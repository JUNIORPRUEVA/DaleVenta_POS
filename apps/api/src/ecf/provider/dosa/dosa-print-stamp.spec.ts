import { dosaPrintStamp } from "./dosa-print-stamp";
import { ecfPrintView } from "../../documents/ecf-print-view";
import { EcfDocumentQueryService } from "../../documents/ecf-document-query.service";

const expected = { encf: "E310000000002", rnc: "133080206", environment: "SANDBOX" as const,
  total: "118.00", buyerRnc: "133306001", issueDate: "2026-11-13" };
const url = "https://ecf.dgii.gov.do/testecf/ConsultaTimbre?RNCEmisor=133080206&RncComprador=133306001&ENCF=E310000000002&FechaEmision=13-11-2026&MontoTotal=118.00&FechaFirma=13-11-2026%2008:45:19&CodigoSeguridad=S9Qvrj";
const body = { estado: "Aceptado", codigo: "1", rnc: expected.rnc, encf: expected.encf,
  url, codigoSeguridad: "S9Qvrj", fechaFirma: "13-11-2026 08:45:19", secuenciaUtilizada: true };

describe("Public e-CF print evidence", () => {
  it("preserves signed fields without provider secrets", () => {
    const stamp = dosaPrintStamp({ ...body, apiKey: "never-return" }, expected);
    expect(stamp).toEqual({ qrUrl: expect.stringContaining("dgii.gov.do/testecf/"), securityCode: "S9Qvrj", signedAt: body.fechaFirma });
    expect(JSON.stringify(stamp)).not.toContain("never-return");
  });
  it.each([
    { ...body, estado: "Rechazado" }, { ...body, url: url.replace("118.00", "119.00") },
    { ...body, url: url.replace("testecf", "ecf") }, { ...body, rnc: "133306001" },
    { ...body, url: url.replace("ecf.dgii.gov.do", "example.com") },
    { ...body, url: url + "&token=secret" }, { ...body, fechaFirma: null },
  ])("blocks mismatched, rejected or incomplete stamps", response => {
    expect(dosaPrintStamp(response, expected)).toBeNull();
  });
  it("keeps legacy environments unclassified", () => {
    expect(ecfPrintView({ id: "doc", documentType: "E31", environment: null, status: "HUMAN_REVIEW_REQUIRED",
      externalDocumentNumber: expected.encf, payloadSummary: {}, fiscalDocument: {} })).toBeNull();
  });
  it("uses the distinct RFCE consultation for E32 below RD$250,000", () => {
    const encf = "E320000000001";
    const response = { ...body, encf,
      url: `https://fc.dgii.gov.do/testecf/ConsultaTimbreFC?RncEmisor=133080206&ENCF=${encf}&MontoTotal=118.00&CodigoSeguridad=S9Qvrj` };
    expect(dosaPrintStamp(response, { ...expected, encf })?.qrUrl).toContain("fc.dgii.gov.do/testecf/ConsultaTimbreFC");
    expect(dosaPrintStamp({ ...response, url: response.url.replace("fc.dgii", "ecf.dgii") }, { ...expected, encf })).toBeNull();
  });
  it("accepts the observed optional RFCE dates only when both match fiscal evidence", () => {
    const encf = "E320000000001";
    const rfce = { ...body, encf, url: `https://fc.dgii.gov.do/testecf/ConsultaTimbreFC?RNCEmisor=133080206&ENCF=${encf}&MontoTotal=118.00&CodigoSeguridad=S9Qvrj&FechaEmision=13-11-2026&FechaFirma=13-11-2026%2008:45:19` };
    expect(dosaPrintStamp(rfce, { ...expected, encf })).not.toBeNull();
    expect(dosaPrintStamp({ ...rfce, url: rfce.url.replace('FechaEmision=13-11-2026', 'FechaEmision=12-11-2026') }, { ...expected, encf })).toBeNull();
    expect(dosaPrintStamp({ ...rfce, url: rfce.url.replace('08:45:19', '09:45:19') }, { ...expected, encf })).toBeNull();
    expect(dosaPrintStamp({ ...rfce, url: rfce.url + '&token=forbidden' }, { ...expected, encf })).toBeNull();
  });
  it("does not expose another tenant's or cashier's sale", async () => {
    const db = { sale: { findFirst: jest.fn().mockResolvedValue(null) }, ecfCompanyConfiguration: { findUnique: jest.fn() } };
    await expect(new EcfDocumentQueryService(db as never).printForSale({ id: "cashier", role: "VENDEDOR", companyId: "company-a" }, "sale-b")).rejects.toThrow("Venta no encontrada");
    expect(db.sale.findFirst).toHaveBeenCalledWith({ where: { id: "sale-b", companyId: "company-a", userId: "cashier" }, select: { id: true } });
    expect(db.ecfCompanyConfiguration.findUnique).not.toHaveBeenCalled();
  });
  it("does not select a fiscal identity silently when multiple documents exist", async () => {
    const db = { sale: { findFirst: jest.fn().mockResolvedValue({id: "sale"}) },
      ecfCompanyConfiguration: { findUnique: jest.fn().mockResolvedValue({enabled:true,environment:"SANDBOX"}) },
      ecfElectronicDocument: { findMany: jest.fn().mockResolvedValue([{}, {}]) } };
    const result = await new EcfDocumentQueryService(db as never).printForSale({id:"admin", role:"ADMIN",companyId:"tenant"}, "sale");
    expect(result).toEqual({document:null,requiresReview:true});
    expect(db.ecfElectronicDocument.findMany.mock.calls[0][0].where).toEqual({companyId:"tenant",environment:"SANDBOX",sourceType:"SALE",sourceId:"sale"});
  });
  it("202 preserves a validated QR with its contingency legend without declaring acceptance", () => {
    const pending={...body,codigo:"3",estado:"Pendiente DGII",leyendaContingencia:"EMITIDO EN CONTINGENCIA - PENDIENTE DGII"};
    expect(dosaPrintStamp(pending,expected)).toBeNull();
    const stamp=dosaPrintStamp(pending,{...expected,allowContingency:true});
    expect(stamp).toMatchObject({qrUrl:url,contingencyLegend:pending.leyendaContingencia});
    expect(dosaPrintStamp({...pending,url:url.replace("118.00","119.00")},{...expected,allowContingency:true})).toBeNull();
  });

});
