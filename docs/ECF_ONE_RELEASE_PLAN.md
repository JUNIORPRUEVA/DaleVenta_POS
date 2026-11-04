# e-CF/DOSA: plan para una sola liberación controlada

Este plan prepara la liberación; no autoriza desplegar, migrar, reconciliar el intento existente, emitir e-CF ni presentar nada ante la DGII.

## Condiciones previas del propietario

1. Aprobar el PR y confirmar la imagen exacta de API y PWA que se instalará. Conservar ambas imágenes anteriores para reversión.
2. Verificar la base y el entorno de producción sin mostrar credenciales. Obtener un respaldo PostgreSQL consistente, verificar que puede leerse y registrar su hora y punto de restauración. Mantener el respaldo fuera del contenedor que se reemplazará.
3. Confirmar, con lectura de `_prisma_migrations`, que `20261104120000_ecf_intent_provider_reconciliation` y `20261104120100_ecf_intent_provider_reconciliation_unique` terminaron correctamente. Confirmar el valor `INTENT_PROVIDER_RECONCILED` en `ecf_audit_action` y el índice `ecf_intent_provider_reconciliation_once` en `ecf_audit_logs`. Si falta algo, detener el despliegue y solicitar aprobación separada para aplicar esas migraciones, tras respaldo y ensayo en UAT. No editar migraciones ya aplicadas.
4. Revisar `RUN_MIGRATIONS`, `PRISMA_SYNC_MODE`, `MIGRATION_STRICT` y `RUN_SEED` antes de iniciar la API: el arranque puede ejecutar migraciones por defecto y `MIGRATION_STRICT` tiene valor predeterminado `false`. El despliegue no debe aplicar migraciones implícitas ni continuar después de un fallo migratorio. Mantener semillas desactivadas.
5. Confirmar presencia de la configuración del portal, dominio autorizado, clave pública, piloto y validación de webhooks sin imprimir valores. La reconciliación administrativa debe continuar deshabilitada hasta completar la revisión de evidencias.

Consulta de solo lectura para el propietario en EasyPanel (debe devolver dos migraciones `APPLIED` y dos comprobaciones `true`):

```sql
SELECT 'migration:' || name AS check_name,
       EXISTS (
         SELECT 1 FROM _prisma_migrations
         WHERE migration_name = name
           AND finished_at IS NOT NULL AND rolled_back_at IS NULL
       ) AS ready
FROM (VALUES
  ('20261104120000_ecf_intent_provider_reconciliation'),
  ('20261104120100_ecf_intent_provider_reconciliation_unique')
) AS required(name)
UNION ALL
SELECT 'audit_enum', EXISTS (
  SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname = 'ecf_audit_action'
    AND e.enumlabel = 'INTENT_PROVIDER_RECONCILED'
)
UNION ALL
SELECT 'reconciliation_index', EXISTS (
  SELECT 1 FROM pg_indexes
  WHERE schemaname = current_schema()
    AND tablename = 'ecf_audit_logs'
    AND indexname = 'ecf_intent_provider_reconciliation_once'
);
```

## Orden propuesto, sujeto a autorización separada

1. Cerrar cambios, revisar resultados del CI y comprobar UAT con datos sintéticos: rutas Nginx, restauración de expediente, certificado vencido, aislamiento entre empresas, elegibilidad piloto, portal, webhooks, bloqueo de emisión y POS tradicional.
2. Tomar y verificar el respaldo. Revisar estado migratorio y restricciones. Si faltan las dos migraciones, aprobarlas y ejecutarlas de forma controlada y observada antes de cambiar imágenes; volver a verificar migraciones, enum e índice.
3. Desplegar la API con los indicadores de arranque verificados; comprobar `/health`, `/health/db`, autenticación, diagnóstico y ausencia de emisiones o intentos nuevos.
4. Desplegar la PWA. Verificar `/ecf`, `/ecf/`, `/ecf/certificacion/`, sesión, empresa y que no hay redirección de HTTPS a HTTP. Comprobar también catálogo, POS, NCF y caja sin crear ventas reales.
5. Con el administrador autenticado, leer el diagnóstico de Intento 1. Preservar número, estado, proveedor registrado e historia. No abrir portal ni generar ticket hasta que la atribución efectiva y las autorizaciones estén verificadas.

## Reversión

- Ante un problema de PWA, restaurar la imagen PWA anterior y comprobar rutas, sesión y caché/service worker. Ante un problema de API sin cambio de esquema, restaurar la imagen API anterior y repetir salud, autenticación y aislamiento.
- Si se aplicaron migraciones, no ejecutar SQL inverso improvisado: detener acciones fiscales y decidir una restauración puntual del respaldo probado, considerando todas las escrituras posteriores. La restauración de producción requiere aprobación separada y ventana controlada.
- Mantener reconciliación, emisión y postulación detenidas mientras se investiga. Registrar hora, imagen, migración y evidencia del fallo.

## Aceptación después del despliegue

- Salud de API y PostgreSQL, migraciones y restricciones verificadas; sin errores de inicio.
- PWA HTTPS entrega Flutter en `/ecf`, redirección relativa desde `/ecf/` y portal estático en `/ecf/certificacion/`; resto de rutas intacto.
- Misma empresa y expediente al recargar, cambiar dispositivo y cerrar/abrir sesión; otra empresa no ve ese progreso.
- Certificado con validación persistida y vigente avanza sin nueva carga. Una validación anterior sin metadatos persistidos exige una revalidación explícita, sin inferir vigencia a partir de un marcador visual.
- Intento 1 sigue único y sin cambios hasta una reconciliación administrativa aprobada; historial ALANUBE visible solo en diagnóstico autorizado. Sin creación automática de intención, ticket, sesión ni envío a DGII.
- Elegibilidad piloto, portal y webhook respetan autorización y aislamiento; emisión fiscal sigue bloqueada.
- POS tradicional, NCF, catálogo y caja conservan comportamiento básico.

## Reconciliación posterior, separada de este despliegue

El diagnóstico actual describe Intento 1 como no iniciado, registrado en ALANUBE y sin referencias externas. La ausencia de referencias no demuestra ausencia de actividad externa. Antes de reconciliar, el propietario debe aportar revisión independiente del proveedor y de logs de salida, evidencia de origen local DOSA, referencia de aprobación y motivo. Solo entonces un administrador autorizado podría habilitar temporalmente la acción auditada de PR #8. Verificar el nuevo estado mediante lectura antes de considerar una prueba controlada del portal. Esa prueba requeriría autorización explícita para emitir un ticket; `cert:ready` solo demostraría carga del asistente.
