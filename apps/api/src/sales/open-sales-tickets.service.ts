import { Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import { requireTenant, type TenantUser } from "../auth/tenant-context";

@Injectable()
export class OpenSalesTicketsService {
  constructor(private readonly prisma: PrismaService) {}

  async getState(user: TenantUser) {
    const companyId = requireTenant(user);
    const row = await this.prisma.openSalesTicketState.findUnique({
      where: { companyId },
    });

    return {
      companyId,
      activeId: row?.activeTicketId ?? null,
      tickets: Array.isArray(row?.tickets) ? row.tickets : [],
      updatedAt: row?.updatedAt?.toISOString() ?? null,
      updatedByUserId: row?.updatedByUserId ?? null,
    };
  }

  async replaceState(user: TenantUser, dto: unknown) {
    const companyId = requireTenant(user);
    const body = this.asRecord(dto);
    const activeId = this.optionalString(body["activeId"]);
    const rawTickets = Array.isArray(body["tickets"]) ? body["tickets"] : [];
    const tickets = rawTickets
      .filter((row): row is Record<string, unknown> => this.isRecord(row))
      .map((row) => this.sanitizeTicket(row, companyId, user));

    const saved = await this.prisma.openSalesTicketState.upsert({
      where: { companyId },
      create: {
        companyId,
        activeTicketId: activeId,
        tickets: tickets as Prisma.InputJsonValue,
        updatedByUserId: user.id,
      },
      update: {
        activeTicketId: activeId,
        tickets: tickets as Prisma.InputJsonValue,
        updatedByUserId: user.id,
      },
    });

    return {
      companyId,
      activeId: saved.activeTicketId,
      tickets,
      updatedAt: saved.updatedAt.toISOString(),
      updatedByUserId: saved.updatedByUserId,
    };
  }

  private sanitizeTicket(
    row: Record<string, unknown>,
    companyId: string,
    user: TenantUser,
  ) {
    const ticket = { ...row };
    ticket["companyId"] = companyId;
    ticket["id"] = this.optionalString(ticket["id"]) || `${Date.now()}`;
    ticket["title"] = this.optionalString(ticket["title"]) || "Ticket";
    ticket["createdAt"] =
      this.optionalString(ticket["createdAt"]) || new Date().toISOString();
    ticket["createdByUserId"] =
      this.optionalString(ticket["createdByUserId"]) || user.id;
    ticket["createdByUserName"] =
      this.optionalString(ticket["createdByUserName"]) ||
      this.optionalString((user as { email?: string }).email) ||
      "Usuario";
    ticket["items"] = Array.isArray(ticket["items"]) ? ticket["items"] : [];
    ticket["selectedCategories"] = Array.isArray(ticket["selectedCategories"])
      ? ticket["selectedCategories"]
      : [];
    return ticket;
  }

  private asRecord(value: unknown): Record<string, unknown> {
    return this.isRecord(value) ? value : {};
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }

  private optionalString(value: unknown): string | null {
    if (typeof value !== "string") return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }
}
