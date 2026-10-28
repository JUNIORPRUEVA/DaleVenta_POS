import { GuardianDiagnosisVerdict } from '@prisma/client';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';

/**
 * Salvaguardas del diagnóstico IA evaluadas sobre 10 incidentes sintéticos con
 * causa conocida.
 *
 * IMPORTANTE: esto valida las REGLAS DETERMINISTAS del servicio (que ninguna
 * causa se afirme sin evidencia y que los veredictos se clasifiquen bien), no el
 * comportamiento de un modelo real. Sin credenciales autorizadas el proveedor
 * real no se ejecuta; esa parte queda pendiente y así se reporta.
 */
function service(): GuardianDiagnosisService {
  return new GuardianDiagnosisService({} as never, {} as never, {} as never);
}

type Case = {
  nombre: string;
  causaConocida: string;
  salidaModelo: Parameters<GuardianDiagnosisService['enforceVerdictRules']>[0];
  esperado: {
    verdict: GuardianDiagnosisVerdict;
    maxConfidence?: number;
    causeCategory?: string | null;
  };
};

const CASES: Case[] = [
  {
    nombre: '1. causa confirmada con evidencia de stack',
    causaConocida: 'NullPointerException en sales.create por total nulo',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.CONFIRMED,
      confidence: 0.92,
      summary: 'El cálculo de total devuelve nulo cuando el carrito está vacío.',
      impact: 'Ventas bloqueadas para el turno.',
      causeCategory: 'bug',
      explanation: 'El stack apunta a la línea que desreferencia el total.',
      nextSteps: ['Validar total antes de persistir'],
      evidenceRefs: [{ type: 'stack', ref: 'evidence:1', note: 'marco superior' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.CONFIRMED, causeCategory: 'bug' },
  },
  {
    nombre: '2. causa probable con dos evidencias',
    causaConocida: 'Timeout de cierre de caja por latencia de red',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.PROBABLE,
      confidence: 0.7,
      summary: 'Latencia alta durante el cierre.',
      impact: 'Cierre lento.',
      causeCategory: 'network',
      explanation: 'Dos marcas de tiempo muestran espera superior al límite.',
      nextSteps: ['Revisar latencia del servidor'],
      evidenceRefs: [
        { type: 'stack', ref: 'evidence:2' },
        { type: 'log', ref: 'evidence:3' },
      ],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.PROBABLE, causeCategory: 'network' },
  },
  {
    nombre: '3. causa confirmada con evidencia de consulta',
    causaConocida: 'Stock negativo por transferencia concurrente',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.CONFIRMED,
      confidence: 0.95,
      summary: 'Dos transferencias descontaron el mismo lote.',
      impact: 'Inventario inconsistente.',
      causeCategory: 'concurrency',
      explanation: 'La consulta muestra dos movimientos con el mismo instante.',
      nextSteps: ['Revisar bloqueo de fila'],
      evidenceRefs: [{ type: 'query', ref: 'evidence:5' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.CONFIRMED, causeCategory: 'concurrency' },
  },
  {
    nombre: '4. causa confirmada con evidencia de código',
    causaConocida: 'NCF duplicado por secuencia compartida',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.CONFIRMED,
      confidence: 0.88,
      summary: 'La secuencia se reutiliza entre sucursales.',
      impact: 'Facturas rechazadas por la DGII.',
      causeCategory: 'configuration',
      explanation: 'El código no aísla la secuencia por empresa.',
      nextSteps: ['Aislar la secuencia por inquilino'],
      evidenceRefs: [{ type: 'code', ref: 'evidence:9' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.CONFIRMED, causeCategory: 'configuration' },
  },
  {
    nombre: '5. afirma causa confirmada SIN evidencia -> se degrada',
    causaConocida: 'Desconocida (el modelo inventó una causa)',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.CONFIRMED,
      confidence: 0.99,
      summary: 'Es un problema de memoria del servidor.',
      impact: 'Servicio inestable.',
      causeCategory: 'infrastructure',
      explanation: 'Sin datos que lo respalden.',
      nextSteps: ['Reiniciar'],
      evidenceRefs: [],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.INSUFFICIENT, maxConfidence: 0.2, causeCategory: null },
  },
  {
    nombre: '6. causa probable SIN evidencia -> se degrada',
    causaConocida: 'Desconocida',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.PROBABLE,
      confidence: 0.8,
      summary: 'Posible fallo de disco.',
      impact: 'Lentitud.',
      causeCategory: 'infrastructure',
      explanation: 'Sin datos.',
      nextSteps: ['Revisar disco'],
      evidenceRefs: [],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.INSUFFICIENT, maxConfidence: 0.2, causeCategory: null },
  },
  {
    nombre: '7. evidencia malformada se descarta y se degrada',
    causaConocida: 'Desconocida',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.CONFIRMED,
      confidence: 0.9,
      summary: 'Fallo de licencia.',
      impact: 'Bloqueo.',
      causeCategory: 'license',
      explanation: 'Referencia vacía.',
      nextSteps: ['Revisar licencia'],
      evidenceRefs: [{ type: 'stack', ref: '' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.INSUFFICIENT, maxConfidence: 0.2, causeCategory: null },
  },
  {
    nombre: '8. causa desconocida con evidencia -> conserva INSUFFICIENT y baja confianza',
    causaConocida: 'Desconocida (datos insuficientes reales)',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.INSUFFICIENT,
      confidence: 0.9,
      summary: 'No se puede determinar con los datos actuales.',
      impact: null,
      causeCategory: null,
      explanation: 'Falta evidencia del estado de la base.',
      nextSteps: ['Solicitar más evidencia'],
      evidenceRefs: [{ type: 'log', ref: 'evidence:11' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.INSUFFICIENT, maxConfidence: 0.5 },
  },
  {
    nombre: '9. confianza fuera de rango se acota',
    causaConocida: 'Causa confirmada con evidencia',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.CONFIRMED,
      confidence: 3.5,
      summary: 'Causa verificada.',
      impact: 'Impacto medido.',
      causeCategory: 'bug',
      explanation: 'Evidencia directa.',
      nextSteps: ['Corregir'],
      evidenceRefs: [{ type: 'code', ref: 'evidence:12' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.CONFIRMED, maxConfidence: 1 },
  },
  {
    nombre: '10. causa probable con evidencia parcial no se eleva a confirmada',
    causaConocida: 'Causa probable con evidencia parcial',
    salidaModelo: {
      verdict: GuardianDiagnosisVerdict.PROBABLE,
      confidence: 0.55,
      summary: 'Coincide con un fallo conocido en otro cliente.',
      impact: 'Impacto limitado.',
      causeCategory: 'regression',
      explanation: 'La huella coincide con otro incidente, sin reproducir.',
      nextSteps: ['Comparar huellas'],
      evidenceRefs: [{ type: 'fingerprint', ref: 'evidence:15' }],
    },
    esperado: { verdict: GuardianDiagnosisVerdict.PROBABLE, causeCategory: 'regression' },
  },
];

describe('guardian IA — salvaguardas de veredicto sobre 10 incidentes sintéticos', () => {
  const diagnosed = service();

  for (const testCase of CASES) {
    it(testCase.nombre, () => {
      const result = diagnosed.enforceVerdictRules(testCase.salidaModelo);

      expect(result.verdict).toBe(testCase.esperado.verdict);
      if (testCase.esperado.maxConfidence !== undefined) {
        expect(result.confidence).toBeLessThanOrEqual(testCase.esperado.maxConfidence);
      }
      if (testCase.esperado.causeCategory !== undefined) {
        expect(result.causeCategory).toBe(testCase.esperado.causeCategory);
      }
      expect(result.confidence).toBeGreaterThanOrEqual(0);
      expect(result.confidence).toBeLessThanOrEqual(1);
    });
  }

  it('nunca deja pasar causas afirmadas sin evidencia verificable', () => {
    const sinEvidencia = CASES.filter((c) => c.salidaModelo.evidenceRefs.length === 0);
    expect(sinEvidencia.length).toBeGreaterThanOrEqual(2);
    for (const testCase of sinEvidencia) {
      const result = diagnosed.enforceVerdictRules(testCase.salidaModelo);
      expect(result.verdict).toBe(GuardianDiagnosisVerdict.INSUFFICIENT);
      expect(result.causeCategory).toBeNull();
    }
  });
});
