import { dec, moneyString } from "../fiscal-core/ecf-money";
import type { EcfFiscalDocument } from "../fiscal-core/ecf-fiscal-document";

/** Recover original payment evidence, excluding subsequent credit collections. */
export function salePaymentForms(input: {
  method: string; total: string; cash: string; transfer: string;
  collectedCash?: string; collectedTransfer?: string;
}): EcfFiscalDocument["paymentForms"] {
  const total = dec(input.total);
  if (total.lte(0)) throw new Error("ECF_PAYMENT_TOTAL_INVALID");
  if (input.method === "cash" || input.method === "transfer") {
    return [{ code: input.method === "cash" ? "1" : "2", amount: moneyString(total) }];
  }
  if (!["credit", "mixed"].includes(input.method)) throw new Error("ECF_PAYMENT_METHOD_UNSUPPORTED");
  const cash = dec(input.cash).minus(input.collectedCash ?? 0);
  const transfer = dec(input.transfer).minus(input.collectedTransfer ?? 0);
  const credit = total.minus(cash).minus(transfer);
  if ([cash, transfer, credit].some(amount => amount.lt(0))) throw new Error("ECF_PAYMENT_AMOUNTS_INCOHERENT");
  const entries = [["1", cash], ["2", transfer], ["4", credit]] as const;
  return entries.filter(([, amount]) => amount.gt(0)).map(([code, amount]) => ({ code, amount: moneyString(amount) }));
}
