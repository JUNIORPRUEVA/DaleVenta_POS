# Inventario de pruebas omitidas de la auditoría IA

Generado desde resultados reales de Jest, sin ejecutar ni cambiar fixtures.

597 pruebas pendientes; 59 archivos contienen pendientes; 57 suites completamente omitidas. IA: 0 pendientes.

Una omisión intencional en el comando habitual no equivale a una validación aprobada. Las suites PostgreSQL siguen siendo necesarias cuando se publica su área. Las pruebas e2e excluidas por el comando npm test son adicionales y no están incluidas en las 597.

| Área | Archivos | Pruebas | Ejecución |
| --- | ---: | ---: | --- |
| Fiscal / ventas e-CF | 39 | 454 | Suite PostgreSQL fiscal aislada requerida para release del área; sin ejecución en esta tarea de IA. |
| Licencias / pagos / actividad | 5 | 42 | Fixtures PostgreSQL dedicadas requeridas para release del área; sin ejecución ni modificación de licencias en esta tarea. |
| Guardian / diagnóstico | 13 | 89 | PostgreSQL y rol lector dedicados; ejecución pendiente fuera del chat de IA. No confundir Guardian con APPYRA runtime. |
| Outbox de notificaciones | 1 | 4 | PostgreSQL y transporte simulado; ejecución pendiente. Nunca activar envíos externos para contar estas pruebas. |
| Importación legacy | 1 | 8 | Ensayo de importación/rollback con SQLite y PostgreSQL desechables; fuera del alcance actual. |

## Detalle por archivo

| Archivo | Omitidas | Clasificación | Variables de activación/requisitos |
| --- | ---: | --- | --- |
| `src/ecf/integration/multi-company-e2e.integration-spec.ts` | 12 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/license/orders/license-orders.integration-spec.ts` | 19 | Opt-in intencional | LICENSE_PAYMENTS_FIXTURE_URL |
| `src/ecf/provider/dosa/dosa-sale-to-json-postgres.integration-spec.ts` | 6 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/sales/sales-return-ecf-credit-postgres.integration-spec.ts` | 15 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/pos/ecf-sale-fiscal.adapter-postgres.integration-spec.ts` | 22 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/sandbox/e32-reconciliation-executor.integration-spec.ts` | 14 | Opt-in intencional | ECF_POSTGRES_UAT, UAT_LOCAL_ONLY |
| `src/ecf/provider/dosa/dosa-phase-f-postgres.integration-spec.ts` | 22 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/dgii/ecf-dgii-habilitation-postgres.integration-spec.ts` | 17 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-e34-postgres.integration-spec.ts` | 28 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/provider/dosa/dosa-multi-company-postgres.integration-spec.ts` | 15 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-evidence-postgres.integration-spec.ts` | 28 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-e32-trial-postgres.integration-spec.ts` | 27 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-e32-consumo-postgres.integration-spec.ts` | 13 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-e34-emission-postgres.integration-spec.ts` | 13 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-credit-note-postgres.integration-spec.ts` | 10 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-line-classification-postgres.integration-spec.ts` | 8 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/provider/dosa/dosa-incident-postgres.integration-spec.ts` | 8 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.alert.readiness.pg.integration-spec.ts` | 9 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/provider/dosa/dosa-intent-http-postgres.integration-spec.ts` | 10 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-preparation-postgres.integration-spec.ts` | 11 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-sequence-postgres.integration-spec.ts` | 16 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/sales/sales-ecf-atomic-postgres.integration-spec.ts` | 16 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/portal/ecf-portal-enrollment-postgres.integration-spec.ts` | 12 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-document-postgres.integration-spec.ts` | 12 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-legacy-test-classification-postgres.integration-spec.ts` | 6 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/provider/dosa/dosa-credential-postgres.integration-spec.ts` | 7 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.diagnosis.pg.integration-spec.ts` | 8 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/provider/dosa/dosa-closeout-postgres.integration-spec.ts` | 6 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.auto-enrollment.pg.integration-spec.ts` | 6 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/license/crm-license.integration-spec.ts` | 12 | Opt-in intencional | CRM_LICENSE_FIXTURE_URL |
| `src/ecf/documents/ecf-fiscal-document-persistence-postgres.integration-spec.ts` | 7 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/provider/dosa/dosa-same-request-recovery-postgres.integration-spec.ts` | 7 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/provider/dosa/ecf-dosa-session-postgres.integration-spec.ts` | 16 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-simulated-dispatch-postgres.integration-spec.ts` | 9 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/notifications/notifications.claim.pg.integration-spec.ts` | 4 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/documents/ecf-e31-emission-postgres.integration-spec.ts` | 10 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-document-query-postgres.integration-spec.ts` | 10 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/provider/dosa/dosa-dispatch-pending-postgres.integration-spec.ts` | 6 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.ingest.pg.integration-spec.ts` | 6 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `scripts/migration/fullpos-legacy/uat/uat-rehearsal.integration-spec.ts` | 8 | Opt-in intencional | UAT_DATABASE_URL, FULLPOS_LEGACY_DB |
| `src/ecf/provider/dosa/dosa-webhook-postgres.integration-spec.ts` | 8 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.alert.delivery.pg.integration-spec.ts` | 7 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/guardian/guardian.integrity.pg.integration-spec.ts` | 5 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/documents/ecf-sales-without-document-postgres.integration-spec.ts` | 9 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/license/company-activity.integration-spec.ts` | 8 | Opt-in intencional | CRM_LICENSE_FIXTURE_URL |
| `src/ecf/provider/dosa/dosa-postulacion-binding-postgres.integration-spec.ts` | 6 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.alert.recovery.pg.integration-spec.ts` | 7 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/guardian/guardian.company.optin.pg.integration-spec.ts` | 6 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/documents/ecf-simulated-dispatch-concurrency-postgres.integration-spec.ts` | 4 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.retention.pg.integration-spec.ts` | 6 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/documents/ecf-environment-isolation-postgres.integration-spec.ts` | 6 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts` | 1 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.machine.pg.integration-spec.ts` | 5 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/license/crm-license-fiscal-postgres.integration-spec.ts` | 1 | Opt-in intencional | CRM_LICENSE_FIXTURE_URL |
| `src/license/license-integration-postgres.integration-spec.ts` | 2 | Opt-in intencional | LICENSE_PAYMENTS_FIXTURE_URL |
| `src/guardian/guardian.security.pg.integration-spec.ts` | 4 | Opt-in intencional | GUARDIAN_READER_DATABASE_URL, GUARDIAN_UAT_DATABASE_URL |
| `src/ecf/provider/dosa/dosa-graceful-shutdown-postgres.integration-spec.ts` | 1 | Opt-in intencional | ECF_POSTGRES_UAT |
| `src/guardian/guardian.alerts.pg.integration-spec.ts` | 10 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |
| `src/guardian/guardian.platform.pg.integration-spec.ts` | 10 | Opt-in intencional | GUARDIAN_UAT_DATABASE_URL |

El JSON adjunto enumera cada una de las pruebas y su estado observado. Ninguna omisión se convirtió en PASS.
