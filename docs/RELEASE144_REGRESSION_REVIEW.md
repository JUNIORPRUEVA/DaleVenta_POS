# Revision de la entrega 144

## Solicitud y criterio

El propietario informa que la interfaz de acceso difiere de la version que
utilizaba y aparece un aviso generico al iniciar. Conservar Mayoreo/offline,
identificar la fuente exacta de la UI esperada y corregir la causa del error.
No publicar otra compilacion hasta resolver ambas observaciones con evidencia.

## Auditoria verificada

- Base remota:fd03df11217d3942722d14af9c57f929b5905460, production-main.
- Worktree de correccion:C:/src/fullpos-144-fix, agent/release144-regression-audit.
- Los worktrees de produccion original, Mayoreo, offline y releases136-143
  comparten la ubicacion del enlace de recuperacion debajo de Crear mi negocio.
  El delta del login integrado desde offline cambia avisos de conectividad,
  no la posicion del enlace. Esto no demuestra que sea la interfaz esperada.
- No se encontro otra ubicacion en los historicos Git revisados ni en las copias
  ARCHIVOS DEL SISTEMA y backups consultadas. Pendiente version/ruta del usuario.
- Registro instalado:PathAccessException en Zone inmediatamente despues de
  AppUpdate silent check failed, dos arranques2026-10-19. El check de servidor
  devolvio UP_TO_DATE; no es evidencia de credenciales incorrectas.
- La rama offline movio estado, descarga y helper de LOCALAPPDATA a
  ProgramFiles/DaleVentas POS/updates. setup.iss no define esa carpeta ni ACL;
  instalacion real tampoco tiene updates. Las otras carpetas mutables si tienen
  users-modify. Defecto de empaquetado no cubierto por la UAT con raiz writable.

## Plan minimo

1. Prueba de contrato entre carpetas mutables del cliente e instalador; reproducir
   ausencia de updates, corregir solo su provision y permisos sin abrir app/binarios.
2. Analisis y regresion storage/updater, verificar que Mayoreo/offline permanecen.
3. Identificar interfaz requerida por version/fuente, comparar delta por archivo.
   No sustituir una rama completa ni inventar una reubicacion visual.
4. Preparar candidato y verificar instalacion estandar, acceso, startup y updater
   antes de cualquier nueva publicacion. Produccion no modificada en esta revision.

Estado inicial antes de corregir la instalacion: NO-GO para publicar el fix.

## Reproduccion y correccion

- Ejecutable y AOT instalados cotejados por SHA256:coinciden con el candidato144,
  no con un instalador antiguo descargado accidentalmente.
- Prueba windows_installer_storage_contract_test antes del cambio:FAIL,
  Missing installer folder:updates. Comprueba todas las carpetas mutables
  declaradas por WindowsProductPaths y que app no reciba users-modify.
- Cambio minimo:declarar updates en setup.iss con users-modify y preservacion
  al desinstalar, sin permisos adicionales sobre binarios ni cambios de negocio.
- La comprobacion anterior de la entrega144 omitio probar los permisos de una
  instalacion estandar bajo ProgramFiles. Los tests con override UAT no cubren eso.

## Referencia141 indicada por el propietario

- Archivo original:installer/output/FullPOS-Setup-1.0.6-141.exe en DaleVentas POS.
  Bytes40180073;SHA2568CB439B05691288E11F26C89EFF43C885829947717D47A0F9F19FAE6DEAAC1B7.
- Coincide por hash con el instalador en C:/src/fullpos-release-141-build.
  Extraccion selectiva de runner/app.so con innoextract verificado; ambos hashes
  coinciden con los archivos del build141 conservado. No se ejecuto el instalador
  historico ni se accedio a su entorno productivo mediante esa app.
- login_screen.dart en ese worktree no tiene cambios respecto de6b3e38ed.
  Comparacion del Widget build con144:solo formato de TextStyle y withValues,
  sin mover controles, cambiar estilos ni textos. El enlace esta al pie en141.
  No se inventa otra UI. Las mejoras nuevas del baseline141 siguen en144.
- El ejecutable/app.so actualmente instalados coinciden con144 por SHA256:
  no se entrego accidentalmente el binario141 ni un artefacto mas antiguo.
- Prueba de contrato antes:FAIL updates ausente; despues:PASS.
  Regresion67 PASS/1 omitida; flutter analyze limpio.
- Ensayo de compilacion Inno del fix con runtime144 existente:PASS.
  Es artefacto local de validacion, NO publicable ni sustituto del144 original.
  Primera llamada uso ruta absoluta incompatible con SourceDir del script;
  se repitio con ruta relativa y completo correctamente. Sin cambios en script.
