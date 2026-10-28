import { BadRequestException, Injectable } from "@nestjs/common";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";

/**
 * Conciliación de un intento de cobro (`sales.attempt`).
 *
 * Contexto: el cliente guarda un intento durable ANTES de enviar la venta, para
 * no cobrar dos veces si la respuesta se pierde. Cuando el resultado remoto es
 * desconocido, el intento queda en `requires_action` y hasta ahora solo se
 * resolvía con soporte técnico presencial.
 *
 * Este servicio responde una única pregunta, en modo ESTRICTAMENTE DE LECTURA:
 * "¿qué sabe el servidor de este `clientRequestId`?".
 *
 * Reglas no negociables:
 *  - Solo lectura: no crea ventas, pagos, movimientos ni turnos.
 *  - Aislamiento por empresa: `companyId` sale del token, nunca del cliente.
 *  - `NOT_FOUND` y `UNKNOWN` NO autorizan a reintentar ni a borrar el intento.
 *  - Una fila de venta no demuestra por sí sola que el dinero entró (puede ser
 *    transferencia, crédito o estar anulada); por eso se devuelve el método de
 *    pago y el estado real de la fila.
 */

/**
 * Resultado del REGISTRO de la operación. Nada más.
 *
 * Deliberadamente NO dice si el dinero entró ni si fue rechazado:
 *  - Una venta registrada y luego anulada sigue siendo un registro CONFIRMADO
 *    (el cobro llegó al servidor una vez y se deshizo por el camino correcto).
 *    Por eso la anulación se informa aparte en `voided`, no como rechazo.
 *  - `DEFINITIVELY_REJECTED` queda reservado para cuando exista una prueba
 *    almacenada de rechazo. Hoy no existe esa fuente, así que el servicio no lo
 *    emite nunca; está en el contrato para no cerrar la puerta a ese dato.
 */
export type SaleAttemptReconciliationStatus =
  | "CONFIRMED"
  | "DEFINITIVELY_REJECTED"
  | "NOT_FOUND"
  | "UNKNOWN";

export type SaleAttemptReconciliationGuidance =
  | "ALREADY_REGISTERED"
  | "REGISTERED_THEN_VOIDED"
  | "VOIDED_ON_SERVER"
  | "NOT_REGISTERED"
  | "INCONCLUSIVE";

const MECHANISM = "sale-attempt-reconciliation-v1";
const MAX_REQUEST_ID_LENGTH = 200;
const MONEY_EPSILON = 0.005;

const saleSelect = {
  id: true,
  saleDate: true,
  totalSold: true,
  paymentMethod: true,
  status: true,
  kind: true,
  isDeleted: true,
  cancelledAt: true,
  cashSessionId: true,
  terminalNameSnapshot: true,
} as const;

const movementSelect = {
  id: true,
  type: true,
  amount: true,
  createdAt: true,
} as const;

@Injectable()
export class SaleAttemptReconciliationService {
  constructor(private readonly prisma: PrismaService) {}

