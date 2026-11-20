import { PrismaClient, Role } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ConfigService } from '@nestjs/config';
import { LicenseActivationService } from './license-activation.service';
import { LicenseEvidenceStorage } from './license-evidence.storage';
import { LicenseOrdersService } from './license-orders.service';
import { LicenseProvisionalService } from './license-provisional.service';

/**
 * Flujo completo de pago contra un PostgreSQL desechable:
 * orden -> comprobante -> activacion inmediata -> pago por verificar.
 *
 * Solo corre si `LICENSE_PAYMENTS_FIXTURE_URL` apunta a 127.0.0.1 con una base
 * de pruebas conocida. Nunca deduce el destino del `.env` de la aplicacion.
 */
const fixtureUrl = process.env.LICENSE_PAYMENTS_FIXTURE_URL;
const suite = fixtureUrl ? describe : describe.skip;

const PDF_A = Buffer.from('%PDF-1.7\ncomprobante de prueba A\n%%EOF');
const PDF_B = Buffer.from('%PDF-1.7\ncomprobante de prueba B\n%%EOF');
const PDF_DUP = Buffer.from('%PDF-1.7\ncomprobante de prueba A\n%%EOF');

suite('Pago de planes con PostgreSQL aislado', () => {
  let db: PrismaClient;
  let orders: LicenseOrdersService;
  let storageDir: string;
  let companyId: string;
  const user = {
    id: randomUUID(),
    email: 'dueno@example.invalid',
    role: Role.ADMIN,
    companyId: '',
  } as never as { id: string; email: string; role: Role; companyId: string };

  beforeAll(async () => {
    const url = new URL(fixtureUrl!);
    if (
      url.hostname !== '127.0.0.1' ||
      url.port !== '56701' ||
      url.pathname !== '/appyra_license_e2e' ||
      (url.search && url.search !== '?schema=public') ||
      url.hash
    ) {
      throw new Error('unsafe_fixture_target');
    }
    db = new PrismaClient({ datasources: { db: { url: fixtureUrl } } });
    await db.$connect();
    storageDir = await mkdtemp(join(tmpdir(), 'license-evidence-'));
    const config = {
      get: (key: string) => {
        if (key === 'LICENSE_EVIDENCE_DIR') return storageDir;
        // En esta prueba no hay motor OCR: el interruptor de pruebas permite
        // seguir ejercitando la activacion y sus validaciones documentales.
        if (key === 'LICENSE_EVIDENCE_TEST_ACTIVATE') return 'true';
        return undefined;
      },
    } as unknown as ConfigService;
    const storage = new LicenseEvidenceStorage(config);
    const activation = new LicenseActivationService(db as never);
    const ocr = {
      extractText: async () => ({
        ok: false as const,
        error: 'ocr-not-configured',
        engine: 'test',
      }),
    };
    orders = new LicenseOrdersService(
      db as never,
      config,
      activation,
      storage,
      new LicenseProvisionalService(),
      ocr as never,
    );
  });

  afterAll(async () => {
    await db?.$disconnect();
    if (storageDir) await rm(storageDir, { recursive: true, force: true });
  });

  beforeEach(async () => {
    await db.licenseNotificationJob.deleteMany();
    await db.licensePaymentEvidence.deleteMany();
    await db.licensePaymentOrder.deleteMany();
    await db.companyLicenseAuditLog.deleteMany();
    await db.company.deleteMany();
    await db.licensePlan.upsert({
      where: { code: 'pro' },
      create: {
        code: 'pro',
        name: 'FullPOS Pro',
        version: 1,
        monthlyPrice: '3500.00',
        currency: 'DOP',
        maxUsers: 4,
        maxProducts: 1000,
        maxWarehouses: 5,
        multiWarehouse: true,
        wholesale: true,
        uom: true,
        ecf: true,
        taxes: true,
        ecfMonthlyQuota: 1500,
        active: true,
      },
      update: { active: true, monthlyPrice: '3500.00', version: 1 },
    });
    const company = await db.company.create({
      data: {
        name: 'Empresa de prueba',
        slug: `pago-${randomUUID().slice(0, 8)}`,
        licenseStatus: 'TRIAL',
        trialStartedAt: new Date(Date.now() - 6 * 86_400_000),
        trialEndsAt: new Date(Date.now() + 86_400_000),
        ncfEnabled: true,
        taxEnabled: true,
      },
    });
    companyId = company.id;
    (user as { companyId: string }).companyId = companyId;
  });

  it('crea una orden con referencia unica, importe del catalogo y vida de renovacion', async () => {
    const order = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    expect(order.reference).toMatch(/^FP-\d{4}-\d{6}$/);
    expect(order.amount).toBe(3500);
    expect(order.status).toBe('AWAITING_TRANSFER');
    const ttl = new Date(order.expiresAt).getTime() - Date.now();
    // Renovacion del mismo plan: la orden sobrevive a la ventana de pago
    // anticipado (15 dias) para que la referencia no cambie.
    expect(ttl).toBeGreaterThan(14 * 86_400_000);
    expect(ttl).toBeLessThanOrEqual(15 * 86_400_000);

    const again = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    expect(again.id).toBe(order.id);
  });

  it('al subir el comprobante activa al instante y deja el pago por verificar', async () => {
    const order = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const result = await orders.uploadEvidence(user, order.id, {
      originalname: 'transferencia.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });

    expect(result.ok).toBe(true);
    expect(result.paymentStatus).toBe('UNCONFIRMED');
    expect(result.order.status).toBe('UNCONFIRMED');

    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    expect(company.licenseStatus).toBe('ACTIVE');
    expect(company.planCode).toBe('pro');
    expect(company.maxUsers).toBe(4);
    expect(company.maxProducts).toBe(1000);
    expect(company.maxWarehouses).toBe(5);
    expect(company.licenseExpiresAt!.getTime()).toBeGreaterThan(Date.now());
    // Las funciones incluidas conservan lo que estaba encendido...
    expect(company.ncfEnabled).toBe(true);

    const evidence = await db.licensePaymentEvidence.findFirstOrThrow({
      where: { companyId },
    });
    expect(evidence.mime).toBe('application/pdf');
    expect(evidence.sha256).toHaveLength(64);

    const job = await db.licenseNotificationJob.findFirstOrThrow({
      where: { companyId },
    });
    expect(job.kind).toBe('ADMIN_EVIDENCE');
    expect((job.payload as Record<string, unknown>).reference).toBe(
      order.reference,
    );

    const audit = await db.companyLicenseAuditLog.findFirstOrThrow({
      where: { companyId, action: 'license.payment_evidence_received' },
    });
    expect(audit.reason).toContain(order.reference);
  });

  it('rechaza el mismo comprobante dos veces sin activar de nuevo', async () => {
    const order = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    await orders.uploadEvidence(user, order.id, {
      originalname: 'uno.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    const second = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    await expect(
      orders.uploadEvidence(user, second.id, {
        originalname: 'repetido.pdf',
        mimetype: 'application/pdf',
        size: PDF_DUP.length,
        buffer: PDF_DUP,
      }),
    ).rejects.toThrow('ya fue enviado');
    expect(await db.licensePaymentEvidence.count({ where: { companyId } })).toBe(1);
  });

  it('renueva sumando al vencimiento existente', async () => {
    const first = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const one = await orders.uploadEvidence(user, first.id, {
      originalname: 'uno.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    const second = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const two = await orders.uploadEvidence(user, second.id, {
      originalname: 'dos.pdf',
      mimetype: 'application/pdf',
      size: PDF_B.length,
      buffer: PDF_B,
    });
    expect(new Date(two.license.periodStart).getTime()).toBe(
      new Date(one.license.periodEnd).getTime(),
    );
    expect(
      new Date(two.license.periodEnd).getTime() -
        new Date(one.license.periodEnd).getTime(),
    ).toBeGreaterThan(27 * 86_400_000);
  });

  it('apaga lo que el plan no incluye al activar un plan inferior', async () => {
    await db.licensePlan.upsert({
      where: { code: 'basico' },
      create: {
        code: 'basico',
        name: 'FullPOS Básico',
        version: 1,
        monthlyPrice: '1000.00',
        maxUsers: 2,
        maxProducts: 100,
        maxWarehouses: 1,
        multiWarehouse: false,
        wholesale: false,
        uom: true,
        ecf: false,
        taxes: false,
        active: true,
      },
      update: { active: true },
    });
    const order = await orders.createOrder(user, { planCode: 'basico' });
    await orders.uploadEvidence(user, order.id, {
      originalname: 'basico.pdf',
      mimetype: 'application/pdf',
      size: PDF_B.length,
      buffer: PDF_B,
    });
    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    expect(company.planCode).toBe('basico');
    expect(company.maxWarehouses).toBe(1);
    expect(company.ncfEnabled).toBe(false);
    expect(company.taxEnabled).toBe(false);
  });

  /**
   * A1: dos subidas simultaneas. La orden se bloquea dentro de la transaccion y
   * se revalida, asi que ni se duplican meses ni se pisa el periodo pagado.
   */
  it('dos subidas simultaneas a la misma orden activan una sola vez', async () => {
    const order = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const before = Date.now();
    const [a, b] = await Promise.allSettled([
      orders.uploadEvidence(user, order.id, {
        originalname: 'a.pdf',
        mimetype: 'application/pdf',
        size: PDF_A.length,
        buffer: PDF_A,
      }),
      orders.uploadEvidence(user, order.id, {
        originalname: 'b.pdf',
        mimetype: 'application/pdf',
        size: PDF_B.length,
        buffer: PDF_B,
      }),
    ]);

    const ok = [a, b].filter((r) => r.status === 'fulfilled');
    const rejected = [a, b].filter((r) => r.status === 'rejected');
    expect(ok).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect(String((rejected[0] as PromiseRejectedResult).reason)).toMatch(
      /ya tiene un comprobante|ya no admite|ya fue activada/i,
    );

    // Un solo comprobante guardado y **un solo** periodo aplicado.
    expect(
      await db.licensePaymentEvidence.count({ where: { companyId } }),
    ).toBe(1);
    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    const days =
      (company.licenseExpiresAt!.getTime() - before) / 86_400_000;
    expect(days).toBeGreaterThan(27);
    expect(days).toBeLessThan(32);

    const order2 = await db.licensePaymentOrder.findUniqueOrThrow({
      where: { id: order.id },
    });
    expect(order2.status).toBe('UNCONFIRMED');
  });

  it('el mismo archivo en dos ordenes a la vez responde 409, no 500', async () => {
    const pro = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    // Segunda orden abierta creada a mano: el servicio reutiliza la orden
    // abierta de la empresa, y aqui hacen falta dos a la vez para provocar la
    // carrera del indice unico (empresa + huella).
    const second = await db.licensePaymentOrder.create({
      data: {
        companyId,
        planCode: 'pro',
        catalogVersion: 1,
        months: 1,
        amount: '3500.00',
        currency: 'DOP',
        reference: `FP-2026-${randomUUID().slice(0, 6)}`,
        status: 'CREATED',
        expiresAt: new Date(Date.now() + 86_400_000),
      },
    });
    const [a, b] = await Promise.allSettled([
      orders.uploadEvidence(user, pro.id, {
        originalname: 'mismo.pdf',
        mimetype: 'application/pdf',
        size: PDF_A.length,
        buffer: PDF_A,
      }),
      orders.uploadEvidence(user, second.id, {
        originalname: 'mismo.pdf',
        mimetype: 'application/pdf',
        size: PDF_A.length,
        buffer: PDF_A,
      }),
    ]);
    const rejected = [a, b].filter((r) => r.status === 'rejected');
    expect(rejected).toHaveLength(1);
    expect(String((rejected[0] as PromiseRejectedResult).reason)).toMatch(
      /ya fue enviado|ya no admite/i,
    );
    expect(
      await db.licensePaymentEvidence.count({ where: { companyId } }),
    ).toBe(1);
  });

  it('una orden ya cerrada no admite otro comprobante', async () => {
    const order = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    await orders.uploadEvidence(user, order.id, {
      originalname: 'uno.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    await expect(
      orders.uploadEvidence(user, order.id, {
        originalname: 'dos.pdf',
        mimetype: 'application/pdf',
        size: PDF_B.length,
        buffer: PDF_B,
      }),
    ).rejects.toThrow(/ya tiene un comprobante|ya no admite/i);
    expect(
      await db.licensePaymentEvidence.count({ where: { companyId } }),
    ).toBe(1);
  });

  /**
   * A4: la referencia se comprueba en **todas** las empresas. Dos negocios con
   * la misma cuenta de cobro no pueden reutilizar el mismo comprobante.
   */
  it('una referencia usada por otra empresa no vuelve a activar (A4)', async () => {
    const localDay = new Date(Date.now() - 4 * 3_600_000);
    const d = String(localDay.getUTCDate()).padStart(2, '0');
    const m = String(localDay.getUTCMonth() + 1).padStart(2, '0');
    const hh = String(localDay.getUTCHours()).padStart(2, '0');
    const mm = String(localDay.getUTCMinutes()).padStart(2, '0');
    const reference = `A4-${randomUUID().slice(0, 8)}`;
    const receipt = [
      'Banco Popular Dominicano',
      'Transferencia realizada',
      'Estado: aprobada',
      'Monto: RD$3,500.00',
      'Cuenta destino: 841360753',
      `Referencia: ${reference}`,
      `Fecha: ${d}/${m}/${localDay.getUTCFullYear()} ${hh}:${mm}`,
    ].join('\n');
    const config = {
      get: (key: string) => {
        if (key === 'LICENSE_EVIDENCE_DIR') return storageDir;
        if (key === 'LICENSE_EVIDENCE_TEST_ACTIVATE') return 'true';
        return undefined;
      },
    } as unknown as ConfigService;
    const withOcr = new LicenseOrdersService(
      db as never,
      config,
      new LicenseActivationService(db as never),
      new LicenseEvidenceStorage(config),
      new LicenseProvisionalService(),
      {
        extractText: async () => ({ ok: true as const, text: receipt, engine: 'test-ocr' }),
      } as never,
    );

    // Empresa A paga con esa referencia.
    const first = await withOcr.createOrder(user, { planCode: 'pro', months: 1 });
    const paid = await withOcr.uploadEvidence(user, first.id, {
      originalname: 'a.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    expect(paid.activated).toBe(true);

    // Empresa B (mismo servidor, otro negocio) intenta el mismo comprobante.
    const other = await db.company.create({
      data: {
        name: 'Empresa B',
        slug: `pago-b-${randomUUID().slice(0, 8)}`,
        licenseStatus: 'TRIAL',
        trialStartedAt: new Date(Date.now() - 6 * 86_400_000),
        trialEndsAt: new Date(Date.now() + 86_400_000),
      },
    });
    const userB = {
      id: randomUUID(),
      email: 'dueno-b@example.invalid',
      role: Role.ADMIN,
      companyId: other.id,
    } as never as { id: string; email: string; role: Role; companyId: string };
    const second = await withOcr.createOrder(userB, { planCode: 'pro', months: 1 });
    const reused = await withOcr.uploadEvidence(userB, second.id, {
      originalname: 'b.pdf',
      mimetype: 'application/pdf',
      size: PDF_B.length,
      buffer: PDF_B,
    });
    expect(reused.activated).toBe(false);
    expect(reused.paymentStatus).toBe('PENDING_REVIEW');
    const after = await db.company.findUniqueOrThrow({ where: { id: other.id } });
    expect(after.licenseStatus).toBe('TRIAL');
    expect(after.licenseExpiresAt).toBeNull();
  });

  /** Servicio con un comprobante ya «leido», para probar el camino completo. */
  function serviceWithReceipt(
    text: string,
    extraConfig: Record<string, string> = {},
  ) {
    const config = {
      get: (key: string) => {
        if (key === 'LICENSE_EVIDENCE_DIR') return storageDir;
        if (key === 'LICENSE_EVIDENCE_TEST_ACTIVATE') return 'true';
        if (key in extraConfig) return extraConfig[key];
        return undefined;
      },
    } as unknown as ConfigService;
    return new LicenseOrdersService(
      db as never,
      config,
      new LicenseActivationService(db as never),
      new LicenseEvidenceStorage(config),
      new LicenseProvisionalService(),
      {
        extractText: async () => ({ ok: true as const, text, engine: 'test-ocr' }),
      } as never,
    );
  }

  /** Codigos de las comprobaciones fallidas (documentales y del banco). */
  function failedChecks(validation: unknown) {
    const record = validation as {
      checks?: Array<{ code: string; ok: boolean }>;
      bank?: { checks?: Array<{ code: string; ok: boolean }> } | null;
    };
    return [...(record.checks ?? []), ...(record.bank?.checks ?? [])]
      .filter((check) => !check.ok)
      .map((check) => check.code);
  }

  function receiptText(dayOffset: number, reference: string) {
    const local = new Date(Date.now() - 4 * 3_600_000 + dayOffset * 86_400_000);
    const d = String(local.getUTCDate()).padStart(2, '0');
    const m = String(local.getUTCMonth() + 1).padStart(2, '0');
    const hh = String(local.getUTCHours()).padStart(2, '0');
    const mm = String(local.getUTCMinutes()).padStart(2, '0');
    return [
      'Banco Popular Dominicano',
      'Transferencia realizada',
      'Estado: aprobada',
      'Monto: RD$3,500.00',
      'Cuenta destino: 841360753',
      `Referencia: ${reference}`,
      `Fecha: ${d}/${m}/${local.getUTCFullYear()} ${hh}:${mm}`,
    ].join('\n');
  }

  it('un comprobante con fecha futura no activa (A2)', async () => {
    const service = serviceWithReceipt(receiptText(1, `A2-${randomUUID().slice(0, 8)}`));
    const order = await service.createOrder(user, { planCode: 'pro', months: 1 });
    const result = await service.uploadEvidence(user, order.id, {
      originalname: 'futuro.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    expect(result.activated).toBe(false);
    expect(result.paymentStatus).toBe('PENDING_REVIEW');
    const failed = failedChecks(result.validation);
    expect(failed).toContain('RECEIPT_NOT_FUTURE');
    const company = await db.company.findUniqueOrThrow({ where: { id: companyId } });
    expect(company.licenseStatus).toBe('TRIAL');
    expect(company.licenseExpiresAt).toBeNull();
  });

  it('una cuenta de cobro mal configurada no activa (A3)', async () => {
    const service = serviceWithReceipt(receiptText(0, `A3-${randomUUID().slice(0, 8)}`), {
      LICENSE_BANK_ACCOUNT: '12',
    });
    const order = await service.createOrder(user, { planCode: 'pro', months: 1 });
    const result = await service.uploadEvidence(user, order.id, {
      originalname: 'cuenta.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    expect(result.activated).toBe(false);
    const failed = failedChecks(result.validation);
    expect(failed).toContain('BANK_ACCOUNT_CONFIGURED');
    const company = await db.company.findUniqueOrThrow({ where: { id: companyId } });
    expect(company.licenseStatus).toBe('TRIAL');
  });

  it('rechazar el pago devuelve la licencia al estado anterior (reversion)', async () => {
    const provisional = new LicenseProvisionalService();
    const order = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const paid = await orders.uploadEvidence(user, order.id, {
      originalname: 'pago.pdf',
      mimetype: 'application/pdf',
      size: PDF_A.length,
      buffer: PDF_A,
    });
    expect(paid.activated).toBe(true);
    const activated = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    expect(activated.licenseStatus).toBe('ACTIVE');
    expect(activated.licenseExpiresAt).not.toBeNull();

    // Soporte comprueba que el dinero no llego: se revierte la provisional.
    await db.$transaction(async (tx) => {
      await provisional.revert(tx as never, { orderId: order.id });
    });

    const reverted = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    // Politica: un pago no acreditado deja la licencia **vencida**, no le
    // devuelve una demo ni mantiene el periodo que se habia concedido.
    expect(reverted.licenseStatus).toBe('EXPIRED');
    expect(reverted.licenseExpiresAt).toBeNull();
    const revertedOrder = await db.licensePaymentOrder.findUniqueOrThrow({
      where: { id: order.id },
    });
    expect(revertedOrder.activationState).toBe('REVERTED');
  });

  // ---------------------------------------------------------------------------
  // Blindaje: carreras agresivas. Todas deben terminar con **una** evidencia y
  // **un** periodo, aunque lleguen muchas peticiones a la vez.
  // ---------------------------------------------------------------------------

  async function openOrder(planCode = 'pro', months = 1) {
    return db.licensePaymentOrder.create({
      data: {
        companyId,
        planCode,
        catalogVersion: 1,
        months,
        amount: '3500.00',
        currency: 'DOP',
        reference: `FP-2026-${randomUUID().slice(0, 6)}`,
        status: 'CREATED',
        expiresAt: new Date(Date.now() + 86_400_000),
      },
    });
  }

  function pdf(tag: string) {
    return Buffer.from(`%PDF-1.7\ncomprobante ${tag}\n%%EOF`);
  }

  it('cinco subidas simultaneas del mismo archivo: una sola evidencia y un solo periodo', async () => {
    const target = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const extra = [
      await openOrder(),
      await openOrder(),
      await openOrder(),
      await openOrder(),
    ];
    const ids = [target.id, ...extra.map((row) => row.id)];
    const before = Date.now();
    const results = await Promise.allSettled(
      ids.map((id, index) =>
        orders.uploadEvidence(user, id, {
          originalname: `igual-${index}.pdf`,
          mimetype: 'application/pdf',
          size: PDF_A.length,
          buffer: PDF_A,
        }),
      ),
    );
    const ok = results.filter((r) => r.status === 'fulfilled');
    expect(ok).toHaveLength(1);
    expect(
      await db.licensePaymentEvidence.count({ where: { companyId } }),
    ).toBe(1);
    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    const days = (company.licenseExpiresAt!.getTime() - before) / 86_400_000;
    expect(days).toBeGreaterThan(27);
    expect(days).toBeLessThan(32);
  });

  it('cinco subidas simultaneas de archivos distintos a la misma orden: una sola activacion', async () => {
    const target = await orders.createOrder(user, { planCode: 'pro', months: 1 });
    const before = Date.now();
    const results = await Promise.allSettled(
      [0, 1, 2, 3, 4].map((index) =>
        orders.uploadEvidence(user, target.id, {
          originalname: `distinto-${index}.pdf`,
          mimetype: 'application/pdf',
          size: pdf(String(index)).length,
          buffer: pdf(String(index)),
        }),
      ),
    );
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(
      await db.licensePaymentEvidence.count({ where: { companyId } }),
    ).toBe(1);
    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    const days = (company.licenseExpiresAt!.getTime() - before) / 86_400_000;
    expect(days).toBeGreaterThan(27);
    expect(days).toBeLessThan(32);
  });

  it('la misma referencia en dos comprobantes distintos de la misma empresa no activa dos veces', async () => {
    const reference = `DOBLE-${randomUUID().slice(0, 8)}`;
    const first = serviceWithReceipt(receiptText(0, reference));
    const one = await first.createOrder(user, { planCode: 'pro', months: 1 });
    const paid = await first.uploadEvidence(user, one.id, {
      originalname: 'uno.pdf',
      mimetype: 'application/pdf',
      size: pdf('r1').length,
      buffer: pdf('r1'),
    });
    expect(paid.activated).toBe(true);

    // Mismo texto de referencia, archivo distinto (otra «copia» del boucher).
    const again = serviceWithReceipt(receiptText(0, reference));
    const two = await again.createOrder(user, { planCode: 'pro', months: 1 });
    const second = await again.uploadEvidence(user, two.id, {
      originalname: 'dos.pdf',
      mimetype: 'application/pdf',
      size: pdf('r2').length,
      buffer: pdf('r2'),
    });
    expect(second.activated).toBe(false);
    expect(failedChecks(second.validation)).toContain('REFERENCE_NOT_REUSED');
    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    const days = (company.licenseExpiresAt!.getTime() - Date.now()) / 86_400_000;
    expect(days).toBeLessThan(32);
  });

  it('tras un comprobante rechazado, uno valido activa una sola vez', async () => {
    const futuro = serviceWithReceipt(receiptText(1, `R-${randomUUID().slice(0, 8)}`));
    const first = await futuro.createOrder(user, { planCode: 'pro', months: 1 });
    const rejected = await futuro.uploadEvidence(user, first.id, {
      originalname: 'futuro.pdf',
      mimetype: 'application/pdf',
      size: pdf('f').length,
      buffer: pdf('f'),
    });
    expect(rejected.activated).toBe(false);

    const bueno = serviceWithReceipt(receiptText(0, `R-${randomUUID().slice(0, 8)}`));
    const second = await bueno.createOrder(user, { planCode: 'pro', months: 1 });
    const ok = await bueno.uploadEvidence(user, second.id, {
      originalname: 'bueno.pdf',
      mimetype: 'application/pdf',
      size: pdf('b').length,
      buffer: pdf('b'),
    });
    expect(ok.activated).toBe(true);
    const company = await db.company.findUniqueOrThrow({
      where: { id: companyId },
    });
    const days = (company.licenseExpiresAt!.getTime() - Date.now()) / 86_400_000;
    expect(days).toBeGreaterThan(27);
    expect(days).toBeLessThan(32);
  });
});
