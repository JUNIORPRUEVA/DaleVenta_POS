/**
 * Read-only target snapshot port backed by Prisma.
 * Only SELECT/count operations are issued: this module never writes.
 */

import type { PrismaClient } from '@prisma/client';
import type { TargetReadPort } from './target-validator';
import type { TargetSnapshot } from './types';

export function createPrismaTargetReadPort(prisma: PrismaClient): TargetReadPort {
  return {
    async company(id: string) {
      const row = await prisma.company.findUnique({
        where: { id },
        select: {
          id: true,
          name: true,
          status: true,
          plan: true,
          licenseStatus: true,
          productSource: true,
          maxProducts: true,
        },
      });
      if (!row) return null;
      return {
        id: row.id,
        name: row.name,
        status: String(row.status),
        plan: String(row.plan),
        licenseStatus: String(row.licenseStatus),
        productSource: row.productSource ? String(row.productSource) : null,
        maxProducts: row.maxProducts,
      };
    },

    async warehouse(id: string) {
      const row = await prisma.warehouse.findUnique({
        where: { id },
        select: { id: true, companyId: true, name: true, code: true, isActive: true },
      });
      return row ?? null;
    },

    async terminal(id: string) {
      const row = await prisma.terminal.findUnique({
        where: { id },
        select: {
          id: true,
          companyId: true,
          name: true,
          code: true,
          isActive: true,
          defaultWarehouseId: true,
        },
      });
      return row ?? null;
    },

    async user(id: string) {
      const row = await prisma.user.findUnique({
        where: { id },
        select: { id: true, companyId: true, blocked: true },
      });
      return row ?? null;
    },

    async baseline(companyId: string): Promise<TargetSnapshot['baseline']> {
      const [
        productsTotal,
        productsNonArchived,
        sales,
        saleItems,
        warehouseStocks,
        inventoryMovements,
        cashSessions,
        cashboxDaily,
        cashMovements,
        clients,
        suppliers,
        purchaseOrders,
        taxes,
        ncfSequences,
      ] = await Promise.all([
        prisma.product.count({ where: { companyId } }),
        prisma.product.count({ where: { companyId, archivedAt: null } }),
        prisma.sale.count({ where: { companyId } }),
        prisma.saleItem.count({ where: { sale: { companyId } } }),
        prisma.warehouseStock.count({ where: { companyId } }),
        prisma.inventoryMovement.count({ where: { companyId } }),
        prisma.cashSession.count({ where: { companyId } }),
        prisma.cashboxDaily.count({ where: { companyId } }),
        prisma.cashMovement.count({ where: { companyId } }),
        prisma.client.count({ where: { companyId } }),
        prisma.supplier.count({ where: { companyId } }),
        prisma.purchaseOrder.count({ where: { companyId } }),
        prisma.tax.count({ where: { companyId } }),
        prisma.ncfSequence.count({ where: { companyId } }),
      ]);

      return {
        productsTotal,
        productsNonArchived,
        sales,
        saleItems,
        warehouseStocks,
        inventoryMovements,
        cashSessions,
        cashboxDaily,
        cashMovements,
        clients,
        suppliers,
        purchaseOrders,
        taxes,
        ncfSequences,
      };
    },
  };
}
