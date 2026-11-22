# Preparación móvil — 22 de noviembre de 2026

## Alcance y conservación

Rama local: `agent/preparacion-compilacion-movil-20261122`.
Base: `61d5d5aa`, merge del PR #53 en `production-main`.
Worktree aislado: `C:/t/fp-mobile-release-20261122`.

- `9c38754b`: 49 archivos con los ajustes móviles de clientes, usuarios,
  impresora, menús, iconos, cotizaciones y chat; documentación y regresiones.
- `96c37238`: preparación de los dos workflows iOS existentes, sin añadir Android
  a Codemagic. Flutter 3.41.6, configuración pública desde checkout limpio,
  análisis obligatorio y pruebas móviles compartidas.
- Acceso offline conservado separadamente en `db93ce18`, rama
  `agent/acceso-local-seguro-20261122`. No se incluye en esta entrega: la prueba
  de reinicio Android sigue pendiente de resolución y no hay validación nativa iOS.

Los worktrees históricos no se sobrescribieron. El inventario privado de 124
archivos del worktree móvil anterior distingue 86 coincidencias con esta entrega,
25 con la base productiva y 13 variantes históricas. No se copiaron esas variantes
sobre las correcciones posteriores ni se eliminaron archivos de los otros trabajos.

## Evidencia ejecutada

- `flutter analyze` repetido desde el worktree limpio: sin problemas, 75,9 segundos.
- Regresión exacta añadida a Codemagic: 67 pruebas aprobadas y otras 3 del chat.
- YAML: dos workflows iOS, 14 scripts con sintaxis Bash válida y generación de
  configuración probada en dos directorios desechables; sin mostrar valores.
- `flutter build appbundle --release` con las definiciones públicas indicadas en
  `RELEASE.md`: aprobado desde checkout limpio, 166 segundos, 124,2 MB.
- `bundletool 1.18.3 validate`: código 0.
- Manifest del bundle: `com.daleventa.pos`, versión `1.0.7`, versionCode `151`,
  minSdk 24, targetSdk 36.
- `jarsigner -verify`: código 0, `jar verified`. JDK también advierte sobre el
  certificado autofirmado, ausencia de timestamp y diferencias de lectura
  JarInputStream/JarFile. La validación de bundletool sí pasa; queda por comprobar
  la aceptación real en la pista interna de Play, no declarada como ejecutada.
- Certificado del AAB coincide con el keystore local existente.
- Bibliotecas nativas de 64 bits: segmentos ELF comprobados sin alineaciones
  inferiores a 16 KB; configuración del bundle `PAGE_ALIGNMENT_16K`.

El primer intento de build falló porque el registrante generado incluía el plugin
`integration_test` mientras se ejecutaban pruebas en el mismo worktree. Se resolvió
repitiendo secuencialmente desde un checkout separado, sin modificar Gradle ni
introducir el plugin de pruebas en release. Hubo también un primer comando de
verificación JDK mal interpretado por PowerShell; se repitió con el argumento
de idioma entre comillas antes de registrar los resultados.

La evidencia visual y funcional anterior de la misma fuente se conserva en
`AJUSTES_MOVILES_CLIENTES_COTIZACIONES_IA_20261122.md` y
`AJUSTES_MOVILES_USUARIOS_IMPRESORA_20261121.md`. Las pruebas de widgets simulan
repositorios; no equivalen a transacciones productivas ni a un build nativo iOS.

## Artefacto local

`C:/Users/pc/Documents/FullPOS-Mobile-Release-20261122/FullPOS-1.0.7-151-96c37238.aab`

SHA256:
`0C503674FCC0A91D1ED7C0996A13047EFD4D8A7B2A550877128D02F1041A8FDB`

Huella pública SHA256 del certificado de subida:
`0F:F4:07:C4:1C:4E:E2:9D:9F:53:69:E5:6F:48:6E:EC:DE:D2:EB:B9:E9:2E:5E:BE:A6:71:4A:04:F4:56:F6:DE`

Keystore, propiedades y configuración local permanecen ignorados, fuera de los
commits y del directorio de entrega. No se alteraron los originales.

## Pendientes y procedimiento del propietario

1. El propietario solicitó preparar el PR de esta entrega hacia `production-main`.
   Publicar únicamente la rama de preparación; conservar el merge manual y no
   ejecutar Codemagic ni publicar en tiendas desde las herramientas del agente.
2. Esperar los controles del PR y hacer merge manual a `production-main`.
3. Para iPhone, ejecutar el workflow iOS elegido de Codemagic sobre el commit
   integrado. Verificar firma, perfil y aceptación en App Store Connect.
4. Para Android, comparar la huella anterior con el certificado de **subida**
   de Play Console y comprobar que 151 sea mayor que todos los códigos ya usados.
   Si no lo es, actualizar `pubspec.yaml` mediante otro commit y recompilar.
5. Probar actualización desde la versión instalada en pista interna, conservando
   datos, autenticación y funcionamiento de ventas antes de distribución general.

NO-GO para publicación en tiendas hasta completar esos controles. La compilación
Android local está comprobada; iOS nativo y aceptación de tienda siguen pendientes.
No se modificaron backend, Prisma, credenciales fiscales ni datos de empresas.

## iPhone: recorrido después del PR

1. En GitHub, esperar todos los controles del último commit y revisar el PR.
   El propietario hace merge a `production-main`; no compilar una rama antigua.
2. En la aplicación existente de Codemagic, pulsar **Start new build**, elegir
   la rama `production-main` y comprobar el commit del merge.
3. Elegir **iOS TestFlight** (`ios-testflight`) para producir una IPA firmada.
   **iOS Release Build (No Codesign)** produce una IPA sin firma que no se puede
   instalar normalmente en un iPhone ni subir como entrega firmada.
4. Conservar la integración `CodemagicKey`, el perfil App Store para
   `com.fulltechrd.fullposcloud` y el equipo `M4WNZDXN2U`. La configuración local
   coincide con `ios/ExportOptions.plist` y el proyecto Xcode; la vigencia de
   certificados, perfil y permisos Apple se confirma al ejecutar el build remoto.
5. La versión canónica es `1.0.7+151`. El workflow calcula el número iOS como
   el mayor entre 151 y `PROJECT_BUILD_NUMBER + 100`; no consulta el último build
   de Apple. Confirmar que sea un número nuevo y una versión admitida en Apple.
6. Codemagic ejecuta análisis y regresión móvil antes del build, y verifica
   versión, bundle y firma de la IPA antes de la carga a App Store Connect.
   `submit_to_testflight: false` permanece intacto. La carga remota y cualquier
   distribución a testers se revisan posteriormente en App Store Connect.

Esta preparación no acredita un build nativo de iOS desde Windows ni la vigencia
de las credenciales guardadas en Codemagic. El GO actual solo puede ser para
revisión del PR y, después de controles y merge, intentar el build remoto.
