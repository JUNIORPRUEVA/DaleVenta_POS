# DOSA: recuperación de la misma petición durante el despacho

Fecha: 2026-11-13. Checkout `finalesdaleventas`, rama `ultimos-trabajos`.
Validación local; ninguna emisión externa, migración compartida ni activación
productiva. Se conserva el asistente DOSA ya utilizado para certificar FULLTECH.

## Contrato confirmado

**HECHO:** el usuario aportó la respuesta de Alejandro del 2026-11-13 a las 16:53:
el endpoint de envío espera el resultado final y una repetición devuelve el
último estado; un comprobante aceptado o aceptado condicional no se vuelve a
emitir. Una consulta GET separada deja de ser dependencia del recorrido síncrono.
La [documentación oficial de errores y reintentos](https://github.com/alapaix13/DosaInvoicecloud-Documentation#2-manejo-de-errores-y-reintentos)
prescribe conservar JSON y e-NCF ante fallos de comunicación. También describe
HTTP 202; ese estado se mantiene pendiente y no concede aceptación automática.

## Alcance implementado

- Un despacho persistido conserva una sola tentativa lógica `SEND_TO_PROVIDER`.
  Ante timeout, error de red o HTTP 5xx permite hasta tres llamadas HTTP totales,
  con esperas de uno y tres segundos y respetando el cortacircuitos.
- Antes de la primera llamada congela JSON serializado, URL, ruta completa,
  parámetros E34, cabecera y e-NCF. Las repeticiones usan los mismos bytes.
  Las huellas SHA-256 comprueban cuerpo, ruta y petición; no se asigna otro número.
- Antes de cada repetición comprueba la compuerta de la empresa y la huella de
  su credencial. En una transacción vuelve a comprobar módulo, proveedor,
  ambiente, certificación y permiso productivo; bloquea la configuración y el
  documento propios y exige que la tentativa original siga en curso.
- Persiste `DOSA_IDENTICAL_REQUEST_REPLAY` antes del transporte, con ordinal,
  motivo, estado HTTP y huellas, incluido el hash de una respuesta 5xx previa.
  No guarda la clave ni el cuerpo fiscal en ese registro. La evidencia final
  sigue el recibo y registrador existentes; una autorización de repetición no
  equivale a aceptación fiscal.
- Los ordinales dos y tres se serializan por documento. Otra empresa, huellas
  alteradas, cambio/revocación de credencial o autorización y una operación
  terminada no obtienen permiso. Se conserva la exclusión durante las esperas.
- Una aceptación, aceptación condicional, rechazo observado o HTTP 202 detiene
  la recuperación. Si no hay autorización/auditoría, no se repite. Los clientes
  directos y probes sin ese observador conservan una llamada.

La política genérica de un segundo despacho continúa bloqueada. No se agrega
una ruta pública para repetir, un GET de consulta, una dependencia, un modelo
Prisma, una migración o una nueva bandera de producción.

## Evidencia funcional

El servidor HTTP de pruebas en localhost guarda una aceptación sintética y
corta la conexión antes de devolverla. El segundo envío recupera ese resultado
con cuerpo y ruta idénticos. La cadena real de rutas FullPOS recorre venta,
preparación E31, aceptación, reserva E34, aceptación, crédito aplicado y QR.
Se comprueban cuatro llamadas HTTP y sólo dos aceptaciones del doble, una por
documento; los rangos avanzan una sola vez y un segundo despacho público falla.
No son nuevas aceptaciones reales de DGII ni nuevas pruebas externas de FULLTECH.

Los ensayos PostgreSQL comprueban concurrencia, aislamiento de empresa y
ambiente, huellas, credencial revocada/rotada, certificación suspendida/bloqueada,
módulo apagado, proveedor cambiado y autorización productiva propia. El fixture
productivo es ficticio; no habilita el recorrido comercial aún protegido.

## Validaciones ejecutadas

API compilada y probada desde una copia temporal aislada de los mismos fuentes,
contra PostgreSQL Docker propio `fullpos_ecf_finish_20261112` y bases locales
efímeras del ensayo HTTP. No se utiliza el `.env` de producción.

| Comando | Resultado |
| --- | --- |
| `npm run api:build` | PASS final: Prisma generate y TypeScript |
| `npm --workspace apps/api run test:unit -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-emission.spec.ts src/ecf/provider/dosa/dosa-emission-key-selection.spec.ts` | PASS: 67 pruebas |
| `npm --workspace apps/api run test:integration -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-same-request-recovery-postgres.integration-spec.ts` | PASS final: 6 pruebas |
| `npm --workspace apps/api test -- --runInBand` | PASS final: 275 suites, 3282 pruebas; 13 suites y 101 pruebas omitidas por sus compuertas |
| `npm --workspace apps/api run test:e2e -- --runInBand --runTestsByPath src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts src/ecf/provider/dosa/dosa-emission-dispatch.e2e-spec.ts` | PASS final: 32/32 |
| `flutter test test/features/ecf/ecf_repository_test.dart test/features/ecf/ecf_dosa_dispatch_action_test.dart test/modules/ventas/ecf_pos_fiscal_test.dart test/core/printing/ecf_print_representation_test.dart` | PASS: 69 pruebas; no hay cambios Flutter en esta etapa |

Los diez fuentes API de la etapa coinciden byte a byte con la copia probada.
`git diff --check` pasó en los archivos seguidos; la inspección de los dieciséis
archivos de la etapa también pasó sin espacios finales ni conflictos. Los
fuentes del asistente, sesión, webhook y autoridad de certificación conservan
diff vacío respecto de HEAD. El contenedor PostgreSQL propio se detiene al
terminar, sin eliminar la base.

Se observan avisos existentes de `ts-jest.isolatedModules`, SQLite experimental,
handles abiertos de Jest y fuentes PDF Helvetica en fixtures. No se atribuyen
a esta etapa cambios anteriores del checkout ni se afirma una validación nueva
de hardware. No se modificó UI; no se ejecutó Playwright, Figma o Context7 en
esta etapa, que usa patrones y versiones ya instalados.

## Pendientes del objetivo completo

1. Recuperación persistente tras reiniciar el proceso o agotar las tres llamadas.
   Este cambio sólo recupera dentro de la operación original viva; no reanuda
   documentos `UNKNOWN_RESULT` ni libera su numeración.
2. Cierre del resultado 202 y representación de contingencia con su leyenda.
3. Registro automático RFCE E32 sin TrackId, que aún conserva revisión.
4. Cierre validado de activación y preparación comercial productivas por empresa:
   `ecf.service.ts` mantiene bloqueos de fase y `assertCompanyCanPrepare` sigue
   limitado a SANDBOX. El asistente existente no necesita reimplementación.
5. Revisión/autorización de migraciones y clasificación histórica compartidas,
   configuración y despliegue coordinado. Esta etapa no ejecuta esas operaciones.

El contrato de consulta GET ya no figura como petición pendiente para Alejandro.
El módulo completo conserva **NO-GO para producción** por los puntos anteriores.

## Archivos de esta etapa

- `apps/api/src/ecf/provider/dosa/dosa-emission.client.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission.wire.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission.service.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch.service.ts`
- `apps/api/src/ecf/provider/dosa/dosa-same-request-recovery.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission.policy.ts` (comentarios)
- `apps/api/src/ecf/documents/ecf-emission.service.ts` (comentario del contrato)
- `apps/api/src/ecf/provider/dosa/dosa-emission.spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-same-request-recovery-postgres.integration-spec.ts`
- `apps/api/src/ecf/provider/dosa/dosa-emission-dispatch-http.e2e-spec.ts`
- `docs/ARCHITECTURE.md`
- `docs/ENVIRONMENTS.md`
- `docs/PRODUCT_SPEC.md`
- `docs/ecf/ECF_COMPANY_ENVIRONMENT_DISPATCH_2026-11-13.md`
- `docs/ecf/ECF_CONFIRMED_DOSA_FLOW_2026-11-13.md`
- `docs/ecf/ECF_DOSA_SAME_REQUEST_RECOVERY_2026-11-13.md`
