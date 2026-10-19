# FullPOS Cloud Offline Safe48H — Fase17: cierre Windows

2026-10-14. HECHO=observado; HIPÓTESIS=no demostrado; RECOMENDACIÓN=acción futura.
Las evidencias privadas están en `.uat/evidence/phase17-*`; no contienen aquí
credenciales. Este informe describe las diferencias respecto de F16, sin sustituir
sus límites ni convertir process kill en prueba de apagón físico.

## 1. Resultado y continuidad de F16

**Motor nuevo: GO técnico dentro de la cobertura UAT demostrada. Candidato17002:
preparado y abierto para UAT local; aceptación Windows integral pendiente.
Piloto y publicación: NO-GO en su estado actual.** No se publicaron releases,
actualizaron clientes, tocaron producción, hicieron push/merge/deploy ni commits.

F16 se verificó antes de modificar:24/24 hashes de su manifiesto coincidentes;
1135 archivos fuente inventariados. Se conserva su evidencia de20 cortes de
proceso, SQLite3.52.0, idempotencia, reconciliación y grant48h. No se repitieron
los20 cortes ni se cambiaron ventas, almacenamiento, negocio o backend en F17.
La suite completa nueva aprobó1335 pruebas Flutter y752 backend.

Worktree `C:\src\fullpos-offline-safe-48h`, rama `feature/offline-safe-48h`, HEAD
`6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`. Cambios anteriores y archivos sin
rastrear preservados. Solo3 archivos fuente existentes cambiaron frente al
baseline: adaptador del instalador, helper C++ y su CMake. El FullPOS del proyecto
ECF abierto en otro worktree no se detuvo ni modificó.

## 2. Defectos nuevos y correcciones mínimas

| ID | Causa verificada y evidencia previa | Corrección y prueba |
|---|---|---|
|17-01 P0|El estado persistido `ProductionUnsignedPolicy/NotSigned` habilitaba unsigned aunque la política vigente estuviera deshabilitada. Test esperaba rechazo por publisher y llegaba a buscar el helper.|Se exige además `Env.allowUnsignedUpdatesForProduction` actual. El estado guardado no concede permiso. Regresión PASS.|
|17-02 P0|Un paquete preparado podía entregarse sin comparar su build con la instalación actual. Tests de target129/130 frente a130 fallaban.|Se consulta PackageInfo real en el handoff, se rechaza build desconocida y target<=actual. Tests PASS.|
|17-03 P0|Helper aceptó PE ProductVersion17001 declarando target17002: verify-only exit0, sin ejecutar instalador (`phase17-native-binding-before.json`).|Se vincula el target con ProductVersion real del PE; ahora exit9. Ausencia de versión:exit8. `phase17-native-binding-after.json` y banco nativo PASS.|
|17-04 P0, endurecimiento|Código validaba antes de esperar padre/mutex; ruta .exe podía reutilizarse después sin nueva verificación. No se ejecutó un ataque de instalación previo.|Se revalida el ejecutable final y se mantiene handle de lectura sin compartir escritura/borrado durante el lanzamiento/instalación. El camino compartido se prueba en verify-only: reemplazo durante espera termina exit4, sin installer start. ShellExecute/UAC positivo pendiente.|
|17-05 P1|Deshabilitar updates no impedía un handoff de estado preparado anterior.|El adaptador rechaza también `appUpdatesDisabled` antes del helper. Test PASS.|

