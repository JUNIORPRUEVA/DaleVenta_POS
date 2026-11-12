# Avisos de error compactos — evidencia visual (2026-11-11)

Capturas reales de la app UAT en Windows (`fullpos_cloud_uat_mayoreo.exe`, modo debug,
`DALEVENTAS_POS_ROOT=C:\b\fp-uat-data`), con un servidor local que devuelve un manifiesto de
actualización inválido (`sha256: 'bad'`) en `GET /api/app-updates/check`.

## 01-antes-aviso-bajo-el-velo-de-licencia.png

Estado inicial: el aviso existía y estaba bien colocado, pero se pintaba **debajo** de
`LicensePurchaseOverlay` en el `Stack` de `main.dart`. El velo semitransparente de esa capa lo dejaba
ilegible. El texto visible en esa captura («No pudimos completar la operación») era el error genérico
provocado por el `Tooltip` de `LicensePurchaseOverlay`, no el aviso del actualizador.

## 02-despues-aviso-actualizador-abajo-derecha.png

Tras mover `AppErrorOverlay` al final del `Stack`:

- Aviso compacto en la **esquina inferior derecha**, elevado por encima de la franja de acciones.
- Texto exacto de negocio: «No pudimos comprobar las actualizaciones.» / «Puedes seguir utilizando
  FullPOS normalmente.», con botón de cerrar (X) accesible.
- Ningún detalle técnico en la superficie del cliente. El `FormatException`, el contexto
  `actualizacion:CHECK_ERROR` y el stack trace solo aparecen en el panel «Diagnóstico interno», que
  existe únicamente en compilaciones de diagnóstico (`kAppDiagnosticsUiEnabled`).

## 03-reinicio-mismo-dia-sin-aviso.png

Segundo arranque del **mismo día** con el mismo fallo: no se muestra ningún aviso. La marca
`flutter.error_notice_last_shown.updater = 2026-11-11` vive en
`%APPDATA%\FullPOS\FullPOS UAT Mayoreo\shared_preferences.json`, un almacén **independiente** del
`UpdatePersistence` que puede estar roto.

## 04-fix-aviso-abierto.png

Con el defecto del `Tooltip` de `LicensePurchaseOverlay` ya corregido y la marca diaria limpia:
el aviso aparece con estilo **neutro** (icono informativo gris, sin rojo ni ámbar), texto humano y X
funcional. La consola de `flutter run` ya no emite ningún `No Overlay widget found`.

## 05-fix-aviso-cerrado-tras-clic-real.png

Tras un clic real (automatización de ratón sobre la ventana) en la X: el aviso desaparece y la
pantalla queda intacta. El clic no afecta a ningún otro control.

## 06-compacto-abierto-dos-lineas.png / 07-compacto-cerrado.png

Versión final, más pequeña: **dos líneas exactas** (título + descripción), ~48 px de alto y 360 px de
ancho frente a los ~103 px de la versión anterior. Sin fila de acciones (el aviso no requiere
decisión), icono 16 px, título 12,5 px w800 y descripción 12 px. Ambos textos se leen completos en
1280×720, sin recortes. La X sigue cerrando el aviso (clic real verificado en 07).

Los avisos `error`/`fatal` y los recuperables **con acción** (por ejemplo «Reintentar» una impresión)
conservan el diseño completo con su fila de botones.

## Limitaciones de esta evidencia

No fue posible la navegación dentro del POS ni el inicio de sesión: la API apuntaba a un servidor
local que solo responde al chequeo de actualizaciones (el resto devuelve 404). La navegación y el
cierre están cubiertos además por pruebas de widget.

## Defecto corregido: `No Overlay widget found` de `LicensePurchaseOverlay`

`LicensePurchaseOverlay` vive en el `Stack` del `builder` de `MaterialApp`, por encima del
`Navigator`: no tiene `Overlay` ancestro. Su botón de cerrar declaraba `tooltip: 'Cerrar aviso'`, y
`Tooltip`/`RawTooltip` exige uno, así que **cada reconstrucción** lanzaba `No Overlay widget found`
(visible como el aviso genérico «No pudimos completar la operación»).

Corrección mínima: se elimina el `tooltip:` y la etiqueta pasa a `Icon.semanticLabel`, que no
necesita `Overlay`. El botón cierra igual (`dismissReason`), el aviso de licencia conserva su
contenido y el de WhatsApp su comportamiento. Cubierto por `test/core/debug/license_purchase_overlay_test.dart`,
que monta el overlay igual que producción (hermano del `Navigator`) y exige `takeException() == null`.
