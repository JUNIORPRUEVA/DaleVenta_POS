// Real credit accounting checks on the dedicated loopback lab. No old data repair.
const fs = require('node:fs'), crypto = require('node:crypto'), assert = require('node:assert/strict');
const { PrismaClient } = require('@prisma/client');
const base = 'http://127.0.0.1:14627', dir = '.uat/credit-ticket';
const db = new PrismaClient({ datasources: { db: { url: 'postgresql://postgres@127.0.0.1:14626/fullpos_credit_ticket_20261126' } } });
const snapshots = [], checks = [];
const money = value => Math.round(Number(value) * 100) / 100;
async function request(route, token, body, status = body ? 201 : 200) {
  const r = await fetch(base + route, { method: body ? 'POST' : 'GET',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  const result = await r.json();
  assert.equal(r.status, status, `${route}: ${r.status} ${JSON.stringify(result).slice(0,200)}`);
  return result;
}
async function tenant(suffix) {
  const id = crypto.randomUUID(), password = crypto.randomBytes(24).toString('hex') + 'aA1!';
  const auth = await request('/auth/register-business', null, { commercialName: `Credit accounting ${suffix} ${id}`, firstName: 'Prueba', lastName: 'Contable', email: `${id}@example.test`, password, confirmPassword: password, phone: '8095550100' });
  const token = auth.accessToken, companyId = auth.user.companyId;
  const api = (route,body,status) => request(route,token,body,status);
  const cash = await api('/cash/sessions/open', { openingAmount: 0 });
  const customer = await api('/clients', { nombre: `Cliente contable ${suffix}`, telefono: '8095550101' });
  const product = await api('/products', { nombre: `Producto contable ${id}`, categoria: 'CreditAudit', precio: 250, costo: 100, stock: 100, operationId: crypto.randomUUID() });
  const sale = await api('/sales', { clientRequestId: crypto.randomUUID(), originCashSessionId: cash.shiftId, customerId: customer.id,
    paymentMethod: 'credit', paymentCashAmount: 1000, paymentTransferAmount: 0, creditAmount: 1500, cashReceived: 1000, changeAmount: 0, expectedTotalSold: 2500,
    items: [{ productId: product.id, qty: 10, priceSoldUnit: 250 }] });
  return { api, companyId, token, user: auth.user, sessionId: cash.shiftId, customerId: customer.id, productId: product.id, saleId: sale.id || sale.sale?.id };
}
const date = input => input.toISOString().slice(0,10);
const today = date(new Date());
async function snapshot(t,label,day = today) {
  const sale = await db.sale.findFirstOrThrow({ where: { id:t.saleId,companyId:t.companyId },include:{items:true,creditPayments:true} });
  const cash = await t.api('/cash/summary');
  const report = await t.api(`/reports/sales-overview?from=${day}&to=${day}`);
  const customer = await t.api(`/clients/${t.customerId}/profile`);
  const product = await db.product.findFirstOrThrow({where:{id:t.productId,companyId:t.companyId}});
  const result = {label, sale,cash,report,customer,stock:product.stock};snapshots.push(result);return result;
}
async function main() {
  const owned = JSON.parse(fs.readFileSync(dir+'/owned-api-pid.json','utf8'));
  assert.equal(owned.port,14627);process.kill(owned.pid,0);
  const a = await tenant('returns');
  let s = await snapshot(a,'initial');
  assert.equal(money(s.sale.creditBalance),1500);assert.equal(money(s.cash.expectedCash),1000);
  assert.equal(money(s.report.kpis.totalSold),2500);assert.equal(money(s.report.kpis.totalProfit),1500);
  const saleItemId = s.sale.items[0].id;
  const refund = qty => a.api(`/sales/${a.saleId}/return`,{clientRequestId:crypto.randomUUID(),originalSaleCashSessionId:a.sessionId,operationCashSessionId:a.sessionId,operationOccurredAt:new Date().toISOString(),restoreInventory:true,reason:'Prueba contable sintética',items:[{saleItemId,qty}]});
  await refund(2);
  s = await snapshot(a,'partial-unpaid-return');
  assert.equal(money(s.sale.creditPaidAmount),1000);assert.equal(money(s.sale.creditBalance),1000);assert.equal(money(s.cash.expectedCash),1000);
  assert.equal(money(s.report.kpis.totalSold),2000);assert.equal(money(s.report.kpis.netProfit),1200);assert.equal(money(s.report.kpis.netCost),800);assert.equal(money(s.report.kpis.grossProfit),1200);assert.equal(money(s.customer.metrics.creditBalanceTotal),1000);assert.equal(money(s.stock),92);
  checks.push('partial return reduces receivable by 500, refunds no cash, retains 1000 paid and 1000 owed');
  const payment = {operationId:crypto.randomUUID(),operationCashSessionId:a.sessionId,paidAt:new Date().toISOString(),cashAmount:0,transferAmount:500};
  await a.api(`/sales/${a.saleId}/credit-payments`,payment);await a.api(`/sales/${a.saleId}/credit-payments`,payment);
  s = await snapshot(a,'payment-and-replay');
  assert.equal(money(s.sale.creditBalance),500);assert.equal(money(s.sale.creditPaidAmount),1500);assert.equal(s.sale.creditPayments.length,1);
  assert.equal(money(s.report.kpis.totalSold),2000);assert.equal(money(s.report.kpis.netProfit),1200);assert.equal(money(s.stock),92);
  checks.push('500 transfer and replay change only collection and receivable, not revenue, profit or inventory');
  await refund(4);
  s = await snapshot(a,'return-beyond-debt');
  assert.equal(money(s.sale.creditBalance),0);assert.equal(money(s.sale.creditPaidAmount),1000);assert.equal(s.sale.creditStatus,'paid');
  assert.equal(money(s.cash.expectedCash),666.67);assert.equal(money(s.report.kpis.totalSold),1000);assert.equal(money(s.report.kpis.netProfit),600);assert.equal(money(s.stock),96);
  checks.push('return exceeding debt refunds exactly 500 through the paid channels and retains the paid credit in history');
  await refund(4);
  s = await snapshot(a,'full-return');
  assert.equal(money(s.sale.creditBalance),0);assert.equal(money(s.sale.creditPaidAmount),0);assert.equal(money(s.cash.expectedCash),0);assert.equal(money(s.stock),100);
  assert.equal(money(s.report.kpis.totalSold),0);assert.equal(money(s.report.kpis.netProfit),0);
  checks.push('successive full return conserves all invoice and payment records, refunds the exact paid total and restores inventory once');
  const b = await tenant('historical');
  const past = new Date();past.setUTCDate(past.getUTCDate()-3);past.setUTCHours(16,0,0,0);
  const closed = await db.cashSession.create({data:{companyId:b.companyId,openedByUserId:b.user.id,initialAmount:0,status:'CLOSED',openedAt:new Date(past.getTime()-3600000),closedAt:new Date(past.getTime()+3600000),businessDate:date(past)}});
  // Historical fixture only: current payment still passes all real session rules.
  await db.sale.updateMany({where:{id:b.saleId,companyId:b.companyId},data:{saleDate:past,cashSessionId:closed.id}});
  const beforeOld = await b.api(`/reports/sales-overview?from=${date(past)}&to=${date(past)}`);
  const later = {operationId:crypto.randomUUID(),operationCashSessionId:b.sessionId,paidAt:new Date().toISOString(),cashAmount:500,transferAmount:0};
  await b.api(`/sales/${b.saleId}/credit-payments`,later);await b.api(`/sales/${b.saleId}/credit-payments`,later);
  const afterOld = await b.api(`/reports/sales-overview?from=${date(past)}&to=${date(past)}`);
  s = await snapshot(b,'historical-invoice-current-collection');
  assert.equal(money(beforeOld.kpis.totalSold),2500);assert.equal(money(afterOld.kpis.totalSold),2500);assert.equal(money(afterOld.kpis.totalProfit),1500);
  assert.equal(money(s.report.kpis.totalSold),0);assert.equal(money(s.report.kpis.totalProfit),0);assert.equal(money(s.report.kpis.creditPaymentsCash),500);
  assert.equal(money(s.cash.expectedCash),500);assert.equal(money(s.cash.salesCashTotal),0);assert.equal(money(s.cash.creditPaymentsCashTotal),500);
  assert.equal(money(s.sale.creditBalance),1000);assert.equal(money(s.customer.metrics.creditBalanceTotal),1000);assert.equal(s.sale.creditPayments.length,1);
  snapshots.push({label:'historical-period-stable',beforeOld,afterOld});
  checks.push('old invoice collection belongs to the current cash session and paidAt period; historical revenue and profit never repeat');
  fs.writeFileSync(dir+'/accounting-evidence.json',JSON.stringify({result:'PASS',checks,snapshots},null,2));
  console.log(JSON.stringify({result:'PASS',checks}));
}
main().catch(error=>{fs.writeFileSync(dir+'/accounting-failure.json',JSON.stringify({error:error.message,snapshots},null,2));console.error(error.message);process.exitCode=1;}).finally(()=>db.$disconnect());
