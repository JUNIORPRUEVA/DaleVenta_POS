import { GuardianDiagnosisVerdict } from '@prisma/client';
import {
  GuardianAiProvider,
  GuardianAiRequest,
  GuardianAiResult,
  GuardianEvidenceRef,
} from './guardian-ai.provider';

/**
 * Proveedor determinista para UAT y pruebas.
 *
 * No inventa causas: solo produce CONFIRMED/PROBABLE cuando hay evidencia
 * concreta en el contexto (incidentes similares o coincidencias de código) y,
 * en caso contrario, devuelve INSUFFICIENT.
 */
export class MockGuardianAiProvider implements GuardianAiProvider {
  readonly name = 'mock';

  isConfigured(): boolean {
    return true;
  }

  async analyze(request: GuardianAiRequest): Promise<GuardianAiResult> {
    const startedAt = Date.now();
    const evidenceRefs: GuardianEvidenceRef[] = [
      { type: 'incident', ref: request.incident.id, note: 'Incidente evaluado' },
    ];
    for (const similar of request.similarIncidents.slice(0, 3)) {
      evidenceRefs.push({
        type: 'similar_incident',
        ref: similar.id,
        note: `Mismo patrón en ${similar.companyId}`,
      });
    }
    for (const match of request.codeMatches.slice(0, 3)) {
      evidenceRefs.push({
        type: 'code',
        ref: `${match.file}:${match.line}`,
        note: match.snippet,
      });
    }
    if (request.company) {
      evidenceRefs.push({ type: 'company', ref: request.company.id, note: 'Empresa verificada' });
    }

    const hasStrongEvidence = request.similarIncidents.length >= 2 && request.codeMatches.length >= 1;
    const hasSomeEvidence = request.similarIncidents.length >= 1 || request.codeMatches.length >= 1;

    let verdict: GuardianDiagnosisVerdict = GuardianDiagnosisVerdict.INSUFFICIENT;
    let confidence = 0.2;
    let causeCategory: string | null = null;
    let summary = 'Información insuficiente para determinar la causa.';

    if (hasStrongEvidence) {
      verdict = GuardianDiagnosisVerdict.CONFIRMED;
      confidence = 0.82;
      causeCategory = 'pattern_recurrence';
      summary = `Patrón recurrente en ${request.incident.module}/${request.incident.operation} con coincidencia en código.`;
    } else if (hasSomeEvidence) {
      verdict = GuardianDiagnosisVerdict.PROBABLE;
      confidence = 0.55;
      causeCategory = 'pattern_recurrence';
      summary = `Posible fallo recurrente en ${request.incident.module}/${request.incident.operation}.`;
    }

    return {
      verdict,
      confidence,
      summary,
      impact: request.incident.impactSummary,
      causeCategory,
      explanation: [
        `Incidente ${request.incident.id} en el módulo ${request.incident.module}.`,
        `Operación afectada: ${request.incident.operation}.`,
        `Tipo de excepción: ${request.incident.exceptionType ?? 'no informado'}.`,
        `Incidentes similares encontrados: ${request.similarIncidents.length}.`,
        `Coincidencias en código autorizado: ${request.codeMatches.length}.`,
      ].join(' '),
      nextSteps:
        verdict === GuardianDiagnosisVerdict.INSUFFICIENT
          ? ['Recolectar evidencia adicional del dispositivo afectado', 'Reproducir en UAT con datos equivalentes']
          : ['Revisar la ruta señalada en el código autorizado', 'Comparar con los incidentes similares listados'],
      evidenceRefs,
      toolCalls: [],
      model: 'mock-guardian-1',
      tokensUsed: 0,
      durationMs: Date.now() - startedAt,
    };
  }
}
