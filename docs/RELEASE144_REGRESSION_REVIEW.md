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

Estado:NO-GO para nueva publicacion; diagnostico y correccion local en curso.

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
