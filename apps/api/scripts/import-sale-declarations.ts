/**
 * Importación CONTROLADA de declaraciones históricas de cobro recibido.
 *
 * Por defecto NO escribe nada (dry-run). Solo con `--apply`, y solo para la
 * empresa indicada, crea obligaciones de conciliación administrativa.
 *
 * Qué hace y qué NO hace:
 *  - Reutiliza `SaleReconciliationObligationService`, exactamente el mismo
 *    camino que el endpoint real: misma empresa por argumento explícito, mismo
 *    hash de idempotencia, mismo registro append-only.
 *  - NO crea ventas, pagos, movimientos de caja, deudas ni inventario.
 *  - NO toca turnos de caja ni sesiones históricas.
 *  - Reenviar el mismo archivo no duplica: las filas ya importadas se reportan
 *    como `duplicate` y no se escriben.
 *
 * Uso:
 *   npm --workspace apps/api run reconciliation:import -- \
 *     --file ./declaraciones-148.json --company <uuid>        # dry-run
 *   npm --workspace apps/api run reconciliation:import -- \
 *     --file ./declaraciones-148.json --company <uuid> --apply
 *
 * Formato del archivo (UTF-8):
 *   {
 *     "companyId": "<uuid>",              // opcional; debe coincidir con --company
 *     "device": "POS-CAJA-1",
 *     "declarations": [
 *       {
 *         "clientRequestId": "3f2c...",
 *         "totalDeclared": 50.00,          // OBLIGATORIO: nunca se inventa
 *         "declaredAtUtc": "2026-10-27T20:39:00.000Z",
 *         "paymentMethod": "cash",
 *         "declaredByUserId": "user-uuid",
 *         "declaredByRole": "OWNER",
 *         "note": "Cobrado en caja, no salió ticket",
 *         "operationFingerprint": "a1b2...",
 *         "evidence": "auditoría local: MANUAL_MONEY_RECEIVED"
 *       }
 *     ]
 *   }
 */
import { PrismaClient } from "@prisma/client";
import * as fs from "node:fs";
import * as path from "node:path";

import { SaleReconciliationObligationService } from "../src/sales/sale-reconciliation-obligation.service";
import type { TenantUser } from "../src/auth/tenant-context";

type ImportRow = {
  clientRequestId?: unknown;
  totalDeclared?: unknown;
  declaredAtUtc?: unknown;
  paymentMethod?: unknown;
  declaredByUserId?: unknown;
  declaredByRole?: unknown;
  note?: unknown;
  operationFingerprint?: unknown;
  evidence?: unknown;
};

type RowReport = {
  line: number;
  clientRequestId: string | null;
  result: "created" | "duplicate" | "invalid" | "would-create";
  detail?: string;
};

const ISO_UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/;
const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function argValue(flag: string): string | null {
  const index = process.argv.indexOf(flag);
  if (index === -1) return null;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) return null;
  return value.trim();
}

function fail(message: string): never {
  console.error(`\n[import-declarations] ERROR: ${message}\n`);
  process.exit(1);
}

