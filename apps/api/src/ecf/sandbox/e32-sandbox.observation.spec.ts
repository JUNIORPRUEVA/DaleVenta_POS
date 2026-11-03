import { e32SafeObservation } from "./e32-sandbox.observation";
import { e32FirstTrialTaxConsistent, firstE32Document } from "./e32-sandbox.policy";
import { mapEcfToAlanubeDom } from "../fiscal-core/alanube-dom.mapper";
describe("single authorized E32 fiscal check and safe observation",()=>{
  it("charges 18 only on the 100 taxable line and rejects charging tax on the exempt 50",()=>{
    const p=mapEcfToAlanubeDom(firstE32Document({taxId:"101000001",legalName:"SYNTHETIC",address:"Synthetic"},"2026-10-14"),{encf:"E320000000001",paymentType:1,incomeType:1}).payload;
    expect(e32FirstTrialTaxConsistent(p)).toBe(true);
    expect(e32FirstTrialTaxConsistent({...p,totals:{...p.totals,itbisTotal:27,totalAmount:177}})).toBe(false);
    expect(e32FirstTrialTaxConsistent({...p,itemDetails:p.itemDetails.map(x=>({...x,billingIndicator:1}))})).toBe(false);
  });
  it("records sequence flag/status/errors but excludes headers, certificate and XML",()=>{
    const body={id:"01FVJ1528AQRBC7D6K2TGVE5S5",legalStatus:"REJECTED",sequenceConsumed:false,documentNumber:"E320000000001",governmentResponse:{code:2,value:[{codigo:"04",valor:"Synthetic rejection"}]},xml:"private",authorization:"secret",message:"Bearer synthetic-marker"};
    const out=e32SafeObservation("POST",201,body,Buffer.from(JSON.stringify(body)));
    expect(out).toMatchObject({legalStatus:"REJECTED",sequenceConsumed:false,governmentResponse:{code:"2",value:[{codigo:"04",valor:"Synthetic rejection"}]},message:"[REDACTED]"});
    expect(out).not.toHaveProperty("xml");expect(out).not.toHaveProperty("authorization");expect(out.responseSha256).toMatch(/^[a-f0-9]{64}$/);
  });
});
