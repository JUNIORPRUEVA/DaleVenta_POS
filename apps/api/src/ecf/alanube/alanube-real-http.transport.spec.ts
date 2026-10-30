import { AlanubeRealHttpTransport } from "./alanube-real-http.transport";

describe("AlanubeRealHttpTransport", () => {
  it("rejects non Sandbox URLs before fetch", async () => {
    const fetchSpy = jest.spyOn(global, "fetch" as any);
    const transport = new AlanubeRealHttpTransport();

    await expect(
      transport.execute({
        method: "POST",
        url: "https://api.alanube.co/dom/v1/invoices",
        headers: {},
        timeoutMs: 100,
        requestId: "req",
      }),
    ).resolves.toEqual(
      expect.objectContaining({
        ok: false,
        errorCode: "CONFIGURATION_ERROR",
      }),
    );
    expect(fetchSpy).not.toHaveBeenCalled();
    fetchSpy.mockRestore();
  });

  it("uses fetch only against the allowed sandbox host when invoked by tests", async () => {
    const fetchMock = jest
      .spyOn(global, "fetch" as any)
      .mockResolvedValue(new Response('{"id":"simulated"}', { status: 200 }));
    const transport = new AlanubeRealHttpTransport();

    const result = await transport.execute({
      method: "GET",
      url: "https://sandbox.alanube.co/dom/v1/invoices/simulated",
      headers: { Authorization: "Bearer fake" },
      timeoutMs: 1000,
      requestId: "req",
    });

    expect(result).toEqual(
      expect.objectContaining({
        ok: true,
      }),
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
    fetchMock.mockRestore();
  });

  it.each([0, -1, NaN, Infinity, 30001])("rejects invalid timeout %s before fetch", async (timeoutMs) => {
    const fetchMock = jest.spyOn(global, "fetch").mockRejectedValue(new Error("unexpected"));
    try {
      const result = await new AlanubeRealHttpTransport().execute({ method: "GET",
        url: "https://sandbox.alanube.co/dom/v1/company", headers: {}, timeoutMs, requestId: "req" });
      expect(result).toMatchObject({ ok: false, errorCode: "CONFIGURATION_ERROR" });
      expect(fetchMock).not.toHaveBeenCalled();
    } finally { fetchMock.mockRestore(); }
  });

  it("blocks fiscal POST even when directly invoked", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockRejectedValue(new Error("unexpected"));
    try {
      expect(await new AlanubeRealHttpTransport().execute({ method: "POST",
        url: "https://sandbox.alanube.co/dom/v1/invoices", headers: {}, timeoutMs: 100, requestId: "req" }))
        .toMatchObject({ ok: false, errorCode: "CONFIGURATION_ERROR" });
      expect(fetchMock).not.toHaveBeenCalled();
    } finally { fetchMock.mockRestore(); }
  });

  it("aborts a timed-out read without retrying", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockImplementation((_url, options) => new Promise((_resolve, reject) => {
      options?.signal?.addEventListener("abort", () => reject(new DOMException("timeout", "AbortError")));
    }));
    try {
      expect(await new AlanubeRealHttpTransport().execute({ method: "GET",
        url: "https://sandbox.alanube.co/dom/v1/company", headers: {}, timeoutMs: 10, requestId: "req" }))
        .toMatchObject({ ok: false, errorCode: "TIMEOUT" });
      expect(fetchMock).toHaveBeenCalledTimes(1);
    } finally { fetchMock.mockRestore(); }
  });

  it("caps streamed response bytes", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockResolvedValue(new Response("x".repeat(1024 * 1024 + 1)));
    try {
      expect(await new AlanubeRealHttpTransport().execute({ method: "GET",
        url: "https://sandbox.alanube.co/dom/v1/company", headers: {}, timeoutMs: 1000, requestId: "req" }))
        .toMatchObject({ ok: false, errorCode: "NETWORK_ERROR" });
    } finally { fetchMock.mockRestore(); }
  });
});
