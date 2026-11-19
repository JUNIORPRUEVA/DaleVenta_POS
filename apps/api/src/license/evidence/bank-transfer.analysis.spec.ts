import {
  describeBankFailure,
  parseBankReceipt,
  toNumber,
  validateBankTransfer,
} from './bank-transfer.analysis';

/**
 * Textos de muestra con la estructura tipica de cada banco.
 *
 * IMPORTANTE: son **transcripciones simuladas** de los formatos, no capturas
 * reales. Sirven para probar el analisis de forma reproducible; la validacion
 * con los comprobantes reales del cliente queda pendiente.
 */
const POPULAR = `Banco Popular Dominicano
Transferencia a terceros
Estado: Realizada
Monto: RD$5,000.00
ITBIS: RD$0.00
Cuenta destino: 841360753
Beneficiario: FULLTECH, SRL
Referencia: 00123456789
Fecha: 17/11/2026 14:35`;

const BHD = `BHD
Transferencia exitosa
Importe RD$ 5,000.00
Impuesto 18%: 0.00
A la cuenta 841-360-75-3
Beneficiario FULLTECH SRL
No. de referencia 987654321
Fecha y hora 17-11-2026 2:35 PM`;

const BANRESERVAS = `Banreservas
Estado: Completada
Monto transferido: DOP 5,000.00
Cuenta destino: 841360753
Beneficiario: FULLTECH SRL
Ref. 5566778899
Fecha: 17/11/2026 02:35 PM`;

const ORDER = {
  amount: 5000,
  createdAt: new Date('2026-11-17T00:00:00.000Z'),
};
const NOW = new Date('2026-11-18T12:00:00.000Z');

function validate(text: string, extra: Record<string, unknown> = {}) {
  return validateBankTransfer({
    parsed: parseBankReceipt(text),
    order: ORDER,
    now: NOW,
    ...extra,
  });
}

describe('parseBankReceipt', () => {
  it('lee Banco Popular', () => {
    const parsed = parseBankReceipt(POPULAR);
    expect(parsed.bank).toBe('popular');
    expect(parsed.amount).toBe(5000);
    expect(parsed.reference).toBe('00123456789');
    expect(parsed.status).toBe('SUCCESS');
    // 14:35 en Republica Dominicana (UTC-4) son las 18:35 UTC.
    expect(parsed.occurredAt).toBe('2026-11-17T18:35:00.000Z');
    expect(parsed.destinationAccount).toBe('841360753');
    expect(parsed.beneficiary).toContain('FULLTECH');
  });

  it('lee BHD con fecha en formato 12 h', () => {
    const parsed = parseBankReceipt(BHD);
    expect(parsed.bank).toBe('bhd');
    expect(parsed.amount).toBe(5000);
    expect(parsed.reference).toBe('987654321');
    // 2:35 PM local (UTC-4) son las 18:35 UTC.
    expect(parsed.occurredAt).toBe('2026-11-17T18:35:00.000Z');
    expect(parsed.destinationAccount).toBe('841-360-75-3');
  });

  it('un pago de las 22:30 sigue siendo del mismo dia local', () => {
    // 18/11 22:30 hora dominicana = 19/11 02:30 UTC. La orden se creo esa misma
    // noche (19/11 02:00 UTC). Leido como UTC, el comprobante caia "antes de la
    // orden" y el cliente que pagaba de noche nunca activaba.
    const parsed = parseBankReceipt(
      POPULAR.replace('17/11/2026 14:35', '18/11/2026 10:30 PM'),
    );
    expect(parsed.occurredAt).toBe('2026-11-19T02:30:00.000Z');
    const result = validateBankTransfer({
      parsed,
      order: { amount: 5000, createdAt: new Date('2026-11-19T02:00:00.000Z') },
      now: new Date('2026-11-19T02:10:00.000Z'),
    });
    expect(result.passed).toBe(true);
  });
  it('lee Banreservas', () => {
    const parsed = parseBankReceipt(BANRESERVAS);
    expect(parsed.bank).toBe('banreservas');
    expect(parsed.amount).toBe(5000);
    expect(parsed.reference).toBe('5566778899');
    expect(parsed.status).toBe('SUCCESS');
  });

  it('no confunde el impuesto con el monto', () => {
    const parsed = parseBankReceipt(
      BANRESERVAS.replace('Monto transferido: DOP 5,000.00', 'Monto transferido: DOP 5,000.00\nITBIS: 900.00'),
    );
    expect(parsed.amount).toBe(5000);
    expect(parsed.tax).toBe(900);
  });

  it('detecta operaciones pendientes y rechazadas', () => {
    expect(parseBankReceipt('Banco Popular\nEstado: Pendiente\nMonto: 5,000.00').status).toBe(
      'PENDING',
    );
    expect(parseBankReceipt('Banco Popular\nOperacion rechazada\nMonto: 5,000.00').status).toBe(
      'FAILED',
    );
  });

  it('interpreta numeros con separadores es-DO y en-US', () => {
    expect(toNumber('5,000.00')).toBe(5000);
    expect(toNumber('5.000,00')).toBe(5000);
    expect(toNumber('5000')).toBe(5000);
    // Sin decimales, el separador de miles no puede leerse como coma decimal.
    expect(toNumber('5,000')).toBe(5000);
    expect(toNumber('5.000')).toBe(5000);
    expect(toNumber('RD$5 000.00')).toBe(5000);
    expect(toNumber('0.500')).toBe(0.5);
  });

  it('no acepta cifras ambiguas (A5)', () => {
    expect(toNumber('1,2,3')).toBeNull();
    expect(toNumber('1.2.3.4')).toBeNull();
    expect(toNumber('5,0000')).toBeNull();
    expect(toNumber('')).toBeNull();
  });

  it('lee la fecha en formato ISO (A5)', () => {
    const parsed = parseBankReceipt(
      POPULAR.replace('17/11/2026 14:35', '2026-11-17 14:35'),
    );
    expect(parsed.occurredAt).toBe('2026-11-17T18:35:00.000Z');
  });

  it('lee el importe con espacio de miles (A5)', () => {
    const parsed = parseBankReceipt(POPULAR.replace('RD$5,000.00', 'RD$5 000.00'));
    expect(parsed.amount).toBe(5000);
  });
});

