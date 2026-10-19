# Integracion Offline 48h + Mayoreo

## Alcance y autorizacion

El propietario solicita integrar todos los cambios offline de 48 horas, conservar
Mayoreo y las mejoras productivas recientes, actualizar production-main,
desplegar API/PWA y crear/publicar un nuevo instalador. Ejecucion continua con
gates internos; no incluye seeds, ventas de prueba ni reparaciones en produccion.
La decision anterior de conservar Windows 142 correspondia al release Mayoreo;
el nuevo pedido autoriza preparar y publicar un instalador combinado posterior.

## Base verificada

- Produccion/main: 2f33df45e732322df794bb58e245d741798e40e1.
- Snapshot offline: 8c19bbac5693376919057fe1aad9348a2493d934, padre 6b3e38ed.
- Fuente preservada: C:/src/fullpos-offline-safe-48h, feature/offline-safe-48h.
- Integracion: C:/src/fullpos-offline-prod, agent/offline-mayoreo-integration-20261018.
- Snapshot aislado sin tocar indice/archivos originales; excluye uploads UAT,
  archivos de entorno y tres imagenes ajenas a la funcionalidad.

## Plan y criterios de aceptacion

1. Revisar el delta y resolver los siete conflictos preservando ambas funciones.
2. Verificar autorizacion 48h por empresa/usuario/dispositivo, vencimiento,
   recuperacion durable, idempotencia, inventario/caja y precios de Mayoreo.
3. Ejecutar analisis, API build, suites completas y smokes en UAT aislada.
4. Revisar migraciones aditivas y ensayarlas; comprobar compatibilidad del cliente
   publicado y limites reales del actualizador. No atribuir pruebas historicas
   de otras builds al candidato combinado.
5. Generar artefactos API/PWA/Windows fuera del servidor, desde commit conocido;
   registrar version, hashes, configuracion, evidencia funcional y visual.
6. Revision final, respaldo, autorizaciones especificas aplicables y rollback.
   Integrar production-main, desplegar artefactos inmutables y verificar salud,
   versiones y descarga. Conservar Windows 142 y las imagenes anteriores.

## Estado actual

Integracion completada en 1c2c7a61. Validacion en curso; no publicacion nueva.

## Revision y validacion observada

- Siete conflictos resueltos: ignores, UAT safety, rutas SQLite, POS, ventas,
  runner y script UAT. Conservados aislamiento Mayoreo, grants48h, intentos
  durables y recalculo al digitar cantidad. UAT build usa ruta fisica corta;
  rechaza salida productiva mezclada, sin borrar archivos ni usar subst.
- sqlite3 Dart3.1.7 incluia SQLite3.52.0 retirado oficialmente. Se fija3.3.2,
  SQLite3.53.1 estable, y su dependencia native_toolchain_c0.18.0. Referencias:
  https://www.sqlite.org/releaselog/3_52_0.html
  https://pub.dev/packages/sqlite3/changelog
- Omision detectada al combinar: replay de ventas no reenviaba priceListId,
  priceListManualOverride ni sourceQuotationId. Se conservan en el handler.
- npm ci PASS; npm run api:build PASS; Jest completo76 suites/766 PASS/8 skips.
  Audit npm:23 avisos,3 altos en cadena de desarrollo ts-node-dev/chokidar/braces;
  sin fix disponible. No se aplica actualizacion masiva ajena al alcance.
- flutter analyze --no-pub PASS. Primera suite completa1368 PASS/6 skips.
- Clon local exclusivo: fullpos_offline_mayoreo144_uat, localhost56549;
  API46554. Fuente UAT Mayoreo preservada, sin cambios de datos originales.
  Migraciones20261014113000 y20261014153000 aplicadas por Prisma:PASS.
  Primer intento uso credencial UAT obsoleta de otra copia y fue rechazado;
  se identifico el origen correcto sin cambiar credenciales ni registrar valores.
