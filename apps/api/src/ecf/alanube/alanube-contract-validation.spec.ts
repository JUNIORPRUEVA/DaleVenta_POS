import { createHash } from "node:crypto";
import { ALANUBE_DOM_SCHEMAS } from "./contracts/alanube-dom-schemas.generated";
import { validateAlanubeOfficialRequest, validateAlanubeOfficialResponse } from "./alanube-schema-validator";
import { ALANUBE_CONTRACT_FIXTURES } from "./alanube-contract.fixtures";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
import { validateAlanubeRequestConformance } from "../fiscal-core/alanube-dom.contract";

describe("pinned public DOM contract validation", () => {
  it.each(ALANUBE_CONTRACT_FIXTURES)("validates mapped $name against its actual official schema", ({ document, metadata }) => {
    const before = JSON.stringify({ document, metadata });
    const mapping = mapEcfToAlanubeDom(document, metadata);
    expect(mapping.schemaValidation).toMatchObject({ ok: true, errors: [] });
    expect(mapping.contractStatus).toBe("CONFIRMED_PARTIAL");
    expect(JSON.stringify({ document, metadata })).toBe(before);
    expect(mapping.payload).not.toHaveProperty("companyId");
    expect(mapping.payload.idDoc).not.toHaveProperty("type");
    expect(mapping.payload.sender).not.toHaveProperty("taxId");
  });

  it.each(ALANUBE_CONTRACT_FIXTURES)("rejects missing metadata, wrong types and malformed structure for $name", ({ document, metadata }) => {
    const payload = mapEcfToAlanubeDom(document, metadata).payload;
    for (const invalid of [
      { ...payload, idDoc: {} }, { ...payload, sender: "wrong" },
      { ...payload, totals: { totalAmount: "118" } }, { ...payload, itemDetails: [] },
      { ...payload, companyId: "internal-must-not-leak" },
      { ...payload, itemDetails: [{ ...payload.itemDetails[0], quantityItem: "1" }] },
    ]) expect(validateAlanubeOfficialRequest(document.type, invalid).ok).toBe(false);
  });

  it("requires E31 sequence expiry and buyer but does not invent them for E32", () => {
    const e31 = ALANUBE_CONTRACT_FIXTURES[0];
    const payload = mapEcfToAlanubeDom(e31.document, e31.metadata).payload;
    expect(validateAlanubeOfficialRequest("E31", { ...payload, buyer: undefined }).ok).toBe(false);
    const e32 = ALANUBE_CONTRACT_FIXTURES[3];
    const mapping = mapEcfToAlanubeDom(e32.document, e32.metadata);
    expect(mapping.payload).not.toHaveProperty("buyer");
    expect(mapping.payload.idDoc).not.toHaveProperty("sequenceDueDate");
    expect(mapping.schemaValidation?.ok).toBe(true);
  });

  it("rejects E34 without original reference/date/code or with an excluded referenced type", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[4];
    const payload = mapEcfToAlanubeDom(fixture.document, fixture.metadata).payload;
    for (const informationReference of [undefined, {}, { ...payload.informationReference, ncfModifiedDate: undefined },
      { ...payload.informationReference, ncfModified: "E340000000001" }]) {
      expect(validateAlanubeOfficialRequest("E34", { ...payload, informationReference }).ok).toBe(false);
    }
  });

  it("validates real dates, enums, finite amounts and item bounds", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[0];
    const payload = mapEcfToAlanubeDom(fixture.document, fixture.metadata).payload;
    for (const invalid of [
      { ...payload, idDoc: { ...payload.idDoc, sequenceDueDate: "2026-02-30" } },
      { ...payload, idDoc: { ...payload.idDoc, paymentType: 3 } },
      { ...payload, totals: { totalAmount: Infinity } },
      { ...payload, itemDetails: [{ ...payload.itemDetails[0], itemName: "x".repeat(81) }] },
    ]) expect(validateAlanubeOfficialRequest("E31", invalid).ok).toBe(false);
  });

  it("pins source identity and detects drift even when OpenAPI info.version stays constant", () => {
    for (const contract of Object.values(ALANUBE_DOM_SCHEMAS)) {
      expect(contract.country).toBe("DOM");
      expect(contract.openapi).toBe("3.0.3");
      expect(contract.source).toMatch(/^https:\/\/developer\.alanube\.co\/reference\//);
      const hash = (request: unknown) => createHash("sha256").update(JSON.stringify({ request, responses: contract.responses })).digest("hex");
      expect(hash(contract.request)).toBe(contract.schemaSha256);
      expect(hash({ ...contract.request, required: [] })).not.toBe(contract.schemaSha256);
    }
  });

  it("validates documented error schemas and rejects undocumented response codes", () => {
    expect(validateAlanubeOfficialResponse("E31", 400, { code: "AP3008", message: "Synthetic validation error" }).ok).toBe(true);
    expect(validateAlanubeOfficialResponse("E31", 400, { code: 3, message: [] }).ok).toBe(false);
    expect(validateAlanubeOfficialResponse("E31", 202, {}).ok).toBe(false);
  });

  it("does not default numbering/payment metadata and enforces supported conditional rules", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[0];
    const absent = mapEcfToAlanubeDom(fixture.document);
    expect(absent.payload.idDoc).toEqual({});
    expect(absent.schemaValidation?.ok).toBe(false);
    const credit = mapEcfToAlanubeDom(fixture.document, { ...fixture.metadata, paymentType: 2 });
    expect(credit.schemaValidation?.errors).toContainEqual({ path: "/idDoc/paymentDeadline", keyword: "creditPaymentDeadlineRequired" });
    const dated = mapEcfToAlanubeDom(fixture.document, { ...fixture.metadata, paymentType: 2, paymentDeadline: "2026-11-14" });
    expect(dated.schemaValidation?.ok).toBe(true);
    const note = ALANUBE_CONTRACT_FIXTURES[4];
    const payload = mapEcfToAlanubeDom(note.document, note.metadata).payload;
    const textNote = { ...payload, informationReference: { ...payload.informationReference, modificationCode: 2 as const } };
    expect(validateAlanubeRequestConformance("E34", textNote).ok).toBe(false);
    expect(() => mapEcfToAlanubeDom(fixture.document, { ...fixture.metadata, encf: "E320000000001" })).toThrow("ECF_ALANUBE_ENCF_TYPE_MISMATCH");
  });

  it("does not silently serialize unsupported currency/non-billable semantics", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[0];
    expect(() => mapEcfToAlanubeDom({ ...fixture.document, currency: "USD" }, fixture.metadata))
      .toThrow("ECF_ALANUBE_UNSUPPORTED_CURRENCY_OR_NON_BILLABLE");
  });

  it("maps explicit provider company selection and rejects malformed identifiers", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[0];
    const mapping = mapEcfToAlanubeDom(fixture.document, { ...fixture.metadata, alanubeCompanyId: "01FVJ1528AQRBC7D6K2TGVE5S5" });
    expect(mapping.schemaValidation?.ok).toBe(true);
    expect(mapping.payload.company).toEqual({ id: "01FVJ1528AQRBC7D6K2TGVE5S5" });
    expect(mapEcfToAlanubeDom(fixture.document, { ...fixture.metadata, alanubeCompanyId: "invalid" }).schemaValidation?.ok).toBe(false);
  });

  it("maps rate-specific bases and ITBIS using the existing decimal core", () => {
    const fixture = ALANUBE_CONTRACT_FIXTURES[0];
    for (const [taxCategory, taxRate, total, index, rate] of [
      ["ITBIS_16", "0.16", "116.00", 2, 16], ["ITBIS_0", "0", "100.00", 3, 0],
    ] as const) {
      const document = { ...fixture.document, lines: [{ ...fixture.document.lines[0], taxCategory, taxRate }],
        totals: { ...fixture.document.totals, itbisAmount: String(Number(total) - 100), total } };
      const mapping = mapEcfToAlanubeDom(document, fixture.metadata);
      expect(mapping.schemaValidation?.ok).toBe(true);
      expect(mapping.payload.totals).toMatchObject({ [`i${index}AmountTaxed`]: 100, [`itbisS${index}`]: rate, [`itbis${index}Total`]: Number(total) - 100 });
    }
  });
});
