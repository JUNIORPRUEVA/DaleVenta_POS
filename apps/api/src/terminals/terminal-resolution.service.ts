import { BadRequestException, Injectable } from "@nestjs/common";
import { Prisma, PrismaClient } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

type Tx = Prisma.TransactionClient | PrismaService | PrismaClient;

export type OperationalTerminalContext = {
  terminal: {
    id: string;
    name: string;
    code: string;
    deviceFingerprint: string | null;
  };
  warehouse: {
    id: string;
    name: string;
    code: string;
  };
  resolution:
    | "explicit-terminal"
    | "bound-device"
    | "default-terminal"
    | "single-active-terminal";
};

export type ResolveOperationalTerminalInput = {
  companyId: string;
  terminalId?: string | null;
  deviceFingerprint?: string | null;
  requestedWarehouseId?: string | null;
};

@Injectable()
export class TerminalResolutionService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveForSale(
    tx: Tx,
    input: ResolveOperationalTerminalInput,
  ): Promise<OperationalTerminalContext> {
    const terminalId = this.clean(input.terminalId);
    const deviceFingerprint = this.clean(input.deviceFingerprint);
    const requestedWarehouseId = this.clean(input.requestedWarehouseId);

    if (terminalId) {
      return this.resolveTerminalById(tx, input.companyId, terminalId, {
        requestedWarehouseId,
        resolution: "explicit-terminal",
      });
    }

    if (deviceFingerprint) {
      const matches = await tx.terminal.findMany({
        where: {
          companyId: input.companyId,
          deviceFingerprint,
          isActive: true,
        },
        include: { defaultWarehouse: true },
        orderBy: { createdAt: "asc" },
        take: 2,
      });
      if (matches.length > 1) {
        throw new BadRequestException(
          "El dispositivo esta asociado a multiples terminales activos; selecciona terminal.",
        );
      }
      if (matches.length === 1) {
        return this.mapTerminal(matches[0], {
          requestedWarehouseId,
          resolution: "bound-device",
        });
      }
    }

    const defaultTerminal = await tx.terminal.findFirst({
      where: { companyId: input.companyId, isDefault: true, isActive: true },
      include: { defaultWarehouse: true },
      orderBy: { createdAt: "asc" },
    });
    if (defaultTerminal) {
      return this.mapTerminal(defaultTerminal, {
        requestedWarehouseId,
        resolution: "default-terminal",
      });
    }

    const activeTerminals = await tx.terminal.findMany({
      where: { companyId: input.companyId, isActive: true },
      include: { defaultWarehouse: true },
      orderBy: { createdAt: "asc" },
      take: 2,
    });
    if (activeTerminals.length === 1) {
      return this.mapTerminal(activeTerminals[0], {
        requestedWarehouseId,
        resolution: "single-active-terminal",
      });
    }

    throw new BadRequestException(
      activeTerminals.length === 0
        ? "No hay terminales activos para registrar la operacion."
        : "Hay multiples terminales activos; selecciona un terminal.",
    );
  }

  private async resolveTerminalById(
    tx: Tx,
    companyId: string,
    terminalId: string,
    options: {
      requestedWarehouseId?: string | null;
      resolution: OperationalTerminalContext["resolution"];
    },
  ) {
    const terminal = await tx.terminal.findFirst({
      where: { id: terminalId, companyId, isActive: true },
      include: { defaultWarehouse: true },
    });
    if (!terminal) {
      throw new BadRequestException("Terminal activo no encontrado.");
    }
    return this.mapTerminal(terminal, options);
  }

  private mapTerminal(
    terminal: {
      id: string;
      companyId: string;
      name: string;
      code: string;
      deviceFingerprint: string | null;
      defaultWarehouseId: string;
      defaultWarehouse: {
        id: string;
        name: string;
        code: string;
        companyId: string;
        isActive: boolean;
      };
    },
    options: {
      requestedWarehouseId?: string | null;
      resolution: OperationalTerminalContext["resolution"];
    },
  ): OperationalTerminalContext {
    if (!terminal.defaultWarehouse?.isActive) {
      throw new BadRequestException(
        "Terminal activo con almacen predeterminado inactivo.",
      );
    }
    if (terminal.defaultWarehouse.companyId !== terminal.companyId) {
      throw new BadRequestException(
        "El almacen predeterminado del terminal pertenece a otra compania.",
      );
    }
    if (
      options.requestedWarehouseId &&
      options.requestedWarehouseId !== terminal.defaultWarehouseId
    ) {
      throw new BadRequestException(
        "El almacen solicitado no coincide con el almacen predeterminado del terminal.",
      );
    }

    return {
      terminal: {
        id: terminal.id,
        name: terminal.name,
        code: terminal.code,
        deviceFingerprint: terminal.deviceFingerprint,
      },
      warehouse: {
        id: terminal.defaultWarehouse.id,
        name: terminal.defaultWarehouse.name,
        code: terminal.defaultWarehouse.code,
      },
      resolution: options.resolution,
    };
  }

  private clean(value?: string | null) {
    const text = value?.trim();
    return text && text.length > 0 ? text : undefined;
  }
}
