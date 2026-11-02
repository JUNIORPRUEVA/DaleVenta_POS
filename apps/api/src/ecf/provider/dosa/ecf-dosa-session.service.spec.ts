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

  it("usa ON CONFLICT sobre (company_id, rnc): el duplicado lo impide la BD", async () => {
    const { store, calls } = fakeStore([
      { id: "s-1", status: "NOT_STARTED", session_url: null, created: true },
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
    });
    expect(calls[0].sql).toContain("ON CONFLICT");
    expect(calls[0].sql).toContain('"company_id"');
    expect(calls[0].sql).toContain('"rnc"');
    // El RNC se normaliza antes de llegar a la base.
    expect(calls[0].values).toContain("101000001");
  });

  it("informa si la fila ya existía (no crea una segunda)", async () => {
    const { store } = fakeStore([
      { id: "s-1", status: "RUNNING", session_url: "https://x", created: false },
    ]);
    const service = new EcfDosaSessionService(store);

    const result = await service.claim({ companyId: "company-a", rnc: "101000001" });

    expect(result).toMatchObject({ ok: true, created: false, status: "RUNNING" });
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
    // Tampoco crea filas nuevas.
    expect(sql).not.toContain("INSERT");
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