- Smoke HTTP/PG: grant48h;5 reintentos concurrentes de producto/stock/venta;
  una sola operacion; rechazo de contenido distinto; stock correcto;
  DTO online legacy compatible y venta sin turno rechazada sin reasignacion.
  Mayoreo15x70=1050, replay tras cambiar regla devuelve la misma venta/total.
- Flutter opt-in offline_mayoreo_http_acceptance_test:API local real, SQLite3.53.1,
  grant real, conexion interrumpida, venta local15x70, cierre/reapertura SQLite,
  envio de lista manual original, sincronizacion y reintento sin doble stock:PASS.
  Se corrigio un getter incorrecto del test antes de ejecutarlo correctamente.

## Limites del alcance

La contingencia48h admite operaciones autorizadas y conservadas por dispositivo;
ventas fiscales y pagos no efectivos necesitan conexion. Resolver nuevos precios
mayoristas requiere API; el carrito mayorista ya calculado puede conservar su
snapshot y sincronizarse. Un cambio posterior incompatible queda para revision,
no autoriza inventar precios ni reasignar pendientes a otro turno/empresa.
No se certifica hardware ni apagones fisicos mediante pruebas de proceso.

NO-GO para publicar hasta completar los gates restantes y registrar resultados.

## Candidato combinado verificado

- Fuentes de runtime:53aa9bb1143168ee56697da20ff1612860e1bcfc. Commit f521df07
  solo agrega llaves de estilo a un test; diff de API/lib/pubspec contra53aa vacio.
- Regresion Flutter final con HTTP UAT opt-in incluido:1369 PASS/6 omitidas.
  Analisis final limpio. Las dos incidencias de estilo del test nuevo se corrigieron.
- API Docker offline-144: build y ensayo HTTP/PG completos PASS, healthy.
  Dependencias comprobadas: Nest11.2.7, compression1.8.2, sharp0.35.5,
  express5.2.1, multer2.4.0; sin regresion frente a produccion.
  Config digest:e2884dae0fb60634f4a467551facef9749b0202a97c8236677359447d881205b.
- PWA144: build Flutter3.41.6 PASS; nginx -t PASS; version144,
  shell/bootstrap144-53aa9bb1, Brotli y proxy a API clon local PASS.
  Config digest:693fa36e90188aa5b618ac5c9989f955013ce5fc9714326eaff85012886e4f9d.
- Windows oficial144 compilado/empacado por script oficial. Archivo
  FullPOS-Setup-1.0.6-144.exe,40257613 bytes,NotSigned,
  SHA256:8F645A0402B8D30ADE40B58603F14AAF1469AB436ABE2C751B112B32931DFE87.
  No certificado de firma configurado ni certificado CodeSigning personal.
- Helper real del candidato:5 casos verify-only PASS (paquete valido bajo
  politica unsigned, build distinto, hash distinto, fuera de raiz y firma requerida).
  No instala, eleva ni cambia instalaciones del usuario.
- Windows UAT144 separado: startup nativo inspeccionado por Computer Use;
  login visible sin aviso de inicio, namespace FullPOS Offline144 UAT, datos
  .uat/app-root y API46554. UAT142 del propietario permanece abierta/preservada.
- Avisos offline:4 tests visuales PASS, capturas escritorio1366/mobile360 al130%
  inspeccionadas; texto completo sin desbordamiento. Los cuadrados de iconos
  pertenecen al banco de widgets sin fuente Material; no al ejecutable.
- PWA local4184 cargo landing y semantica de botones en navegador. Captura CDP
  agoto timeout; no se reclama PASS de screenshot de navegador ni login web.
  La presentacion modificada se valido con los widgets y Windows indicados.
- Snapshot fuente:170 archivos cotejados, ninguno cambio en el worktree offline
  desde la captura. Los worktrees originales y sus indices permanecen intactos.
- Paquete de imagenes:244532004 bytes, SHA256
  36ae1030077565fd27037856da391fe0887acc879fd1b323acf77f0951a0d111.