  async reconcile(
    user: TenantUser,
    clientRequestId: string,
    expectedTotalSoldRaw?: string,
  ) {
    const companyId = requireTenant(user);
    const requestId = `${clientRequestId ?? ""}`.trim();

    if (!requestId) {
      throw new BadRequestException({
        code: "SALE_ATTEMPT_REQUEST_ID_REQUIRED",
        message: "Falta el identificador del intento de cobro.",
      });
    }
    if (requestId.length > MAX_REQUEST_ID_LENGTH) {
      throw new BadRequestException({
        code: "SALE_ATTEMPT_REQUEST_ID_INVALID",
        message: "El identificador del intento de cobro no es válido.",
      });
    }

    const expectedTotal = this.parseMoney(expectedTotalSoldRaw);

    const sale = await this.prisma.sale.findFirst({
      where: { companyId, clientRequestId: requestId },
      select: saleSelect,
    });

    /*
     * Un movimiento de caja con el mismo `operationId` demuestra que la petición
     * llegó al servidor, pero NO es una venta: el resultado sigue sin poder
     * confirmarse. Se consulta solo cuando no hay venta, para no abrir dos
     * consultas en el caso normal.
     */
    const movement = sale
      ? null
      : await this.prisma.cashMovement.findFirst({
          where: { companyId, operationId: requestId },
          select: movementSelect,
        });

    const status = this.resolveStatus(sale, movement);
    const recordedTotal = sale ? this.toNumber(sale.totalSold) : null;
    const voided = sale ? this.isVoided(sale) : false;

    return {
      status,
      guidance: this.resolveGuidance(status, voided),
      mechanism: MECHANISM,
      clientRequestId: requestId,
      checkedAt: new Date().toISOString(),
      /** El servidor nunca autoriza a repetir el cobro desde esta consulta. */
      retryAllowed: false,
      /** Una fila de venta no demuestra que el dinero entró (transferencia,
       *  crédito o anulación posterior). Nunca se afirma aquí. */
      assertsPaymentReceived: false,
      voided,
      voidReason: sale ? this.voidReason(sale) : null,
      expectedTotalSold: expectedTotal,
      recordedTotalSold: recordedTotal,
      matchesExpected:
        expectedTotal === null || recordedTotal === null
          ? null
          : Math.abs(expectedTotal - recordedTotal) < MONEY_EPSILON,
      sale: sale
        ? {
            id: sale.id,
            saleDate: this.toIso(sale.saleDate),
            totalSold: recordedTotal,
            paymentMethod: sale.paymentMethod ?? null,
            status: sale.status,
            kind: sale.kind,
            isDeleted: sale.isDeleted === true,
            cancelledAt: this.toIso(sale.cancelledAt),
            cashSessionId: sale.cashSessionId ?? null,
            terminalName: sale.terminalNameSnapshot ?? null,
          }
        : null,
      movement: movement
        ? {
            id: movement.id,
            type: movement.type,
            amount: this.toNumber(movement.amount),
            createdAt: this.toIso(movement.createdAt),
          }
        : null,
    };
  }

  private resolveStatus(
    sale: { isDeleted: boolean; cancelledAt: Date | null } | null,
    movement: unknown,
  ): SaleAttemptReconciliationStatus {
    /*
     * Si la fila existe, la operación SE REGISTRÓ, aunque después se anule o se
     * borre: eso es un hecho del registro, no un rechazo. La anulación se
     * informa en `voided` / `voidReason` para que el cliente no la confunda con
     * un cobro fallido.
     */
    if (sale) return "CONFIRMED";
    if (movement) return "UNKNOWN";
    return "NOT_FOUND";
  }

  private isVoided(sale: { isDeleted: boolean; cancelledAt: Date | null }) {
    return sale.isDeleted === true || sale.cancelledAt !== null;
  }

  private voidReason(
    sale: { isDeleted: boolean; cancelledAt: Date | null },
  ): "DELETED" | "CANCELLED" | null {
    if (sale.cancelledAt !== null) return "CANCELLED";
    if (sale.isDeleted === true) return "DELETED";
    return null;
  }

  private resolveGuidance(
    status: SaleAttemptReconciliationStatus,
    voided: boolean,
  ): SaleAttemptReconciliationGuidance {
    switch (status) {
      case "CONFIRMED":
        return voided ? "REGISTERED_THEN_VOIDED" : "ALREADY_REGISTERED";
      case "UNKNOWN":
        return "INCONCLUSIVE";
      default:
        return "NOT_REGISTERED";
    }
  }

  private parseMoney(raw?: string): number | null {
    const text = `${raw ?? ""}`.trim();
    if (!text) return null;
    const value = Number(text);
    return Number.isFinite(value) ? value : null;
  }

  private toNumber(value: unknown): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === "number") return value;
    const parsed = Number(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private toIso(value: unknown): string | null {
    if (!value) return null;
    if (value instanceof Date) return value.toISOString();
    const parsed = new Date(`${value}`);
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }
}