No se redujo firma, hash, tenant, autorización ni idempotencia. La comprobación
de versión lee ProductVersion textual: el instalador Inno tiene FileVersion vacío,
por lo que no se inventa su build a partir de campos numéricos vacíos.
Se enlaza version.lib. Referencia primaria:
[Version information de Windows](https://learn.microsoft.com/en-us/windows/win32/menurc/version-information).

Los códigos8/9/10 significan versión ausente/build no coincidente/archivo no
bloqueable. Si el paquete está en uso o no puede verificarse, se rechaza; no se
deshabilitan locks. El helper auténtico+132 no hereda estas correcciones.

## 3. Candidato verificable

| Dato | Valor |
|---|---|
|Build final|1.0.6+17002; Windows Release x64|
|Instalador UAT|`.uat/phase17-update-final-bank/packages/FullPOS-Phase17-Candidate-17002.exe`|
|Bytes|39766454|
|SHA256 instalador|`FA0368B27E896FCC256094769297D19E63A36908178043A1298111DEFE57C2D7`|
|SHA256 runner|`3B059CD1B4FFE60E05A72D154976C99FF77A97B7E1CEE87CE4FB8D629182F89B`|
|SHA256 helper|`749B12075625211C411C14986EB1ACB0A3D8AD2B10B1E8FA3D03030A0EA49FD5`|
|SQLite|3.52.0, DLL consultada en ejecución|
|API|127.0.0.1:46552, clon UAT; API manual46548 preservada|
|Política de esta build|Updates deshabilitados; excepciones unsigned UAT/producción=false|
|Firma|NotSigned; no se presenta como distribución comercial|
|AppId/root Inno|Exclusivos de laboratorio; sin registro, uninstall, elevación ni borrado de datos|

`phase17-candidate-manifest.json` registra hashes de todos los archivos del build
y comprueba igualdad con runtime instalado. Fuentes Dart completas y helper
copiados al build coinciden byte a byte con los actuales. La copia corta `.uat/n17`
solo cambia el mutex UAT a `FullPOSPhase17UAT`; conserva el namespace de datos de
prueba `FullPOSPhase16NativeUAT` usado por A. No cambia el runner comercial.
El instalador utiliza destino fijo .uat y rechaza `/DIR` distinto.

La interrupción dejó `is-SM0HWRZTEV.tmp` únicamente en el banco desechable; se
conservó como evidencia y se excluyó del manifiesto de runtime esperado. No está
en la carpeta fuente del paquete ni se distribuye dentro del instalador final.

Arranque realizado con `scripts/uat/run-phase17-candidate.ps1`: PID29824,
título de proceso `FullPOS Cloud - Sistema de facturacion [UAT]`, datos en
`.uat/phase17-visual`, sin importar DB legacy al existir override explícito.
Se observaron conexión127.0.0.1:46552 y DB/WAL/SHM nuevos en esa raíz. Estos son
metadatos de proceso/red y archivos, **no PASS visual** de login/POS.
La ventana quedó abierta. El propietario confirmó por respuesta explícita:
**«Sí, veo el POS sin error»**. Esto aprueba visualmente el arranque del POS,
no una venta nueva ni actualización completa. En el segundo paso el propietario
confirmó: **«Muestra Sin actualización pendiente, sin error»**. Arranque del POS
y pantalla Actualizaciones quedan aprobados visualmente por el propietario,
sin atribuir al agente una inspección de imagen ni repetir pantallas no afectadas.

## 4. Instaladores auténticos y búsqueda limitada

Se rehasharon los21 archivos de F15: mismos tamaños y SHA. Dos manifiestos
exactos conservan su hash y apuntan a los mismos artefactos; todos siguen sin
firma válida. Extractor previamente verificado por SHA, sin descargas nuevas.
Se listaron y extrajeron nuevamente solo5 archivos whitelist (runner/AOT/helper),
con hashes idénticos a F15; no se extrajo .env ni se ejecutaron instaladores/apps.
Evidencia: `phase17-artifact-verification.json`, `.uat/phase17-authentic-verified`.

Raíz de las rutas históricas siguientes:
`C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\DaleVentas POS`.

| Versión | Artefacto, tamaño y SHA256 | Procedencia y contenido |
|---|---|---|
|+130|`release_artifacts/FullPOS-Setup-1.0.6-130-e8473c02.exe`;40131240B;`A0383ABB772347D76A9394CC3F56C233F6D149A7AE218846D6E514644F67A6E9`|Manifiesto e8473c02; runner1.0.6+130; **sin helper nativo**|
|+132|`installer/output/FullPOS-Setup-1.0.6-132.exe`;258900588B;`EC3A60BFADF8C5E00E37B2FC11EA6BDA9C80162C1A2806DFB993F3A6FD1A172D`|Manifiesto f1be244c; runner1.0.6+132; helper SHA`34C60BD91CF6CB6B3BCFDE7F0BD6F1003296CBD0468D9F44F3ACA6A9F439373C`|
|+133|NOT AVAILABLE en las11 raíces locales documentadas de builds/installer/release/manifiestos|Sin sustituto reconstruido; no probado ni declarado distribuido|

Coincidir con manifiesto local no acredita distribución a clientes. El código
de +130 auténtico e8473c02 y +132 f1be244c conserva originCashSessionId; no se
confunde con el snapshot69dd871b. El envío real desde sus GUI no fue ejecutado.
El script de build de e8473c02 fija API productiva mediante dart-define, con
prioridad sobre .env: una VM por sí sola no demuestra que pueda dirigirse a UAT.
f1be244c también usa dart-define para API. Cualquier ensayo histórico debe probar
primero un modo de direccionamiento UAT autorizado; si el binario no lo permite,
marcar ese tramo BLOCKED, sin recompilarlo y llamarlo auténtico ni puentear TLS.

## 5. Updater y cadena de confianza: cobertura real

| Etapas | Resultado y límite |
|---|---|
|Detección/manifest/download|PASS: AppUpdateRepository/UpdateDownloader reales contra HTTPS loopback con certificado efímero confiado solo por ese cliente de prueba. Es fixture de manifiesto, no publicación AppRelease comercial.|
|.part, tamaño y SHA|PASS transferencia real del paquete; hash equivocado no alcanza READY; incompleto se limpia.|
|Redirect/traversal/replay|PASS: no sigue redirect a otro host, rechaza filename traversal antes de HTTP y no ofrece build ya instalada.|
|Firma/publisher|Rechazo correcto del paquete unsigned:exit5/SIGNATURE_INVALID. **Positivo firmado BLOCKED**;0 certificados de code-signing disponibles.|
|Coordinación antes de ejecutar|PASS guards Dart y verify-only con padre real; sustitución detectada. Cierre GUI/handoff/UAC normal completo NOT RUN en F17.|
|Reemplazo y recuperación|PASS Inno aislado14017→17002, tres puntos de interrupción, SQLite abierta. No AppId/ProgramFiles comercial.|
|Identidad/grant/turno|Campos de las8 pendientes fixture idénticos; código auth/48h/storage sin cambios. Evidencia nativa F14 reutilizada; no un nuevo E2E completo histórico de identidad/grant.|
|Relanzamiento|Main17002 arrancado manualmente por launcher verificado. Relanzamiento desde helper/UAC BLOCKED.|
|Reconexión/sync/PG|PASS smokes independientes contra clon con3 ventas y cadena producto/stock. No se afirma una única ejecución GUI desde instalador histórico hasta PG.|

HTTPS bank:6 PASS (`phase17-https-bank.json`). TLS efímero no es Authenticode,
no acredita publisher, no se instaló en el trust de Windows y no desactiva
verificación TLS. Clave ignorada por git y nunca impresa. Native bank:9 PASS
(`phase17-native-verifier.json`): integridad, build incorrecta, hash, root,
firma exigida, helper auténtico132, versión ausente y sustitución durante espera.

Hash acredita integridad; la autenticidad del manifiesto depende aquí del canal
TLS/API configurado, no de una firma autónoma del JSON. Authenticode, editor,
confianza de Windows y reputación SmartScreen son comprobaciones distintas.
No hay PASS positivo para ninguna cadena de publisher firmada ni SmartScreen.

`docs/RELEASE.md` describe un puente histórico unsigned en el build oficial;
el checkpoint histórico EXECUTION_STATE exige firma para producción. No se
interpretó el puente como autorización para cambiar la política en esta tarea.
El candidato ensayado desactiva ambas excepciones: aceptar unsigned en pruebas
verify-only no habilita distribución ni un handoff comercial sin firma.
Si el propietario decide otro régimen de distribución, requiere decisión
explícita y validación propia; no se obtiene un PASS suprimiendo controles.

## 6. SQLite, WAL y conservación económica

Banco Inno final:8 pendientes sintéticas, incluyendo producto, entrada, venta,
cadena dependiente, cotización, fallo recuperable/permanente, legacy y resultado
ambiguo; conserva todas sus filas exactas, company/user/turno/IDs/dependencias.
Mientras el owner SQLite seguía abierto, DB/WAL/SHM conservaron hashes después
de cada interrupción y reinstalación. Commit no checkpointed recuperado. Después
se consultó la DB con la DLL3.52.0 del candidato:integrity=ok y8 pendientes.
`phase17-update-bank.json`. El fixture de preservación no es un payload comercial
ejecutable y no se sincronizó; no se cuenta como prueba de negocio de esos8 tipos.

Original manual: Backup API consistente antes/después, filas exactas iguales:
8 ventas,20 líneas,8 pagos,20 intenciones,1 pendiente. Cotización
`quotes.create:local_quote_1791944878261619` intacta, sin reencolar ni recuperar.
PG solo lectura:8 ventas únicas,20 líneas,20 movimientos,turnos originales,
0 candidatos remotos para la cotización. Evidencias:
`phase17-manual-preservation.json`, `phase17-manual-postgres.json`.

Smokes F17 en clon:3 ventas,total360,3 líneas/3 movimientos,mismo turno;
producto+20→venta−4→stock16,1 producto/1 entrada/1 venta,5 retries concurrentes.
Legacy source-shaped sin vínculo de turno:409 LEGACY_MISSING_SESSION,0 venta
y stock intacto. No equivale a la GUI del instalador+130 ni permite inferir turno.

Multiempresa/48h: fuente de auth, grants, sync, caja, almacenes, productos y
ventas sin cambios (baseline1135). Regresión final incluye scope switch,
emergency policy, rechazo de actor distinto, intento remoto, backup/downgrade y
compatibilidad backend. No se extendió grant al actualizar, no se regeneraron
identidades ni se bloqueó sync por vencimiento. El nuevo handoff preserva la
arquitectura cloud; SQLite continúa siendo contingencia temporal, no autoridad.

## 7. Matriz de compatibilidad

PASS se limita a la prueba descrita; ningún snapshot sustituye un instalador
auténtico. Las combinaciones no ejecutadas no heredan el PASS del motor.

| Combinación solicitada | Estado F17 | Cobertura/límite |
|---|---|---|
|+130 auténtico→backend candidato|BLOCKED|Artefacto/runner verificados; falta Windows desechable y direccionamiento UAT autorizado del binario.|
|+132 auténtico→backend candidato|BLOCKED|Igual límite; helper real sí ejecutado verify-only.|
|+133→backend candidato|NOT RUN|NOT AVAILABLE; excluir de versiones certificadas.|
|Nuevo→backend candidato|PASS|Smokes HTTP/PG; proceso main17002 conectado al clon; GUI de venta aún no confirmada.|
|Nuevo→backend anterior|NOT RUN|No nuevo E2E en F17; contratos automatizados PASS y evidencia F13/F15 reutilizada, sin cambio de protocolo.|
|Instalador antiguo→updater nuevo|BLOCKED|130 carece de helper; no tratar130/132 como equivalentes ni asumir actualización automática.|
|Updater anterior→instalador nuevo|BLOCKED integral|Helper132 PASS integridad/rechazo firma del paquete17002; instalación/UAC/relaunch no ejecutados.|
|SQLite legacy→app nueva|PASS focal|v1→3/backup/downgrade en driver real; no DB obtenida tras instalación auténtica130/132.|
|Pendientes legacy→backend nuevo|PASS rechazo seguro|409 sin turno, sin efecto. Conciliación solo supervisada con evidencia de origen.|
|Prisma actual→backend candidato|PASS|Build/validate nuevos;31 migraciones aplicadas,0 abiertas en clon F15; rehearsal real F15 y archivos SQL sin cambios. No se aplicaron nuevas migraciones.|
|14017→17002 laboratorio|PASS reemplazo/preservación|3 interrupciones con WAL y8 pendientes; no circuito elevado/GUI completo.|

## 8. Hardware y pruebas externas: impacto y aceptación

Hyper-V Get-VM continúa devolviendo falta de permisos. Windows Sandbox,
VirtualBox y VMware no aparecen como opciones ejecutables disponibles en la
inspección acotada. La VM worker visible y el emulador Android no acreditan un
Windows de laboratorio autorizado. No se elevaron privilegios ni escanearon
equipos de terceros/red para buscar un segundo equipo.

SEWOO SLK-TS100 y POS80 registrados figuran WorkOffline=true. Las Epson/PDF
presentes no acreditan térmica/cajón UAT autorizado. No se imprimió RAW ni se
abrió cajón o cambió driver/Defender/SmartScreen. Impresión/cajón físicos BLOCKED;
tests de ticket existentes pasan en la suite. Un fallo de impresión nunca debe
crear otra venta ni descontar stock otra vez.

El corte físico NOT RUN no es un P0 de software probado ni bloquea por sí solo
un piloto que acepte el límite WAL/FULL y no afirme certificación eléctrica.
SmartScreen sin reputación tampoco es equivalente a un bug financiero. Hardware
solo bloquea el piloto que dependa de esas funciones; +133 ausente solo bloquea
una declaración de soporte que lo incluya. No se usan esos pendientes opcionales
para mantener un NO-GO genérico indefinido.

## 9. Regresiones, fallos de laboratorio y archivos

| Comando realmente ejecutado | Resultado |
|---|---|
|`flutter analyze`|PASS final sin issues,46,6s|
|`flutter test`|1335 PASS,5 omitidas,4min12s; antes de añadir el banco HTTPS opt-in, probado aparte|
|`flutter test test/core/app_update/windows_installer_handoff_test.dart` antes del fix|5 fallos esperados que reprodujeron omisión de guards; no se lanzó helper|
|Suite focal updater existente+nuevo handoff|62 PASS|
|`FULLPOS_PHASE17_HTTPS=true` y `flutter test test/core/app_update/phase17_https_update_bank_test.dart`|6 PASS con HTTPS/helper reales|
|Regresión focal final updater/offline48h/compatibilidad/scope/storage/sale attempt|91 PASS,1 omitida (banco HTTPS opt-in, ejecutado aparte)|
|`npm --workspace apps/api test`|752 PASS,8 omitidas,74 suites|
|`npm run api:build`|PASS Prisma generate+tsc; APIs propias detenidas por DLL y reabiertas|
|`npx prisma validate` desde apps/api|PASS|
|`flutter build windows --release --build-number=17002 --dart-define=API_BASE_URL=http://127.0.0.1:46552 --dart-define=APP_BASE_URL=http://127.0.0.1:46552 --dart-define=DISABLE_APP_UPDATES=true --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_UAT=false --dart-define=ALLOW_UNSIGNED_UPDATES_FOR_PRODUCTION=false` desde .uat/n17|PASS37,7s; C++ /W4 /WX|
|`phase17-artifact-verification.ps1`|21 artefactos,2 manifiestos,5 archivos extraídos PASS|
|`phase17-update-bank.ps1`|3 etapas PASS,8 pendientes y DB/WAL/SHM preservados|
|`phase17-native-verifier.ps1`|9 PASS; verify-only, sin UAC|
|`run-sync-integrity-smoke.ps1 -DisposablePhase12`|PASS|
|`run-product-stock-integrity-smoke.ps1 -DisposablePhase12`|PASS16 y5 retries|
|`node scripts/uat/phase14-legacy-http.cjs` con envclone|PASS409 seguro; evidencia anterior restaurada tras capturar resultado F17|
|`run-phase17-candidate.ps1`|Proceso[UAT] abierto; después el propietario confirmó POS y Actualizaciones sin error|
|`git diff --check`|Verificación final registrada en phase17-git-diff-check.log|

Incidencias propias corregidas sin ocultar resultados: primer test usó una API
dotenv inexistente y se ajustó a testLoad de5.2.1 antes de reproducir el defecto;
filtro de extracción con slash devolvió0 archivos y la aserción detuvo el banco
(se corrigió al separador real, preservando intento); Get-FileHash inicial no
compartía lectura con SQLite abierta, se sustituyó en el banco por FileStream
read-only con FileShare.ReadWrite/Delete, sin saltar ACL ni alterar locks SQLite.
El intento fallido preservó sus8 pendientes. Build17001 quedó como intermedio;
17002 es el único candidato final de esta fase. No se rebajó ningún assert.

Archivos propios modificados/añadidos:

- `apps/fulltech_app/lib/core/app_update/app_update_installer_io.dart`.
- `apps/fulltech_app/windows/updater/main.cpp`, `CMakeLists.txt`.
- `apps/fulltech_app/test/core/app_update/windows_installer_handoff_test.dart`.
- `apps/fulltech_app/test/core/app_update/phase17_https_update_bank_test.dart`.
- `scripts/uat/phase17-artifact-verification.ps1`.
- `scripts/uat/phase17-live-update-fixture.py`, `phase17-candidate.iss`, `phase17-update-bank.ps1`.
- `scripts/uat/phase17-native-verifier.ps1`, `run-phase17-candidate.ps1`.
- `docs/EXECUTION_STATE.md` (encabezado actual, conserva checkpoint histórico).
- Este informe. Los demás cambios del git status pertenecen al trabajo acumulado.

## 10. Cierre de bloqueos y cuatro decisiones

Los P0 nuevos de handoff/build y ventana de sustitución están corregidos dentro
del alcance probado. No se identificó un P0 financiero nuevo sin mitigar en el
motor actual. El camino positivo de ejecución bajo UAC y firma no está validado;
no se confunde cierre de código con aceptación funcional del circuito completo.

| BLOQUEO | CAUSA | EVIDENCIA | ESTADO | ACCIÓN NECESARIA | ¿BLOQUEA PUBLICACIÓN? |
|---|---|---|---|---|---|
|Estado unsigned obsoleto / downgrade preparado|Faltaban gates vigentes|5 tests antes;62/91 después|CORREGIDO|Conservar regresiones|No, en candidato nuevo|
|Target no ligado al PE / sustitución tras espera|Metadatos y ejecutable no se revalidaban juntos al final|before exit0/after9; reemplazo exit4|CORREGIDO; UAC positivo pendiente|Ensayo firmado del helper bajo UAC|Sí para updater integral hasta ese ensayo|
|130/132 auténticos completos|Sin Windows desechable autorizado; API de producción compilada puede impedir UAT|Get-VM denegado; inventario/compilación histórica|BLOCKED|Dispositivo/VM autorizado y ruta UAT probada antes de conectar app|Sí para certificar upgrades históricos; no impide seguir UAT nuevo|
|Publisher y cadena elevada final|Certificado ausente; paqueteNotSigned|0 certificados,WinTrust rechaza|BLOCKED|Artefacto final firmado/editor configurado y UAC/relaunch en laboratorio|Sí para flujo de distribución con política de firma ensayada|
|GUI de arranque/Actualizaciones|Sin control nativo del agente; validación manual autorizada|Propietario confirma POS y Sin actualización pendiente sin error|CERRADO en ese alcance|No repetir pantallas no afectadas|No; no equivale al E2E firmado|
|133|Artefacto no hallado ni distribución atestada|Búsqueda limitada vacía|NOT AVAILABLE|Excluir de matriz certificada u obtener original verificable|Solo si se promete soporte133|
|Térmica/cajón|Dispositivos offline/no equipo UAT confirmado|InventarioWin32_Printer|BLOCKED|Prueba física si el piloto usa impresión/cajón|Condicional al alcance del piloto|
|Apagón físico/SmartScreen reputación|Sin equipo/canal representativo|F16 nivelA;firma ausente|NOT RUN|Runbook dedicado; registrar límites|No son bloqueo universal por sí solos|
|Piloto real|No existe aprobación expresa ni dispositivo seleccionado|Alcance actual soloUAT|PENDING EXTERNAL|Autorizar dispositivo, versión/matriz, métricas y suspensión|Sí para iniciar piloto; no autoriza producción|

| Nivel | Decisión y criterio |
|---|---|
|Motor offline|**GO técnico acotado**: preservación/idempotencia/48h/conciliación/regresión demostradas; no garantía física universal.|
|Candidato Windows|**GO para UAT local preparado**, con arranque/Actualizaciones visualmente confirmados; **NO-GO de aceptación integral** hasta el circuito positivo de actualización firmado requerido.|
|Piloto controlado|**NO-GO para iniciarlo ahora**: laboratorio/transición y aprobación pendientes. Puede limitarse a nuevas instalaciones/versiones realmente aceptadas; no se exige133 o impresora si se excluyen explícitamente.|
|Publicación general|**NO-GO**: faltan cadena final y matriz/instalación aceptadas y autorización. No basta el paquete de laboratorio.|

## 11. Próximos pasos exactos y recuperación

**No queda otra acción manual solicitada en esta ventana.** El propietario ya
confirmó POS y Actualizaciones sin error. No se registraron ventas nuevas para
repetir pantallas no afectadas. La ventana UAT permanece abierta. Si debe reabrirse,
usar `pwsh -File scripts/uat/run-phase17-candidate.ps1`; rechaza segunda instancia
y verifica hashes/API antes de abrir. No usar run-windows-portable contra raíz manual.

Para cerrar la actualización histórica sin abrir otra fase:

1. Operador proporciona Windows desechable autorizado, sin datos reales, con
   snapshot/restauración y salida de red denegada por defecto. No usar el PC principal.
2. Transferir instaladores130/132 y manifiestos; recalcular los hashes de §4.
   Instalar primero sin red. Confirmar versión/rutas/AppId/helper y preservar snapshot.
3. **Gate de API:** probar un método soportado que dirija el binario intacto a
   backend ficticio. No basta editar .env si dart-define lo fija; no probar el
   endpoint productivo, desactivar TLS ni presentar una reconstrucción como original.
   Si no hay método autorizado, registrar BLOCKED ese E2E y limitar alcance de piloto.
4. Solo al superar ese gate, login ficticio, turno UAT inequívoco, producto nuevo,
   entrada20, venta4 y captura de IDs/turno/grant/DB/WAL/SHM. Preparar pendientes
   de la matriz y backup consistente verificado, conservando original inmutable.
5. Usar paquete final de producto con firma/publisher que cumpla la política
   aprobada; verificar manifiesto, SHA, versión, WinTrust y editor. +130 sin helper
   necesita bootstrap/instalación supervisada diseñada y validada, no una supuesta
   actualización automática por helper inexistente.
6. Detección→download→READY→cierre seguro→UAC cancelar y aceptar→reemplazo→relaunch.
   Registrar versión instalada, misma identidad/grant/turno y cola. Expirar grant
   solo en fixture controlado: nuevas ventas denegadas, sync pendiente permitido.
7. Reconectar a UAT, perder ACK de forma controlada y conciliar una venta/un efecto,
   producto20−4=16, efectivo/turno originales y ninguna fila de otra empresa.
8. Fallo: conservar DB/WAL/SHM y paquetes/logs. Reinstalar binarios compatibles;
   no restaurar DB antigua sobre ventas posteriores, no forzar downgrade y no
   reasignar turno. Resultado ambiguo queda protegido hasta conciliación supervisada.
9. Aprobar el circuito y seleccionar dispositivo/alcance/métricas del piloto,
   respaldo, observabilidad, responsable y condiciones de suspensión: duplicado,
   diferencia de stock/caja, cambio de actor/turno, pending perdido o archivo no verificado.
   La aprobación del propietario sigue siendo externa; esta tarea no ejecuta piloto.

Hardware, si se incluye: confirmar térmica/cajón UAT físicamente conectados;
registrar conteos/stock antes, emitir una venta fixture, imprimir y reimprimir
**la misma identidad**, desconectar impresora/papel/cajón de forma controlada,
reconectar y comprobar que no nace otra venta ni movimiento. Sin hardware ese
resultado es BLOCKED, no PASS del test de ticket. No enviar pruebas a una Epson
o impresora de terceros solo porque figure online.

Apagón físico futuro: máquina dedicada autorizada y datos ficticios, backup
verificado/UPS cuando corresponda; registrar operación y límite de commit antes
del corte autorizado; al encender conservar DB/WAL/SHM, verificar agregado/cola,
reconectar a clon y cotejar IDs/stock/caja. Process kill, VM stop y corte físico
se registran por separado. No ejecutar este procedimiento en el host principal.

Riesgos residuales: hardware puede incumplir flush; corrupción coherente puede
perder completitud; recuperación empresarial sigue siendo responsabilidad
backend/operador; una operación incierta puede bloquear cobros hasta revisión.
Los helpers antiguos no reciben correcciones nuevas antes de una transición.
No se afirma compatibilidad total ni se autoriza distribución del instalador UAT.
