import { Role } from "@prisma/client";
import { UsersService } from "./users.service";

/**
 * Fase 2 — Formulario «Nuevo usuario» de solo acceso.
 *
 * Cubre con fixtures (sin base de datos real) los casos A, B y C del plan:
 * - Caso B: alta sin cédula, fecha de ingreso, teléfono ni número de flota.
 * - Caso A: edición de un usuario histórico sin perder cédula ni fecha de
 *   ingreso (el payload parcial nunca incluye esas claves).
 * - Caso C: un usuario creado sin número de flota puede editarse igual.
 */
function buildService(prisma: any) {
  const config = { get: jest.fn().mockReturnValue(undefined) };
  const licenses = {
    assertCanCreateUser: jest.fn().mockResolvedValue(undefined),
    assertCanCreateUserInTransaction: jest.fn().mockResolvedValue(undefined),
  };
  const realtime = { emitCompanyUser: jest.fn() };
  const service = new UsersService(
    prisma,
    config as any,
    licenses as any,
    realtime as any,
  );
  return { service, realtime };
}

const requestUser = {
  id: "admin-1",
  role: Role.ADMIN,
  companyId: "company-1",
};

describe("UsersService — alta y edición de solo acceso", () => {
  it("Caso B: crea el usuario sin cédula, fecha de ingreso, teléfono ni número de flota", async () => {
    const captured: any[] = [];
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue(null),
        findUniqueOrThrow: jest.fn().mockResolvedValue({ id: "user-new" }),
      },
      $transaction: jest.fn(async (fn: any) =>
        fn({
          user: {
            create: jest.fn(async ({ data }: any) => {
              captured.push(data);
              return { id: "user-new" };
            }),
          },
          companyMember: { create: jest.fn().mockResolvedValue({}) },
        }),
      ),
    };
    const { service } = buildService(prisma);

    await service.create(requestUser as any, {
      email: "Nuevo.Usuario@Empresa.test",
      password: "ClaveSegura123",
      nombreCompleto: "Usuario Nuevo",
      edad: 0,
      role: Role.CAJERO,
    } as any);

    expect(captured).toHaveLength(1);
    const data = captured[0];
    // No se inventan valores: las columnas opcionales quedan vacías.
    expect(data.cedula).toBeUndefined();
    expect(data.fechaIngreso).toBeUndefined();
    expect(data.numeroFlota).toBeUndefined();
    // `telefono` es NOT NULL: se guarda vacío, no un número ficticio.
    expect(data.telefono).toBe("");
    expect(data.nombreCompleto).toBe("Usuario Nuevo");
    expect(data.role).toBe(Role.CAJERO);
  });

  it("Caso A + C: editar un usuario histórico no envía cédula ni fecha de ingreso", async () => {
    const updates: any[] = [];
    const existing = {
      id: "user-historico",
      role: Role.CAJERO,
      blocked: false,
      numeroFlota: null,
      cedula: "001-1234567-8",
      fechaIngreso: new Date("2020-01-15T00:00:00.000Z"),
    };
    const prisma = {
      user: {
        findFirst: jest.fn().mockResolvedValue(existing),
        findUnique: jest.fn().mockResolvedValue(null),
        update: jest.fn(async ({ data }: any) => {
          updates.push(data);
          return { id: "user-historico" };
        }),
      },
      companyMember: {
        findFirst: jest.fn().mockResolvedValue(null),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      $transaction: jest.fn(async (fn: any) =>
        fn({
          user: { update: prisma.user.update },
          companyMember: { updateMany: prisma.companyMember.updateMany },
        }),
      ),
    };
    const { service } = buildService(prisma);
    // El retorno final relee el usuario con SQL crudo: no aporta a la prueba.
    jest.spyOn(service, "findById").mockResolvedValue({} as any);

    await service.update(requestUser as any, "user-historico", {
      nombreCompleto: "Nombre Actualizado",
    } as any);

    expect(updates).toHaveLength(1);
    const data = updates[0];
    expect(data.nombreCompleto).toBe("Nombre Actualizado");
    // La actualización es parcial: las claves omitidas no se tocan.
    expect(data).not.toHaveProperty("cedula");
    expect(data).not.toHaveProperty("fechaIngreso");
    expect(data).not.toHaveProperty("numeroFlota");
    expect(data).not.toHaveProperty("telefono");
  });
});