- Backup productivo previo: /root/fullpos-deploy-backups/offline-144-20261018/
  database-before-offline144.dump,6346483 bytes, catalogo pg_restore validado,
  SHA25614462f0647d9def235d3c5fca771a6f18e7d0dbe425aa7475be5e8c429ca4e1d.
  Especificaciones API/PWA143 privadas0600 preservadas. Produccion saludable,
  cero migraciones fallidas, solo las dos migraciones offline pendientes.

## Gates productivos especificos

Deploy y nueva publicacion autorizados por el pedido actual. AGENTS.md10 exige
autorizacion explicita para las dos migraciones productivas. Ademas la politica
del backend exige firma; publicar este instalador requiere excepcion unsigned
limitada a144. El propietario respondio "Autorizo ambas acciones para la version
144" a la solicitud concreta de migraciones y excepcion de firma con el hash
8F645A04...31DFE87. Autorizacion recibida; no se modifican politicas globales.
Rollback: conservar imagenes143 y Windows142; ante fallo de salud abortar/volver
a imagen143. El esquema aditivo se conserva, sin downmigration ni restauracion
automatica que descarte operaciones reales posteriores.

## Ejecucion productiva autorizada

- production-main actualizado a90246e01d78caad65a9c4c37586913c30550e21c,
  descendiente de2f33df45, sin reemplazar mejoras recientes. Runtime53aa9bb1.
- Transferencias ensambladas en servidor; ambos SHA256 exactos verificados.
  Imagenes cargadas, no compiladas en produccion, config digests coincidentes.
- Respaldo inmediato database-immediate-20261019T113743Z.dump,6353590 bytes,
  catalogo validado, SHA256
  28df640667f404fff9c6d5f8a8e89d461e237dbab36f48ed9c9351355b9554f1.
- Primer intento de migracion P1001 por seleccionar red general easypanel;
  no alcanzo PostgreSQL. Reejecutado en easypanel-daleventapos:Prisma PASS,
  ambas migraciones aplicadas y verificadas por consulta de historial.
- API offline-144 saludable. Web offline-144 en rollout. Configuracion,
  mounts y puertos preservados; imagenes143 disponibles para rollback.
- Windows144 borrador1efef881-4c3f-4dd4-8794-fd64058a8660 preparado con
  clases reales del backend, DTO validado y verificacion completa R2 SHA/bytes.
  Excepcion unsigned limitada a esta operacion; politica global intacta.
- Sin seeds ni ventas/cobros/ajustes de prueba en produccion.
  Publicacion completada tras ambos rollouts Swarm completed.

## Cierre productivo

- API y PWA offline-144:Swarm completed, health publico ok, web1.0.6/144,
  shell/bootstrap144-53aa9bb1; endpoints Mayoreo y grant offline401 sin sesion.
- Cero ERROR de runtime desde el despliegue. Env/mounts/EndpointSpec iguales
  a143. No credenciales ni politicas globales cambiadas.
- Windows144 publicado2026-10-19T11:40:32.951Z, release
  1efef881-4c3f-4dd4-8794-fd64058a8660; hash y bytes del candidato aprobado.
  Retencion dry-run:true;142 sigue PUBLISHED, storageDeletedAt null.
- Entrada de descarga estable:
  https://daleventapos-backend.gcdndd.easypanel.host/api/app-updates/windows/latest/download
  Renueva URL firmada en cada consulta; no divulgar los enlaces R2 privados.
- Comprobacion externa final PASS:build142 ofrece144;144 no recibe update;
  descarga completa40257613 bytes/MZ y SHA2568f645a04...31dfe87 exactos;
  ruta estable302/no-store hacia144. Sin enlaces antiguos en ese circuito.
- Estado GO para integracion/despliegue/publicacion del alcance validado.
  No se afirma instalacion automatica en el equipo del propietario, prueba
  de hardware, corte electrico fisico ni certificacion de instaladores historicos.
