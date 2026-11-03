# Asistente DOSA — cómo embeberlo en cada plataforma

Estado: **adaptador implementado y apagado por bandera**. Con
`DOSA_ASSISTANT_ENABLED=false` (valor por defecto) la pantalla actual no cambia.

---

## 0. Corrección de la Fase 3 (evidencia verificada)

En la Fase 3 se concluyó que «DOSA no documentó los atributos» y que había que
exigir una clave `pk_test_`. **Las dos conclusiones eran incorrectas.**

Evidencia: el script oficial
`https://dosasystem.com/static/embed/dosa-cert.js` (7.330 bytes, descargado y
leído) declara en su propio código:

```js
static get observedAttributes() {
  return ['session-url', 'publishable-key', 'base-url', 'theme', 'height'];
}

const ALLOWED_EVENTS = new Set([
  'cert:ready', 'cert:step', 'cert:postulacion', 'cert:attention',
  'cert:complete', 'cert:error', 'cert:resize', 'cert:asistida_pago',
  'cert:asistida_pagada',
]);
```

Correcciones aplicadas:

| Antes (Fase 3) | Ahora |
| --- | --- |
| `componentAttributes` vacío | Los 5 atributos que el componente observa |
| Eventos: no modelados | Los 10 de `ALLOWED_EVENTS` + `cert:blocked` (emitido por el propio componente) |
| Bloqueo por `pk_test_` | **Eliminado**: el script solo documenta `publishable-key="pk_..."`, sin prefijos de entorno |
| Montaje imposible | Montaje real en Web/PWA y apertura externa en nativo |

Sobre las claves, el script es explícito:

* `publishable-key` es **pública** por diseño: viaja en la URL
  (`.../embed/certificacion/wizard?pk=...`).
* La **secret key** es del servidor: se usa para crear el enlace de sesión con
  `POST /api/certificacion/sesiones`. Nunca entra en el cliente.
* La forma recomendada es `session-url` (enlace de sesión), no la clave.

---

## 1. Capacidad real del proyecto (verificada)

| Necesidad | Qué hay hoy |
| --- | --- |
| WebView nativo | **No hay**. `pubspec.yaml` no incluye `webview_flutter` ni `flutter_inappwebview` |
| DOM en Flutter Web | `web: ^1.1.1` (package:web) y `js: ^0.6.7` disponibles |
| Abrir URL externa | `url_launcher: ^6.3.0` disponible |
| Views de plataforma | No se usa `platformViewRegistry` en ningún punto del código |

Consecuencia: **hoy solo Web/PWA puede contener el componente sin añadir
dependencias.** Windows, Android e iOS requieren una dependencia nueva y
configuración de plataforma, que es una decisión aparte.

---

## 2. Web / PWA (prioridad del producto)

El PWA es Flutter Web servido por el contenedor nginx `daleventapos_pwa`.

**Opción A — componente en la propia página (recomendada a medio plazo)**

```dart
// Solo web: compilado con dart:ui_web
ui_web.platformViewRegistry.registerViewFactory('dosa-cert-wizard', (int id) {
  final element = html.DivElement()..id = 'dosa-cert-wizard';
  // atributos SOLO cuando DOSA los documente (hoy: ninguno)
  return element;
});
// y en el árbol: HtmlElementView(viewType: 'dosa-cert-wizard')
```

Requisitos y límites:
- Sin dependencias nuevas.
- El script `dosa-cert.js` debe cargarse **una sola vez** y desde el origen
  oficial de DOSA; no se puede autoalojar sin su permiso.
- En Flutter Web los eventos de teclado/scroll dentro de un `HtmlElementView`
  se comportan distinto según el renderer; hay que probarlo de verdad.
- Requiere que DOSA autorice nuestro origen (CSP / allow-list de dominios).

**Opción B — WebView (con dependencia)**

`flutter_inappwebview` daría un comportamiento homogéneo con Android/iOS, a
cambio de una dependencia pesada y de configuración de plataforma.

**Opción C — abrir en pestaña nueva (coste cero, disponible hoy)**

`url_launcher` abre la URL del asistente en el navegador. No hay integración
visual, pero permite el flujo completo sin tocar dependencias ni la app.

---

## 3. Windows

No existe soporte de views DOM en Flutter Windows. Las vías son:

1. `webview_windows` (WebView2) — **dependencia nueva**; WebView2 está presente
   en Windows 10/11 actualizados, pero hay que declararlo y probarlo en el build
   de release.