describe('validateBankTransfer', () => {
  it('un comprobante del Banco Popular correcto pasa todas las comprobaciones', () => {
    const result = validate(POPULAR);
    expect(result.passed).toBe(true);
    expect(describeBankFailure(result)).toBeNull();
  });

  it('BHD y Banreservas tambien pasan con la cuenta 0753', () => {
    expect(validate(BHD).passed).toBe(true);
    expect(validate(BANRESERVAS).passed).toBe(true);
  });

  it('una imagen cualquiera no activa nada', () => {
    const result = validate('Comprobante de pago\nGracias por su compra');
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('BANK_IDENTIFIED');
  });

  it('una operacion pendiente no activa', () => {
    const result = validate('Banco Popular\nEstado: Pendiente\nMonto: RD$5,000.00\nReferencia: 00123456789\nCuenta destino: 841360753\nFecha: 17/11/2026 14:35');
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('OPERATION_SUCCESSFUL');
  });

  it('un monto distinto no activa', () => {
    const result = validate(POPULAR.replace('5,000.00', '3,500.00'));
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('AMOUNT_EXACT');
  });

  it('otra cuenta destino no activa', () => {
    const result = validate(POPULAR.replace('841360753', '841360999'));
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('DESTINATION_ACCOUNT');
  });

  it('una referencia ya usada no activa', () => {
    const result = validate(POPULAR, { referenceAlreadyUsed: true });
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('REFERENCE_NOT_REUSED');
  });

  it('un comprobante viejo no activa', () => {
    const result = validate(
      POPULAR.replace('17/11/2026', '01/01/2026'),
      { now: new Date('2026-11-18T12:00:00.000Z') },
    );
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('RECEIPT_RECENT');
  });

  it('hoy o ayer si valen; anteayer ya es excepcion', () => {
    // El comprobante de "hoy" trae las 14:35 locales (18:35Z): el instante de la
    // subida tiene que ser posterior, como en la vida real.
    const base = { now: new Date('2026-11-18T23:00:00.000Z') };
    // mismo dia
    expect(
      validate(POPULAR.replace('17/11/2026', '18/11/2026'), base).passed,
    ).toBe(true);
    // ayer
    expect(validate(POPULAR, base).passed).toBe(true);
    // anteayer -> revision
    const older = validate(POPULAR.replace('17/11/2026', '16/11/2026'), base);
    expect(older.passed).toBe(false);
    expect(describeBankFailure(older)).toContain('RECEIPT_RECENT');
  });

  it('un comprobante con fecha de manana no activa (A2)', () => {
    const result = validate(POPULAR.replace('17/11/2026', '19/11/2026'));
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('RECEIPT_NOT_FUTURE');
  });

  it('tolera 30 minutos de desfase de reloj, no medio dia', () => {
    const parsed = parseBankReceipt(POPULAR);
    // 18:35Z + 20 min de reloj adelantado -> se acepta.
    const soon = validateBankTransfer({
      parsed,
      order: ORDER,
      now: new Date('2026-11-17T18:55:00.000Z'),
    });
    expect(describeBankFailure(soon) ?? '').not.toContain('RECEIPT_NOT_FUTURE');
    // El mismo comprobante visto 6 h antes: viene del futuro -> no.
    const later = validateBankTransfer({
      parsed,
      order: ORDER,
      now: new Date('2026-11-17T12:00:00.000Z'),
    });
    expect(describeBankFailure(later)).toContain('RECEIPT_NOT_FUTURE');
  });

  it('una cuenta destino mal configurada no se omite: no activa (A3)', () => {
    expect(validate(POPULAR, { authorizedAccountSuffix: '' }).passed).toBe(false);
    expect(
      describeBankFailure(validate(POPULAR, { authorizedAccountSuffix: '' })),
    ).toContain('BANK_ACCOUNT_CONFIGURED');
    expect(validate(POPULAR, { authorizedAccountSuffix: '3' }).passed).toBe(false);
    expect(validate(POPULAR, { authorizedAccountSuffix: '0753' }).passed).toBe(
      true,
    );
  });

  it('un comprobante anterior a la orden no activa', () => {
    const result = validateBankTransfer({
      parsed: parseBankReceipt(POPULAR.replace('17/11/2026', '17/11/2026')),
      order: { amount: 5000, createdAt: new Date('2026-11-18T09:00:00.000Z') },
      now: new Date('2026-11-18T12:00:00.000Z'),
    });
    expect(result.passed).toBe(false);
    expect(describeBankFailure(result)).toContain('DATE_COMPATIBLE_WITH_ORDER');
  });
});
