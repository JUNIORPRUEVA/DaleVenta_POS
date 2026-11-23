# Control administrativo desde APPYRA CRM — candidato local

## Alcance

Rama `agent/crm-control-integral-20261123`, base remota verificada
`production-main` en `7a3a3541`. Conserva `20c880d3` y `2f1432b6`, correcciones
previas del contrato de soporte. No modifica el cliente Flutter ni el módulo
de emisión fiscal. No incorpora pendientes de otros worktrees.

El backend amplía los comandos administrativos existentes: contacto general,
asignación de plan sin cambiar vencimiento, concesión de días y correo de acceso
del propietario. Conserva el control de versión, idempotencia, aislamiento,
auditoría transaccional y revocación de sesiones. Una cuenta propietaria activa
en varias empresas requiere revisión separada para modificar su correo.

## Validación local ya ejecutada

- `npm run api:build`: PASS.
- PostgreSQL aislado: 24 pruebas de administración/conservación fiscal PASS.
- HTTP e2e del contrato administrativo: 6 PASS, ejecución separada del comando
  general porque éste excluye archivos e2e.
- Regresión de licencias: 162 PASS, 53 omisiones condicionales; no se cuentan
  esas omisiones como pruebas ejecutadas.
- Cadena CRM → puente → FullPOS con dos empresas ficticias: contacto, plan,
  extensión, correo y deduplicación verificadas; documentos y contadores fiscales
  conservados. Aceptación nativa del CRM en Windows y Android aprobada.

## Migración obligatoria antes del backend nuevo

`20261123010000_company_contact_email` añade una columna nullable VARCHAR(254).
El correo general no se copia del correo fiscal ni del usuario; los datos
anteriores permanecen sin cambios. SQL probado en esquema PostgreSQL local con
una fila preexistente y rollback; esquema completo probado en bases descartables.

**No desplegar el backend nuevo sin esta columna.** Prisma consulta el campo
nuevo. La migración productiva requiere autorización independiente, respaldo
verificado, comprobación de historial/checksums y ejecución manual revisada.
No cambiar `RUN_MIGRATIONS` ni usar db push en producción. Una reversión de
imagen conserva la columna; no ejecutar DROP ni restaurar toda la base para
revertir esta ampliación.

## Coordinación de publicación

1. Revisión de los commits y PR de FullPOS hacia `production-main` y del CRM
   hacia su rama canónica `master`; conservar sus ancestros anteriores.
2. El puente se mantiene en copia saneada con push deshabilitado. No fusionar
   su historia con la historia original ni hacer force-push. Su distribución
   requiere una imagen privada verificable y autorización separada.
3. Completar el respaldo/migración autorizada antes de activar el backend nuevo.
4. Verificar capacidades y scopes entre backend y puente antes de publicar CRM.
   Clientes o servicios antiguos no presumen capacidades nuevas: fallan cerrados.
5. Verificar canal firmado de soporte y almacenamiento privado en el entorno
   autorizado. No probar con ventas, pagos o comprobantes fiscales reales.

Esta tarea no publica código, no modifica configuración ni datos productivos y
no ejecuta despliegues. GO local; NO-GO de producción hasta esos controles.

Informe completo e inventario en el repositorio CRM:
`docs/integracion-fullpos-20261122/CONTROL_INTEGRAL_RESULTADO_20261123.md`.