2. `url_launcher` a la URL del asistente (navegador del sistema). Coste cero.

El instalador oficial se genera con `scripts/release/build_windows_release.ps1`
e Inno Setup; añadir un WebView obliga a revisar ese camino y el runtime de
WebView2.

---

## 4. Android

1. `webview_flutter_android` — **dependencia nueva** (`webview_flutter`).
2. `url_launcher` (Custom Tabs / navegador).

Consideración fiscal: el asistente gestiona identidad tributaria; en Android
conviene bloquear capturas si DOSA lo requiere y no registrar WebView con
`setWebContentsDebuggingEnabled`.

---

## 5. iOS / iPhone

1. `webview_flutter_wkwebview` — **dependencia nueva** (WKWebView).
2. `url_launcher` (Safari).

Consideración: la app se distribuye por TestFlight/App Store vía Codemagic
(`codemagic.yaml`). WKWebView está permitido, pero conviene revisar la política de
datos del flujo antes de publicar.

---

## 6. Recomendación

1. **Ahora**: `DosaAssistantPanel` con `mountBuilder` nulo →
   la UI muestra el estado real (bloqueado / pendiente de contenedor) sin fingir.
2. **Cuando DOSA documente atributos y dé clave de PRUEBA**: implementar
   **Opción A** en Web/PWA (sin dependencias) y **Opción C** en Windows, Android
   e iOS para no bloquear el flujo.
3. **Solo si el producto exige integración nativa**: autorizar
   `webview_flutter` (Android/iOS) y `webview_windows`, con su impacto en el
   build de release.

---

## 7. Seguridad del montaje

- La clave publicable es pública por diseño, pero **se entrega por configuración
  en tiempo de ejecución**, no se escribe en el código ni en assets.
- `DosaAssistantConfig.hasProductionKey` detecta el prefijo `pk_live_` y bloquea
  el montaje: la clave recibida es de producción y no se usa hasta tener una
  configuración de prueba autorizada.
- La URL del script debe ser fija y del origen oficial. **Nunca** una URL que
  venga del usuario, de la empresa o del cuerpo de un evento.
- El panel no inicia sesión ni postulación por sí mismo: solo pinta estado y, si
  el contrato estuviera completo, el hueco donde montar.
- "Finalizado por el proveedor" no se presenta nunca como autorización fiscal
  (`DosaAssistantSession.impliesFiscalAuthorization` es siempre `false`).

---

## 8. Lo que falta para activarlo

| # | Requisito | De quién | Estado |
| --- | --- | --- | --- |
| 1 | Atributos del componente | — | **RESUELTO** (los declara el script) |
| 2 | Clave publicable | — | **RECIBIDA** (es pública; no requiere prefijo de entorno) |
| 3 | Enlace de sesión emitido por el servidor | Contrato de `POST /api/certificacion/sesiones` | **PENDIENTE** |
| 4 | Registrar el dominio en «Dominios permitidos para iframe» | Configuración de DOSA | **PENDIENTE** |
| 5 | Contrato de eventos (payload) | DOSA | Documentado en el script a nivel de nombres; el detalle de `payload` se lee de forma defensiva |
| 6 | WebView nativo | Decisión interna | **NO necesario** en esta fase: se usa navegador externo |

## 9. Cómo queda el montaje

### Web/PWA

`dosa_wizard_view_web.dart` (importado de forma condicional) registra una vista de
plataforma, inyecta el script **una sola vez** desde el origen oficial, crea
`<dosa-cert-wizard>`, aplica solo los 5 atributos observados y reenvía los
eventos de la lista blanca.

### Windows, Android e iOS

`dosa_wizard_view_stub.dart` no monta nada. El panel ofrece
«Abrir asistente», que llama a `openDosaAssistantExternally`: valida que la URL
sea `https` y del origen oficial **antes** de abrir el navegador del sistema. Al
volver, el progreso se recupera del backend.

### Eventos: lo que pueden y no pueden hacer

`mayMutateFiscalState()` devuelve `false` para **todos** los eventos. En el
backend, `recordEventHint()` solo escribe `last_event_type` y `last_event_at`
(un `UPDATE` que ni siquiera menciona `status`). `provider_confirmed_at` solo lo
escribe `applyProviderConfirmation()`, pensado para el backend tras reconciliar.

`cert:complete` significa «el asistente terminó», **nunca** «la DGII aprobó».
