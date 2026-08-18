import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import { CreateNcfSequenceDto, UpdateNcfSequenceDto } from "./tax.dto";

type Tx = Prisma.TransactionClient;

@Injectable()
export class NcfService {
  constructor(private readonly prisma: PrismaService) {}

  async listSequences(user: TenantUser) {
    const companyId = requireTenant(user);
    const rows = await this.prisma.ncfSequence.findMany({
      where: { companyId },
      orderBy: [{ voucherType: "asc" }, { createdAt: "desc" }],
    });
    return rows.map((row) => ({ ...row, status: this.sequenceStatus(row) }));
  }

  async createSequence(user: TenantUser, dto: CreateNcfSequenceDto) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const type = this.normalizeType(dto.voucherType);
    const prefix = dto.prefix.trim().toUpperCase();
    if (prefix !== type) {
      throw new BadRequestException("El prefijo de la secuencia debe coincidir con el tipo B01/B02.");
    }
    if (dto.endNumber < dto.startNumber) {
      throw new BadRequestException("El final de la secuencia no puede ser menor que el inicio.");
    }
    await this.assertSequenceCanBeActive(companyId, type, {
      startNumber: dto.startNumber,
      endNumber: dto.endNumber,
      active: dto.active ?? true,
    });
    return this.prisma.ncfSequence.create({
      data: {
        companyId,
        voucherType: type,
        prefix,
        startNumber: dto.startNumber,
        nextNumber: dto.startNumber,
        endNumber: dto.endNumber,
        validUntil: dto.validUntil ? new Date(dto.validUntil) : null,
        active: dto.active ?? true,
      },
    });
  }

  async updateSequence(user: TenantUser, id: string, dto: UpdateNcfSequenceDto) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const existing = await this.prisma.ncfSequence.findFirst({ where: { id, companyId } });
    if (!existing) throw new NotFoundException("Secuencia NCF no encontrada.");
    if (dto.endNumber !== undefined && dto.endNumber < existing.nextNumber - 1) {
      throw new BadRequestException("El final no puede quedar por debajo de los NCF ya emitidos.");
    }
    await this.assertSequenceCanBeActive(companyId, existing.voucherType, {
      id,
      startNumber: existing.startNumber,
      endNumber: dto.endNumber ?? existing.endNumber,
      active: dto.active ?? existing.active,
    });
    return this.prisma.ncfSequence.update({
      where: { id },
      data: {
        ...(dto.endNumber !== undefined ? { endNumber: dto.endNumber } : {}),
        ...(dto.validUntil !== undefined
          ? { validUntil: dto.validUntil ? new Date(dto.validUntil) : null }
          : {}),
        ...(dto.active !== undefined ? { active: dto.active } : {}),
      },
    });
  }

  async reserveNextNcf(tx: Tx, params: {
    companyId: string;
    userId: string;
    voucherType: string;
  }) {
    const type = this.normalizeType(params.voucherType);
    const rows = await tx.$queryRaw<Array<{
      id: string;
      company_id: string;
      voucher_type: string;
      prefix: string;
      start_number: number;
      next_number: number;
      end_number: number;
      valid_until: Date | null;
      active: boolean;
    }>>`
      SELECT id, company_id, voucher_type, prefix, start_number, next_number, end_number, valid_until, active
      FROM ncf_sequences
      WHERE company_id = ${params.companyId}::uuid
        AND voucher_type = ${type}
        AND active = true
      ORDER BY created_at ASC
      FOR UPDATE
    `;

    const now = new Date();
    const sequence = rows.find((row) => {
      if (!row.active) return false;
      if (row.valid_until && row.valid_until.getTime() < now.getTime()) return false;
      return row.next_number <= row.end_number;
    });

    if (!sequence) {
      throw new BadRequestException(`No hay secuencia ${type} activa con capacidad disponible.`);
    }

    const nextNumber = sequence.next_number;
    const ncf = `${sequence.prefix}${String(nextNumber).padStart(8, "0")}`;
    await tx.ncfSequence.update({
      where: { id: sequence.id },
      data: { nextNumber: { increment: 1 } },
    });
    await tx.ncfAuditLog.create({
      data: {
        companyId: params.companyId,
        sequenceId: sequence.id,
        userId: params.userId,
        ncf,
        type,
        action: "RESERVED",
      },
    });
    return { ncf, sequenceId: sequence.id, type };
  }

  async markIssued(tx: Tx, params: {
    companyId: string;
    sequenceId?: string | null;
    saleId: string;
    userId: string;
    ncf: string;
    type: string;
  }) {
    await tx.ncfAuditLog.create({
      data: {
        companyId: params.companyId,
        sequenceId: params.sequenceId ?? null,
        saleId: params.saleId,
        userId: params.userId,
        ncf: params.ncf,
        type: this.normalizeType(params.type),
        action: "ISSUED",
      },
    });
  }

  normalizeType(value: string) {
    const type = value.trim().toUpperCase();
    if (type !== "B01" && type !== "B02") {
      throw new BadRequestException("Solo B01 y B02 están habilitados en esta fase.");
    }
    return type;
  }

  sequenceStatus(sequence: {
    active: boolean;
    nextNumber: number;
    endNumber: number;
    validUntil: Date | null;
  }) {
    if (!sequence.active) return "DISABLED";
    if (sequence.validUntil && sequence.validUntil.getTime() < Date.now()) return "EXPIRED";
    if (sequence.nextNumber > sequence.endNumber) return "EXHAUSTED";
    return "ACTIVE";
  }

  private requireAdmin(user: TenantUser) {
    if (!isAdminLike(user)) {
      throw new ForbiddenException("Solo un administrador puede administrar secuencias NCF.");
    }
  }

  private async assertSequenceCanBeActive(
    companyId: string,
    voucherType: string,
    candidate: {
      id?: string;
      startNumber: number;
      endNumber: number;
      active: boolean;
    },
  ) {
    if (!candidate.active) return;
    const existingActive = await this.prisma.ncfSequence.findMany({
      where: {
        companyId,
        voucherType,
        active: true,
        ...(candidate.id ? { id: { not: candidate.id } } : {}),
      },
      select: {
        id: true,
        startNumber: true,
        endNumber: true,
      },
    });
    if (existingActive.length > 0) {
      throw new BadRequestException(
        `Ya existe una secuencia ${voucherType} activa para esta empresa. Desactívala antes de activar otra.`,
      );
    }
    const overlapping = await this.prisma.ncfSequence.findFirst({
      where: {
        companyId,
        voucherType,
        ...(candidate.id ? { id: { not: candidate.id } } : {}),
        startNumber: { lte: candidate.endNumber },
        endNumber: { gte: candidate.startNumber },
      },
      select: { id: true },
    });
    if (overlapping) {
      throw new BadRequestException(
        `La secuencia ${voucherType} se solapa con un rango ya registrado.`,
      );
    }
  }
}