- Siguiente candidato145:misma UI/negocio, solo provision updates y version;
  compilar desde commit conocido y verificar antes de cualquier publicacion.

## Candidato145 preparado

- Commit8dd67542382d4d72e2e8a37b3792c1e3787224cb, build oficial fuera de produccion.
- FullPOS-Setup-1.0.6-145.exe,40258303 bytes,NotSigned,
  SHA256 FA66972E49B6E99BEE80BDA7E906ECB2C044E158E174FC7A8FFD2C6113F4201E.
- Helper del145 en verify-only:paquete/target145 PASS0, target146 rechazado9.
  No se instala ni eleva durante esos ensayos.
- Widget build del login145 coincide con141 al normalizar solo espacios y
  comas finales de Dart. Ningun cambio en lib/ ni API frente al144.
- Estado al preparar la seccion: candidato aún no instalado ni publicado; los
  resultados finales de ambas acciones se documentan en las secciones siguientes.

## Instalacion autorizada del145

- Autorizacion del propietario: instalar el candidato, comprobar el arranque y
  publicarlo sin firma solo si pasa, con la condicion de no tener ventas en
  curso. La aceptacion del aviso de Control de cuentas de usuario la realizo el
  propietario; el agente no eleva ni acepta avisos de seguridad.
- Instalacion estandar completada en el equipo del propietario el2026-10-19 a
  las08:07. Registro de aplicaciones instaladas:FullPOS1.0.6(build145) en
  C:\Program Files\DaleVentas POS\. Proceso fullpos_cloud arrancado a las
  08:07:02 con la sesion local restaurada; no se cerro la sesion del propietario.
- Carpeta C:\Program Files\DaleVentas POS\updates presente tras la instalacion
  estandar, con permiso de modificacion para BUILTIN\Usuarios ademas de las
  entradas heredadas de Administradores, SYSTEM y TrustedInstaller.
- El actualizador escribio updates\update_state.json a las08:07:06 con
  lastUpdateResult UP_TO_DATE, targetBuild nulo y lastErrorCode nulo: el
  PathAccessException observado en la144 no se reproduce en la145.
- fullpos-client.log del arranque145 sin PathAccessException ni errores de
  permisos sobre esa ruta. El registro de la144 se conserva para comparacion.
- Test de contrato windows_installer_storage_contract_test reejecutado sobre el
  worktree145:PASS1/1 (carpetas mutables del cliente provisionadas para
  usuarios estandar), tras copiar el asset .env que git ignora.
- Verificacion visual del acceso:no realizada en esta revision porque la
  instalacion arranco con la sesion ya restaurada. No se cierra sesion para no
  interrumpir la operacion del propietario; la comparacion del login145 con141
  sigue siendo la evidencia disponible.
- La publicacion se autorizo condicionada a la aceptacion de instalacion;
  resultado final documentado abajo.
- No se modifico la politica global de firma. Sin seeds, ventas ni cobros de
  prueba; la excepcion unsigned se limito a esta operacion de publicacion.

## Resultado final de aceptacion y publicacion145

- El propietario acepto el aviso UAC e instruyo instalar y publicar145 si la
  prueba pasaba. Instalador devolvio codigo0; archivo instalado es1.0.6+145 y su
  SHA del ejecutable coincide con el runtime candidato. Instalacion bajo
  Program Files provisiono `updates` con Modify para BUILTIN\Usuarios; la
  shell no administrativa pudo crear, leer y retirar un archivo de prueba.
- Arranque del19-oct-2026 mantuvo el proceso activo; registro de AppUpdate
  completado con `update=false` y build `none`; guardo `update_state.json` sin
  PathAccessException. La sesion existente se restauro directamente en
  Facturacion; no se creo ni cobro una venta. La captura visual devolvio otra
  aplicacion; no se reclama inspeccion visual del login ni de Facturacion.
- Publicacion aprobada:145, id `ff5a78cc-0f1b-4535-8bec-ec19404a0539`, unsigned,
  40,258,303 bytes, SHA256
  `FA66972E49B6E99BEE80BDA7E906ECB2C044E158E174FC7A8FFD2C6113F4201E`.
  Retention se ejecuto como dry-run. Los releases142,144 y145 permanecen
  publicados y los tres objetos de almacenamiento existen.
- Check publico: build144 reporta update disponible145; build145 reporta
  up-to-date. Descarga estable devuelve302/no-store y200, encabezado PE `MZ`,
  tamano y SHA iguales al candidato. API health `ok`; servicios API/PWA siguen
  en imagen offline-144, sin redeploy requerido para este cambio de instalador.
- No se uso JWT de publicacion. Se ejecuto la operacion autorizada de release
  desde el contexto API con una excepcion unsigned limitada a esa operacion.
