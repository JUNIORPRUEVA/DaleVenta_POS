import {
  EcfDosaSessionService,
  type DosaSessionStore,
} from "./ecf-dosa-session.service";

type Call = { sql: string; values: unknown[] };

/** Doble del cliente: captura el SQL parametrizado, no toca ninguna base. */
function fakeStore(
  rows: unknown[],
): { store: DosaSessionStore; calls: Call[] } {
  const calls: Call[] = [];
  const store: DosaSessionStore = {
    async $queryRaw<T>(
      query: TemplateStringsArray,
      ...values: unknown[]
    ): Promise<T> {
      calls.push({ sql: query.join("?"), values });
      return rows as T;
    },
  };
  return { store, calls };
}

describe("EcfDosaSessionService — duplicados transaccionales", () => {
  it("exige empresa y RNC antes de escribir nada", async () => {
    const { store, calls } = fakeStore([]);
    const service = new EcfDosaSessionService(store);

    expect(await service.claim({ companyId: "  ", rnc: "101000001" })).toEqual({
      ok: false,
      reason: "MISSING_COMPANY",
    });
    expect(await service.claim({ companyId: "company-a", rnc: "  " })).toEqual({
      ok: false,
      reason: "MISSING_RNC",
    });
    expect(calls).toHaveLength(0);
  });

  it("usa ON CONFLICT sobre la clave activa: el duplicado lo impide la BD", async () => {
    const { store, calls } = fakeStore([
      {
        id: "s-1",
        status: "NOT_STARTED",
        session_url: null,
        attempt_no: 1,
        created: true,
      },
    ]);
    const service = new EcfDosaSessionService(store);

    const result = await service.claim({
      companyId: "company-a",
      rnc: "1-01-00000-1",
    });

    expect(result).toEqual({
      ok: true,
      id: "s-1",
      status: "NOT_STARTED",
      created: true,
      sessionUrl: null,
      attemptNo: 1,
    });
    expect(calls[0].sql).toContain("ON CONFLICT");
    expect(calls[0].sql).toContain('"active_key"');
    // El intento se numera con MAX+1: es lo que preserva el historial.
    expect(calls[0].sql).toContain('MAX("attempt_no")');
    // El RNC se normaliza antes de llegar a la base.
    expect(calls[0].values).toContain("101000001");
    expect(calls[0].values).toContain("company-a:101000001");
  });

  it("informa si la fila ya existía (no crea una segunda)", async () => {
    const { store } = fakeStore([
      {
        id: "s-1",
        status: "RUNNING",
        session_url: "https://x",
        attempt_no: 3,
        created: false,
      },
    ]);
    const service = new EcfDosaSessionService(store);

    const result = await service.claim({ companyId: "company-a", rnc: "101000001" });

    expect(result).toMatchObject({
      ok: true,
      created: false,
      status: "RUNNING",
      attemptNo: 3,
    });
  });

  it("resuelve la competición: si otra petición ya creó la sesión, devuelve la suya", async () => {
    const calls: Call[] = [];
    const store: DosaSessionStore = {
      async $queryRaw<T>(
        query: TemplateStringsArray,
        ...values: unknown[]
      ): Promise<T> {
        const sql = query.join("?");
        calls.push({ sql, values });
        // El INSERT choca con el intento que creó la otra petición.
        if (sql.includes("INSERT")) {
          throw Object.assign(new Error("dup"), {
            code: "P2010",
            meta: { code: "23505" },
          });
        }
        // La otra petición ya confirmó: se devuelve SU fila.
        return [
          {
            id: "s-winner",
            status: "NOT_STARTED",
            session_url: null,
            attempt_no: 2,
            created: false,
          },
        ] as T;
      },
    };
    const service = new EcfDosaSessionService(store);

    const result = await service.claim({ companyId: "company-a", rnc: "101000001" });

    expect(result).toMatchObject({
      ok: true,
      id: "s-winner",
      attemptNo: 2,
      created: false,
    });
    expect(calls).toHaveLength(2);
    expect(calls[1].sql).toContain("SELECT");
  });

  it("reintenta el insert si el ganador aún no era visible", async () => {
    const calls: Call[] = [];
    let inserts = 0;
    const store: DosaSessionStore = {
      async $queryRaw<T>(
        query: TemplateStringsArray,
        ...values: unknown[]
      ): Promise<T> {
        const sql = query.join("?");
        calls.push({ sql, values });
        if (sql.includes("INSERT")) {
          inserts += 1;
          if (inserts === 1) {
            throw Object.assign(new Error("dup"), {
              code: "P2010",
              meta: { code: "23505" },
            });
          }
          return [
            {
              id: "s-2",
              status: "NOT_STARTED",
              session_url: null,
              attempt_no: 2,
              created: true,
            },
          ] as T;
        }
        return [] as T; // el ganador todavía no es visible
      },
    };
    const service = new EcfDosaSessionService(store);

    const result = await service.claim({ companyId: "company-a", rnc: "101000001" });

    expect(result).toMatchObject({ ok: true, id: "s-2", attemptNo: 2 });
    expect(inserts).toBe(2);
  });

  it("cierra el intento en curso y libera la clave activa", async () => {
    const { store, calls } = fakeStore([{ id: "s-1" }]);
    const service = new EcfDosaSessionService(store);

    const result = await service.close({
      companyId: "company-a",
      rnc: "101000001",
      status: "EXPIRED",
    });

    expect(result).toEqual({ closed: true });
    expect(calls[0].sql).toContain('"active_key" = NULL');
    expect(calls[0].sql).toContain('"closed_at"');
    expect(calls[0].values).toContain("EXPIRED");
  });

  it("un estado no terminal no puede cerrar la sesion", async () => {
    const { store, calls } = fakeStore([{ id: "s-1" }]);
    const service = new EcfDosaSessionService(store);

    // El tipo lo impide; comprobamos que ademas el SQL no se emite.
    await expect(
      service.close({
        companyId: "company-a",
        rnc: "101000001",
        status: "RUNNING" as never,
      }),
    ).rejects.toThrow();
    expect(calls).toHaveLength(0);
  });

  it("un evento del navegador solo escribe la pista, nunca el estado", async () => {
    const { store, calls } = fakeStore([{ id: "s-1" }]);
    const service = new EcfDosaSessionService(store);

    await service.recordEventHint({
      companyId: "company-a",
      rnc: "101000001",
      eventType: "cert:complete",
    });

    const sql = calls[0].sql;
    expect(sql).toContain('"last_event_type"');
    expect(sql).toContain('"last_event_at"');
    // Lo esencial: el evento NO puede tocar estado ni confirmación.
    expect(sql).not.toContain('"status"');
    expect(sql).not.toContain('"provider_confirmed_at"');
    // Tampoco crea filas nuevas ni reabre la sesión.
    expect(sql).not.toContain("INSERT");
    expect(sql).not.toContain('"active_key" = NULL');
  });

  it("rechaza un evento vacío sin tocar la base", async () => {
    const { store, calls } = fakeStore([]);
    const service = new EcfDosaSessionService(store);

    expect(
      await service.recordEventHint({ companyId: "c", rnc: "101000001", eventType: " " }),
    ).toEqual({ updated: false });
    expect(calls).toHaveLength(0);
  });

  it("solo la confirmación del backend marca provider_confirmed_at", async () => {
    const { store, calls } = fakeStore([{ id: "s-1" }]);
    const service = new EcfDosaSessionService(store);

    const result = await service.applyProviderConfirmation({
      companyId: "company-a",
      rnc: "101000001",
      providerPostulationId: "p-1",
    });

    expect(result).toEqual({ updated: true });
    expect(calls[0].sql).toContain('"provider_confirmed_at"');
    expect(calls[0].sql).toContain('"provider_postulation_id"');
    expect(calls[0].values).toContain("p-1");
  });
});