async function main() {
  const apply = process.argv.includes("--apply");
  const file = argValue("--file");
  const companyArg = argValue("--company");

  if (!file) {
    fail("falta --file <ruta del JSON exportado por la app>");
  }
  if (!companyArg || !UUID.test(companyArg)) {
    fail("falta --company <uuid> (la empresa se pasa a mano, nunca se adivina)");
  }
  const absolute = path.resolve(process.cwd(), file);
  if (!fs.existsSync(absolute)) {
    fail(`no existe el archivo ${absolute}`);
  }

  const raw = JSON.parse(fs.readFileSync(absolute, "utf8")) as
    | ImportRow[]
    | { declarations?: ImportRow[]; companyId?: string; device?: string };

  const rows: ImportRow[] = Array.isArray(raw)
    ? raw
    : Array.isArray(raw?.declarations)
      ? raw.declarations
      : fail("el archivo no contiene `declarations` (array)");

  if (!Array.isArray(raw) && raw.companyId && raw.companyId !== companyArg) {
    fail(
      `el archivo dice companyId=${raw.companyId} y se pidió --company=${companyArg}. No se importa nada.`,
    );
  }

  const prisma = new PrismaClient();
  try {
    // La empresa debe existir: no se importa a un tenant inventado.
    const company = await prisma.company.findUnique({
      where: { id: companyArg },
      select: { id: true, name: true },
    });
    if (!company) fail(`no existe la empresa ${companyArg}`);

    const service = new SaleReconciliationObligationService(
      prisma as unknown as ConstructorParameters<
        typeof SaleReconciliationObligationService
      >[0],
    );

    const reports: RowReport[] = [];
    for (let index = 0; index < rows.length; index += 1) {
      const row = rows[index] ?? {};
      const requestId = String(row.clientRequestId ?? "").trim();
      const line = index + 1;
      if (!requestId) {
        reports.push({
          line,
          clientRequestId: null,
          result: "invalid",
          detail: "sin clientRequestId",
        });
        continue;
      }
      const total = Number(row.totalDeclared);
      if (!Number.isFinite(total) || total < 0.01) {
        // El importe NUNCA se inventa: si la exportación no lo trae, la fila
        // queda pendiente de que una persona lo complete con evidencia.
        reports.push({
          line,
          clientRequestId: requestId,
          result: "invalid",
          detail: "totalDeclared ausente o inválido: complétalo a mano",
        });
        continue;
      }
      const declaredAt = String(row.declaredAtUtc ?? "").trim();
      if (!ISO_UTC.test(declaredAt)) {
        reports.push({
          line,
          clientRequestId: requestId,
          result: "invalid",
          detail: "declaredAtUtc debe ser ISO-8601 UTC (…Z)",
        });
        continue;
      }

      const dto = {
        totalDeclared: Math.round(total * 100) / 100,
        declaredAtUtc: declaredAt,
        paymentMethod: String(row.paymentMethod ?? "cash").trim() || "cash",
        declaredByUserId: row.declaredByUserId
          ? String(row.declaredByUserId).trim()
          : undefined,
        declaredByRole: row.declaredByRole
          ? String(row.declaredByRole).trim()
          : undefined,
        note: row.note ? String(row.note).trim() : "Importación histórica",
        operationFingerprint: row.operationFingerprint
          ? String(row.operationFingerprint).trim()
          : undefined,
      };

      if (!apply) {
        // Dry-run: se comprueba si ya existe la obligación (mismo hash) sin
        // escribir absolutamente nada.
        const hash = SaleReconciliationObligationService.declarationHash({
          companyId: companyArg,
          clientRequestId: requestId,
          totalDeclared: dto.totalDeclared.toFixed(2),
          declaredAtUtc: dto.declaredAtUtc,
          declaredByUserId: dto.declaredByUserId ?? "import-historical",
          note: dto.note,
        });
        const existing = await prisma.saleReconciliationObligation.findFirst({
          where: {
            companyId: companyArg,
            clientRequestId: requestId,
            declarationHash: hash,
          },
          select: { id: true },
        });
        reports.push({
          line,
          clientRequestId: requestId,
          result: existing ? "duplicate" : "would-create",
          detail: existing ? `ya existe ${existing.id}` : undefined,
        });
        continue;
      }

      const actor = {
        id: dto.declaredByUserId ?? "import-historical",
        companyId: companyArg,
        role: dto.declaredByRole ?? "IMPORT",
      } as unknown as TenantUser;

      try {
        const { obligation, duplicate } = await service.recordDeclaration(
          actor,
          requestId,
          dto as never,
        );
        reports.push({
          line,
          clientRequestId: requestId,
          result: duplicate ? "duplicate" : "created",
          detail: obligation.id,
        });
      } catch (error) {
        reports.push({
          line,
          clientRequestId: requestId,
          result: "invalid",
          detail: error instanceof Error ? error.message : String(error),
        });
      }
    }

    const summary = {
      mode: apply ? "apply" : "dry-run",
      file: absolute,
      company: { id: company.id, name: company.name },
      totals: {
        rows: reports.length,
        created: reports.filter((r) => r.result === "created").length,
        wouldCreate: reports.filter((r) => r.result === "would-create").length,
        duplicate: reports.filter((r) => r.result === "duplicate").length,
        invalid: reports.filter((r) => r.result === "invalid").length,
      },
      reports,
      notes: [
        "Este proceso NO crea ventas, pagos, movimientos de caja ni inventario.",
        "No modifica turnos de caja históricos.",
        "Reejecutarlo es seguro: las filas ya importadas se reportan como duplicate.",
      ],
    };
    console.log(JSON.stringify(summary, null, 2));

    if (!apply) {
      console.log(
        "\n[import-declarations] dry-run: no se escribió nada. Repite con --apply tras la autorización.",
      );
    }
  } finally {
    await prisma.$disconnect();
  }
}

void main().catch((error) => {
  console.error(error);
  process.exit(1);
});
