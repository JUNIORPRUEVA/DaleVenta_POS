import {
  businessDateRange,
  formatBusinessDay,
  parseBusinessBoundary,
  parseServerInstant,
} from "./business-time.util";

describe("business-time.util", () => {
  it("convierte el día de negocio dominicano a rango UTC exclusivo", () => {
    expect(businessDateRange("2026-09-15", "2026-09-15")).toEqual({
      gte: new Date("2026-09-15T04:00:00.000Z"),
      lt: new Date("2026-09-16T04:00:00.000Z"),
    });
  });

  it("atribuye correctamente ventas alrededor de medianoche RD", () => {
    const beforeMidnight = new Date("2026-09-16T03:59:00.000Z");
    const afterMidnight = new Date("2026-09-16T04:01:00.000Z");

    expect(formatBusinessDay(beforeMidnight)).toBe("2026-09-15");
    expect(formatBusinessDay(afterMidnight)).toBe("2026-09-16");
  });

  it("acepta ISO con Z u offset explícito sin doble conversión", () => {
    expect(parseServerInstant("2026-09-16T04:01:00.000Z")).toEqual(
      new Date("2026-09-16T04:01:00.000Z"),
    );
    expect(parseServerInstant("2026-09-16T00:01:00.000-04:00")).toEqual(
      new Date("2026-09-16T04:01:00.000Z"),
    );
  });

  it("rechaza timestamps ambiguos sin Z ni offset", () => {
    expect(() => parseServerInstant("2026-09-16T04:01:00")).toThrow(
      /Timestamp ambiguo/,
    );
  });

  it("parsea boundaries date-only con America/Santo_Domingo", () => {
    expect(parseBusinessBoundary("2026-09-16", true)).toEqual(
      new Date("2026-09-16T04:00:00.000Z"),
    );
    expect(parseBusinessBoundary("2026-09-16", false)).toEqual(
      new Date("2026-09-17T04:00:00.000Z"),
    );
  });
});
