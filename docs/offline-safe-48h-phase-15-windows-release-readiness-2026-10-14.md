# FullPOS Cloud Offline Safe 48H — Fase 15

Fecha: 2026-10-14. Worktree `C:\src\fullpos-offline-safe-48h`, rama
`feature/offline-safe-48h`, HEAD `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.

**GO técnico del motor offline nuevo dentro del UAT demostrado. NO-GO técnico
integral del candidato, NO-GO para ejecutar piloto de actualización con datos
reales y NO-GO para distribución general.** Se conservaron los cambios anteriores.
No hubo producción, push, merge, deploy, cambios en main ni actualización de clientes.

## 1. Documentación y criterio de aceptación

Se revisaron la auditoría final de sincronización previa a Fase 11
(`offline-safe-48h-final-sync-audit-2026-10-14.md`, antecedente solicitado de
Fase 10; no se encontró un informe separado cuyo nombre diga phase-10), los
informes de Fases 11–14 y las políticas de arquitectura, entornos, release,
testing y workflow. Se verificaron estado Git y manifiestos de fuentes.
No se repitieron implementaciones económicas ni se reconstruyeron clientes antiguos.

Aceptación: inventario trazable de artefactos auténticos locales, alcance real de
compatibilidad, exportación legacy de solo lectura sin credenciales reconocibles,
copias de base verificadas, regresiones actuales y decisiones separadas para
motor UAT, candidato, piloto y distribución. No se toma un snapshot de código
como equivalente al instalador distribuido.

## 2. Hallazgo que corrige la atribución histórica de Fase 14

HECHO: al ampliar la búsqueda al repositorio original autorizado se encontraron
instaladores **+130 y +132** con manifiestos cuyo SHA256 coincide con el archivo.
La ausencia informada en Fase 14 correspondía a un alcance de búsqueda menor.
Los informes anteriores se conservaron como evidencia histórica; esta sección
actualiza la conclusión con los artefactos encontrados.

En particular, el snapshot `69dd871b` de 2026-09-17 declara +130 pero no envía
turno de origen. El manifiesto del instalador Windows +130 encontrado apunta a
`e8473c02ee7e8022a34650343c13852fcfea1248`, de 2026-10-06, cuyo código **sí**
incluye `originCashSessionId` en la creación y envío de ventas. No corresponde
atribuir a todos los binarios +130 la omisión del snapshot anterior.

HECHO: la petición sin turno continúa fallando con 409 sin mutación. Esto prueba
el contrato seguro para esa forma de operación, incluyendo pendientes heredados
sin origen, pero no prueba que el +130 encontrado la emita al crear ventas nuevas.
La emisión real del binario todavía requiere ejecución aislada. La referencia
del manifiesto es evidencia local de build, no una atestación criptográfica de
compilación ni de distribución a clientes. Ambos manifiestos declaran deployed=false.

## 3. Inventario de instaladores

Se ejecutó `scripts/uat/phase15-artifact-inventory.ps1`. Alcance de lectura:

- `C:\src\fullpos-136` a `C:\src\fullpos-141`.
- `C:\src\fullpos-release-141-build` y `fullpos-release-141-20261013215837`.
- Bajo `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS`:
  `installer`, `release` y `release_artifacts`.

Se excluyeron dependencias, .git, builds internos de terceros y dispositivos de
clientes. El inventario registra cada ruta absoluta, versiones PE, tamaño,
SHA256, LastWriteUtc, firma, manifiesto coincidente, contenido updater y límite
de ejecución. Resultado: **21 archivos / 15 hashes distintos, todos NotSigned**.
La fecha de modificación no acredita una fecha de publicación.

Evidencia completa: `.uat/evidence/phase15-artifact-inventory.json`.
Cada payload se listó sin ejecutar su instalador. Las copias de idéntico SHA
comparten el resultado de inspección. No hay prueba de entrega a clientes.

### +130 y +132: procedencia local verificable

Raíz de las siguientes rutas: `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS`.

| Artefacto | Ruta relativa | Bytes | SHA256 |
| --- | --- | ---: | --- |
| +130 | release_artifacts/FullPOS-Setup-1.0.6-130-e8473c02.exe | 40131240 | A0383ABB772347D76A9394CC3F56C233F6D149A7AE218846D6E514644F67A6E9 |
| +132 | installer/output/FullPOS-Setup-1.0.6-132.exe | 258900588 | EC3A60BFADF8C5E00E37B2FC11EA6BDA9C80162C1A2806DFB993F3A6FD1A172D |

| Dato | +130 | +132 |
| --- | --- | --- |
| Versión PE del instalador | 1.0.6.130 | 1.0.6.132 |
| Versión del runner extraído | 1.0.6+130 | 1.0.6+132 |
| Commit declarado por manifiesto | e8473c02ee7e8022a34650343c13852fcfea1248 | f1be244c2331eda16ccbc969ecda3693b1756887 |
| Timestamp de build declarado, UTC | 2026-10-06T17:46:42.6646855Z | 2026-10-09T11:53:31.699Z |
| LastWriteUtc del archivo | 2026-10-06T17:46:16.6717379Z | 2026-10-09T11:53:31.6997089Z |
| Manifiesto | release_artifacts/windows-release-1.0.6-130-e8473c02-manifest.json | installer/output/windows-release-1.0.6-132-f1be244c-manifest.json |
| Firma del instalador / runner | NotSigned / NotSigned | NotSigned / NotSigned |
| Contiene FullposUpdater.exe | No | Sí, app/updater/FullposUpdater.exe |
| Puede ensayarse aislado ahora | Extracción/inspección sí; instalación/app no ejecutadas | Extracción y verifier-only sí; instalación/app no ejecutadas |

Se extrajeron únicamente runners, AOT y helper hacia `.uat/phase15-authentic`;
no se extrajo ni imprimió el .env. No se parchearon ni recompilaron esos archivos.
SHA256 del runner130: `7F913F0ED92DC5AC74F879C2C8E749C65E9AF2A8751D176DD862F8F545190CF7`.
SHA256 de su app.so: `2D95159249FB1C99FA5A8226DB4CB2BEFCC27C1E446B9B52FB5C94A2E2EEC457`.
SHA256 del runner132: `05CC2225F78FB4070D655DE727C1C3DC8CD29F2DC9B389FC02479F363E8026DC`.
SHA256 de su app.so: `4A1C6583FCCFC842D63CD40918AB5959FA4212BE3F27840BAEAA5C1925C34346`.
SHA256 del helper132: `34C60BD91CF6CB6B3BCFDE7F0BD6F1003296CBD0468D9F44F3ACA6A9F439373C`.
Evidencia: `phase15-extracted-files.json` y listados de payload bajo `.uat/evidence`.
Authenticode sobre app.so produjo UnknownError: no se cuenta como firma válida.

### Otros hashes locales realmente disponibles

Versiones de esta tabla son metadatos PE del instalador. Solo +130/+132 tienen
verificación adicional del runner extraído. Sus rutas y fechas individuales
están en el inventario completo; no se atribuye distribución ni commit a los
otros archivos. Todas las firmas son NotSigned.

| Versión PE | Bytes | Copias | SHA256 | Updater incluido |
| --- | ---: | ---: | --- | --- |
| 1.0.4.121 | 259581080 | 1 | CE9929E083FCAB89534B090975B1EFCB8F0356332A82BC2C42F55594BE3E2278 | No |
| 1.0.5.122 | 258099919 | 1 | 45968DC05095A7FBE03310B71D3F875F87B8741BF9023CD72BD230F51F33B94B | No |
| 1.0.5.123 | 258107663 | 1 | F9E56DAC558A8F308A19BA91A981E7F38C76DB878CC68C85EC4EDE91D9803352 | No |
| 1.0.5.124 | 258694261 | 1 | FAC0F4AA5C57B818556ACD1FA58E01C8E3AC0507D30E0F834CDD11446A6C9C55 | No |
| 1.0.6.135 | 40179535 | 1 | 6EB6C0D392AB92CEA56E98E98B575F2656C1B502A6FBBE5E3FCE9B8A342FFD67 | Sí |
| 1.0.6.136 | 40177684 | 2 | 42297C67E141F94E0AA679C004C54062286550448272388292BD846DEF938BD3 | Sí |
| 1.0.6.137 | 40176952 | 2 | 3902B80C8412AD77143706FACE372D09D84F1E8D37C7FA6946EE4D95819EE23A | Sí |
| 1.0.6.138 | 40180441 | 2 | 68B952131D49DCBDB0FF4B61E86D08509CC2A7D8BBFEDDDCF91D44E4A25E3137 | Sí |
| 1.0.6.139 | 40177539 | 2 | 999B9163A02E785A4512ABC55D9B185ECD01FF5A6D5A31D3D58D70C3666DC8B4 | Sí |
| 1.0.6.140 | 40181714 | 2 | B8DD35FD3F46FC523AB41DE57D330B310C55C9537AD07468B665CAB84300BEDB | Sí |
| 1.0.6.141 A | 40175138 | 1 | 645C62A810118F78B91806B3CA25D7D9CA24A4F181C387D03B1161C89BE22163 | Sí |
| 1.0.6.141 B | 40180073 | 2 | 8CB439B05691288E11F26C89EFF43C885829947717D47A0F9F19FAE6DEAAC1B7 | Sí |
| setup.exe, PE1.0.0.1 | 251582662 | 1 | F31837C89845B3532463E634D95D4C05AF687EAFED9522CABB61F9F2BCCBE601 | No |

Las dos variantes +141 tienen hashes diferentes: no son intercambiables por
número de versión. El setup genérico no permite inferir la versión real de su
aplicación. **+133 no encontrado** en las raíces autorizadas consultadas.

## 4. Aislamiento y matriz real A–G

HECHO: no se lanzó ningún POS histórico ni instalador histórico en este host.
Los instaladores comparten identidad y acciones de instalación globales; `/DIR`
por sí solo no aísla registro, accesos directos, redist ni almacenamiento seguro.
Además, el código del commit130 da prioridad a API_BASE_URL compilada; cambiar
un .env no demuestra que el binario deje de apuntar a su backend original.

No están disponibles los launchers WindowsSandbox, VBoxManage o vmrun por PATH.
Existe Get-VM de Hyper-V, pero su ejecución devolvió:
`You do not have the required permission to complete this task.`
No se elevaron permisos ni se crearon reglas de red globales. Por ello falta un
Windows desechable con aislamiento de red verificado antes de ejecutar esas apps.
No se intentó acceder a equipos de clientes.

| Caso | Resultado real | Cobertura / límite |
| --- | --- | --- |
| A histórica → backend candidato | NO EJECUTADO con app histórica | Instaladores130/132 auténticos locales verificados; falta VM y red controlada. Fuentes de sus commits envían origen, no equivalen a captura de ejecución |
| B histórica → actualización candidata | NO EJECUTADO | 130 sin helper empaquetado; 132 helper auténtico probado solo como verifier. Instalación/actualización completa pendiente |
| C pendientes → update → sync | PASS banco nativo F14; NO VERIFICADO con cohortes históricas auténticas | Se reutiliza evidencia A14001→B14002, no se reconstruye130/132 |
| D interrupción → recuperación | PASS banco F14; NO VERIFICADO con instaladores históricos | Banco Inno aislado, SQLite y WAL/SHM confirmados; no updater elevado completo |
| E venta histórica sin turno | PASS rechazo seguro HTTP y conservación técnica | Fixture nuevo de contrato sin origen:409, cero venta/descuento; no captura de app histórica. Originales manuales preservados |
| F nuevo → nuevo | PASS UAT técnico | Regresiones actuales + banco F14 nativo SQLite/identidad/grant/PG; UI final y hardware no declarados aprobados |
| G nuevo → backend antiguo | PASS bloqueo seguro en pruebas de negociación; conjunto NO VERIFICADO | Suite Flutter de compatibilidad y evidencia DTO histórica; no API antigua completa ejecutada en esta fase |

No se considera una combinación completa aprobada por inspeccionar código o
extraer archivos. No se fabricaron snapshots adicionales para llenar esas celdas.

## 5. Ventas legacy: rechazo y exportación sin modificación

Se conservó `409 LEGACY_MISSING_SESSION`. El smoke actual
`phase14-legacy-http.cjs` se ejecutó sobre API46552/base desechable y su resultado
se archivó como `.uat/evidence/phase15-legacy-http.json`: no se creó la venta y
stock permaneció20. Es un payload del contrato sin origen, no del instalador130
encontrado. No se activó compatibilidad financiera global ni se eligió turno por
estado abierto o coincidencia de fecha. No se ejecutó conciliación real.

### Defecto reproducido y corrección mínima del exportador

HECHO: el exportador anterior copiaba la fila completa sin examinar secretos en
payloads anidados o mensajes de error. Cuatro casos de prueba demostraron el
defecto (ValueError esperado no se produjo). Se corrigió únicamente la exportación:

- Examina recursivamente estructuras JSON y JSON serializado en strings.
- Rechaza claves de credenciales, Authorization/Bearer, JWT reconocible,
  URLs con credenciales, cadenas PostgreSQL y PEM de clave privada.
- Ante detección, falla **antes de crear el expediente**, con un error genérico
  que no contiene el valor. No redacta ni modifica la operación original.
- Conserva lectura SQLite `mode=ro`, `query_only`, cierre de handle, filtros de
  empresa/usuario/identidad, hashes y creación exclusiva del archivo de salida.
- El guard de ruta manual compara componentes sin distinguir mayúsculas.

Siete pruebas pasan: scope/identidad, exclusión de cotizaciones/origen explícito,
hashes, bytes originales intactos, no sobrescritura de expediente y rechazo CLI
de credenciales sin archivo de salida ni valor sensible en stdout/stderr.
No se leyó un .env ni se exportaron credenciales para comprobarlo.

Límite: no es un clasificador universal de secretos dentro de texto libre.
Antes de compartir un expediente, un responsable debe revisar notas/errores
en el entorno autorizado. Si hay información sensible no reconocida, no compartir
el expediente; conservar el original restringido y ampliar la detección con una
prueba, sin volcar su contenido en logs ni respuestas.

### Procedimiento preparado; no ejecuta conciliación

1. Identificar la instalación y su hash/version exactos; detener el trabajo del
   operador en una ventana acordada sin descartar ni limpiar pendientes.
2. Obtener copia SQLite consistente mediante Backup API y verificar integrity_check;
   si se archiva una base física activa, preservar DB/WAL/SHM como conjunto. No
   copiar solo el archivo DB mientras hay escrituras. Conservar original inmutable
   y documentar empresa, usuario y hashes en almacenamiento restringido.
3. En una **copia** y dentro del scope autenticado, listar `sales.create` con
   payload JSON válido sin `originCashSessionId`/`cashSessionId`. No tratar la
   fecha de venta como prueba de turno; no reencolar ni borrar nada.
4. Exportar una operación por expediente con `phase14-legacy-case.py` hacia una
   ruta `.uat` nueva. El guard prohíbe la raíz manual. Si se detectan secretos,
   detener exportación y revisar localmente; no alterar el original para eludirlo.
5. El supervisor reúne evidencia independiente por operación y registra su
   referencia/hash. Buscar duplicados en backend por empresa+clientRequestId y
   comparar toda la economía antes de contemplar envío. Un turno abierto actual
   o un horario parecido no bastan. Sin prueba inequívoca, conservar409 y pendiente.
6. Una eventual recuperación requiere autorización expresa separada, hash del
   original sin cambios y misma identidad económica; turno cerrado o divergencias
   requieren decisión supervisada. El exportador no tiene apply, red ni envío.

Las ocho ventas manuales y la cotización fallida no fueron conciliadas de nuevo.
Comparación de todas sus filas antes/después: pending_actions1, sales8, items20,
payments8 e inventory_intents20 idénticos. integrity_check=ok. Consulta PG de
solo lectura:8ventas únicas,20líneas,20movimientos y turnos originales; candidatos
remotos de la cotización histórica=0, recuperación aplicada=false.

## 6. Updater nativo y firma

Se conservó y aprovechó el banco A14001→B14002 de Fase14: identidad de dispositivo,
TokenStorage/secure storage y grant/sello originales, vencimiento48h, turno,
producto→entrada→venta, SQLite/WAL/SHM e interrupción/reinstalación. La sincronización
nativa perdió tres ACK y concilió stock16. Son resultados **anteriores reutilizados**;
no se presenta un segundo ciclo nativo completo como ejecutado en Fase15.

Nuevo ensayo: `phase15-native-verifier-bench.ps1`, en raíz exclusiva `.uat`,
usa el helper auténtico extraído de +132 y el helper candidato. Paquete Inno del
banco F14 SHA256 `A0D74F3A1108BF67EF4AE9B3727ABA13729A72CE3DA70C815F3039DED630C552`.
Ambos se ejecutaron con `--verify-only`, sin parent/restart ni instalación:

| Helper | Excepción unsigned solo UAT | Hash incorrecto | Firma exigida sobre paquete sin firma |
| --- | --- | --- | --- |
| Auténtico132 | exit0, verify-only success | exit4, rechazo | exit5, SIGNATURE_INVALID |
| Candidato | exit0, verify-only success | exit4, rechazo | exit5, SIGNATURE_INVALID |

Evidencia: `.uat/evidence/phase15-native-verifier.json`, logs en
`.uat/phase15-native-verifier`. Ninguna prueba relajó la política de producción.
El banco de preservación de archivos también pasó de nuevo; sigue siendo fixture.

HECHO: almacenes `Cert:/CurrentUser/My` y `Cert:/LocalMachine/My` consultados:
**0 certificados de code signing, 0 con clave privada utilizable**. No se buscó
ni exportó una clave privada, no se fabricó certificado y no se firmó nada.
Esto no acredita inexistencia de un servicio de firma externo: no hay uno
aprovisionado/verificado para esta tarea. Los21 instaladores locales son NotSigned.

En UAT se pueden ensayar sin infraestructura comercial el hash, rutas, rechazo
de firma ausente y persistencia del banco. **No se pudo validar confianza de
publisher/firma válida, elevación/UAC ni relanzamiento automático completo**.
Hace falta certificado/servicio aprobado, candidato UAT firmado y Windows
aislado interactivo. No se sustituyó ese recorrido por una afirmación de GO.

## 7. Compatibilidad PostgreSQL y SQLite

### Prisma en copia auténtica pre-expansión

`phase15-migration-rehearsal.ps1` crea una base NUEVA
`daleventa_offline_safe_48h_phase15_migration_uat` en el PostgreSQL local56548,
rechaza sobrescritura y restaura `.uat/evidence/phase11_postgres_before.dump`.
Backup SHA256 `ABF2FB0233ACF526912DFEE64CF9188E7D48123303D1E7B962B1AF4C90DA7F95`.
Comprueba identidad del clon antes de ejecutar Prisma. Se encontraron31 migraciones
y se aplicó la pendiente `20261014153000_offline_operation_payload_hash`.
La anterior de operation_id ya estaba en ese backup: no se afirma que se haya
reaplicado. No se hizo rollback artificial ni se modificó una migración existente.

| Tabla del tenant UAT | Filas antes/después | Huella de contenido antes=después |
| --- | --- | --- |
| Product | 6/6 | eae5dfee6f99b1f613590885ed75c1ff |
| Sale | 51/51 | c604bf8f67de151eb22e032074b97f4f |
| inventory_movements | 74/74 | 73a93bc68efa2007a0a5a82de83f1a92 |
| cash_sessions | 9/9 | 98034d9bee84ed75952fa0b54cad4363 |

Las huellas MD5 son comparaciones de todas las columnas históricas serializadas,
excluyendo las nuevas columnas aditivas; no son firmas de autenticidad. Los
hashes históricos de payload permanecieron null. Evidencia:
`.uat/evidence/phase15-migration-rehearsal.json/log`. No migración compartida/productiva.

### SQLite

Los commits declarados por los instaladores130/132 y el candidato usan schema3.
Se creó una copia consistente del UAT manual, se abrió con OfflineStore candidato
y se verificó cada fila de cinco tablas antes/después: idénticas, versión3 e
integridad ok. Prueba real opt-in `offline_store_uat_copy_test.dart` PASS.
Evidencia `.uat/phase15-sqlite-copy/verification.json`; el test no tiene red ni
sincroniza. No se requería transición de versión en esa copia. **No se acredita
migración desde SQLite1/2 auténticos**, cuyas bases no están disponibles aquí.
El banco de fallos SQLite pasó errores esperados locked5/readonly8 y preservó
fuente. No hubo reset ni eliminación de datos.

El backend sigue aceptando contratos demostrados sin operationId para producto
y stock (smokes actuales), y ventas con turno e identidad explícitos (sync/Jest).
Sin turno verificable mantiene409. No se promete seguridad de reintentos sin
identidad estable ni compatibilidad funcional de todo cliente anterior.

## 8. Regresiones y fallos

Evidencia bajo `.uat/evidence/` salvo indicación distinta. Resultados de esta fase:

| Comando ejecutado | Resultado | Evidencia |
| --- | --- | --- |
| `flutter analyze` | PASS inicial/final, sin issues | phase15-flutter-analyze-final.log |
| `flutter test` | 1316PASS,3omitidas; después se añadió/ejecutó focal de copia | phase15-flutter-test.log |
| `flutter test test/core/offline/offline_store_uat_copy_test.dart` con opt-in y raíz aislada | 1PASS | phase15-sqlite-copy.log |
| `npm --workspace apps/api test -- --runInBand` | 752PASS,8omitidas;74suites | phase15-jest.log |
| `npm run api:build` | PASS Prisma generate+tsc | phase15-api-build.log |
| `npx prisma validate` desde apps/api con perfil UAT | PASS | phase15-prisma-validate.log |
| `python -m unittest discover -s scripts/uat -p test_phase14_legacy_case.py -v` | 7PASS final | phase15-exporter-tests-final.log |
| `phase15-artifact-inventory.ps1 -ExtractorPath .uat/tools/innoextract670/innoextract.exe` | PASS21archivos,2manifiestos coincidentes,15payloads listados | phase15-inventory.log y JSON |
| `phase15-migration-rehearsal.ps1` | PASS clon Prisma, filas/huellas conservadas | phase15-migration-rehearsal.log |
| `run-sync-integrity-smoke.ps1 -DisposablePhase12` | PASS3ventas/3líneas/3movimientos,total360 | phase15-sync.log |
| `run-product-stock-integrity-smoke.ps1` | PASS1producto/1entrada/1venta,stock16,5concurrentes | phase15-product-stock.log |
| `node scripts/uat/phase14-legacy-http.cjs` con perfil clon46552 | PASS409 sin mutación de venta/stock | phase15-legacy-http.json/log |
| `run-sqlite-failure-bench.ps1` | PASS fallos esperados, fuente preservada | phase15-sqlite-failure.log |
| `run-updater-preservation-bench.ps1` | PASS fixture de archivos; no instalación histórica | phase15-updater-preservation.log |
| `phase15-native-verifier-bench.ps1` | PASS6casos con helpers real132 y candidato | phase15-native-verifier.json/log |
| `node scripts/uat/audit-phase11-preservation.cjs` con perfil local | PASS lectura PG | phase15-preservation-postgres.log |
| Backup API y comparación completa SQLite manual | PASS | phase15-manual-preservation.json |
| `git diff --check` | PASS; sin errores whitespace | phase15-diff-check.log |

No se ocultan fallos:

- Exportador:4reproducciones fallaron antes de corregir; `phase15-exporter-repro-before.log`.
  Corrección del guard de secretos →7pruebasPASS, sin cambio financiero.
- innoextract1.9 oficial no reconoció el formato6.7 del instalador: exit2 y
  advertencia de loader/checksum. No se interpretó como corrupción del instalador:
  sus hashes coinciden. Se usó el fork670 compatible y se verificó el digest SHA256
  del ZIP publicado en GitHub API antes de ejecutarlo. La extracción no instala.
- Primer ensayo de extracción no pudo crear la ruta anidada; se crearon directorios
  nuevos. Filtros con `/` seleccionaron cero archivos; se corrigieron a `\` y se
  exigió el conjunto exacto de cinco archivos130/132. No se contó una selección vacía
  como evidencia de extracción válida.
- Harness de inventario: usar `$matches` permitió que PowerShell sobrescribiera
  esa variable automática al evaluar una regex; se corrigió a `$matchingManifests`
  y se comprobó exactamente dos coincidencias130/132. No hay10manifiestos probados.
- Hyper-V Get-VM: acceso denegado por permisos; bloqueo real de ejecución aislada.
- Signature-required: exit5 es el rechazo esperado de un paquete sin firma,
  **no** una prueba de firma válida ni un FAIL corregido desactivando seguridad.

Las APIs locales se detuvieron tras identificar sus procesos para liberar Prisma
durante build y se restauraron: health46548/46552=200 al finalizar validación.
No se detuvo PostgreSQL ni se tocaron servicios productivos.

## 9. Procedimiento de piloto propuesto, no autorizado ni ejecutado

RECOMENDACIÓN: realizar primero un piloto de laboratorio con copia ficticia o
debidamente autorizada, después decidir un piloto con operador. Requisitos previos:

1. Windows VM desechable accesible, sin carpetas compartidas de producción,
   credenciales de clientes ni acceso a backends comerciales. Denegar salida a
   Internet antes del primer arranque y permitir solo el backend UAT confirmado.
   Probar el aislamiento; un flag de UI/.env no lo sustituye.
2. Seleccionar un hash concreto del instalador histórico130/132 y un hash concreto
   del candidato. Registrar manifiesto, firma/publisher válidos cuando se exijan
   y versión monotónica; resolver la ambigüedad de variantes con igual número.
3. Copia consistente de SQLite y sus sidecars, identidad/config y almacenamiento
   seguro por un mecanismo Windows aprobado, sin exportar tokens/clave a un informe.
   Snapshot/backup previo con restauración ensayada; conservar originales fuera
   de la VM. No sustituir datos reales por un fixture para declarar preservación.
4. Crear operaciones ficticias con identidades y dependencias conocidas; registrar
   turno, totales y hashes. Ensayar A–G, interrupción, cierre/reapertura offline,
   expiración48h, reconexión, pérdida de ACK y conciliación por empresa/operación.
5. Ejecutar Dart→helper→espera de padre/mutex→UAC→instalador→relaunch con paquete
   UAT firmado, sin canal comercial. Observar identidad/grant antes de renovar.
6. Detener el piloto ante pérdida/cambio de identidad, extensión de grant offline,
   cambio de turno, duplicado, payload divergente, mezcla de empresas o firma inválida.
   Preservar logs y pendientes; no resetear, reidentificar ni enviar automáticamente
   una operación de resultado incierto.
7. Rollback: aislar la instancia fallida y conservar sus escrituras/pendientes.
   Restaurar el estado previo solo sobre otra copia aislada. No prometer que
   restaurar un backup antiguo recupera escrituras posteriores; conciliar IDs antes
   de reactivar para no duplicar compromisos remotos. Evitar bajar versión sin
   compatibilidad de esquema demostrada.
8. Con evidencia completa, revisión del responsable y autorización expresa del
   dispositivo/empresa/ventana, decidir piloto limitado. No ejecutar cambios en
   clientes reales bajo esta tarea. Distribución general exige otra decisión posterior.

## 10. Riesgos, cobertura pendiente y veredictos

| Área | Decisión |
| --- | --- |
| Motor offline nuevo, integridad/idempotencia y recuperación en UAT demostrado | **GO técnico acotado**; suites y evidencia real, no aprobación de distribución |
| Candidato Windows como actualización histórica integral | **NO-GO técnico integral**: A/B históricas completas pendientes, +133 ausente, aislamiento bloqueado |
| Piloto de actualización con datos reales | **NO-GO de ejecución**: procedimiento preparado; falta entorno aislado accesible, firma y recorrido completo, revisión/autorización operativa |
| Continuar ensayos desechables ya autorizados | Permitido dentro del alcance UAT; no equivale a un piloto comercial aprobado |
| Distribución general | **NO-GO**: compatibilidad por binario y flujo firmado/elevado/relaunch sin cerrar |

Riesgos restantes: procedencia de distribución no acreditada aunque haya dos
builds locales vinculados a manifiestos; mezcla de snapshots con igual versión;
dos instaladores141 distintos; SQLite1/2 auténticos no ensayados; backend anterior
completo no ejecutado; GUI/hardware final no aprobado por estas herramientas;
ventas sin origen requieren revisión independiente; cotización histórica continúa
fallida y preservada. No se deben reabrir implementaciones económicas ya validadas
para convertir esas limitaciones en un GO aparente.

## 11. Archivos y fuentes consultadas

Cambios exclusivos de Fase15:

- `scripts/uat/phase14-legacy-case.py`: rechazo de secretos, guard de ruta manual.
- `scripts/uat/test_phase14_legacy_case.py`: regresiones de no filtración.
- `scripts/uat/phase15-artifact-inventory.ps1`: inventario y payloads de solo lectura.
- `scripts/uat/phase15-migration-rehearsal.ps1`: migración en copia nueva con huellas tenant.
- `scripts/uat/phase15-native-verifier-bench.ps1`: seis verificaciones nativas aisladas.
- `apps/fulltech_app/test/core/offline/offline_store_uat_copy_test.dart`: apertura de copia real.
- Este informe. Evidencia y herramientas descargadas permanecen bajo `.uat` ignorado.

Fuentes externas del extractor, sin uso de canales FullPOS:
[upstream innoextract](https://constexpr.org/innoextract/) y
[release670 del fork Windows utilizado](https://github.com/UserUnknownFactor/innoextract_win/releases/tag/670).
ZIP del fork SHA256 `79b69b9b1fcd98f42ccd4b245efdf6a03bcfb674ba6af482f5a46891c9ed4d14`,
contrastado con el digest del asset de GitHub; no se lo presenta como una firma
de los instaladores FullPOS. El inventario registra también el hash del extractor.

Herramientas utilizadas: terminal PowerShell/git, apply_patch, Flutter/Dart,
Node/Jest/Prisma, Python/SQLite, Docker/PostgreSQL, Authenticode/almacenes de
certificados Windows, consulta web y extracción read-only. Sin subagentes ni
interacción gráfica o remota con clientes. Se detiene en Fase15, sin publicación.
