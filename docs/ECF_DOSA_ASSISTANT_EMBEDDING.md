# Asistente DOSA — cómo embeberlo en cada plataforma

Estado: **adaptador listo y apagado**. Con la bandera por defecto (`false`) no se
pinta nada y la pantalla actual no cambia.

DOSA entregó `dosa-cert.js` y el componente `<dosa-cert-wizard>`. De ese
componente **no** están documentados sus atributos, así que el adaptador deja el
mapa vacío y el montaje bloqueado (ver `DosaAssistantBlockReason`).

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

| # | Requisito | De quién |
| --- | --- | --- |
| 1 | Nombres y tipos de los atributos de `<dosa-cert-wizard>` | DOSA |
| 2 | Clave **de PRUEBA** (`pk_test_`), no la `pk_live_` | DOSA |
| 3 | URL oficial del script y autorización de nuestro origen | DOSA |
| 4 | Eventos que emite el componente y su contrato | DOSA |
| 5 | Contrato de vinculación RNC ↔ empresa (evitar duplicados) | DOSA |
| 6 | Autorización para añadir `webview_flutter` / `webview_windows` | Decisión interna |
