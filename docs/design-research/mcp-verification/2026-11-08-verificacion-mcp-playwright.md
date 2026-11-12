# Verificación MCP — Playwright (independiente) y Playwright Chrome (`--extension`)

**Fecha:** 2026-11-08 (segunda verificación, tras la del mismo día)
**Tipo de tarea:** diagnóstico exclusivo. **No se modificó ninguna configuración MCP, ni código de la app,
ni la habilidad `auditor-visual-pos`.**
**Proyecto:** DaleVentas POS / FullPOS Cloud — `apps/fulltech_app`.

Etiquetas: `HECHO` (verificado en este turno) · `HIPÓTESIS` (inferencia no verificada) · `RECOMENDACIÓN`.

---

## 1. Configuraciones MCP encontradas (HECHO)

| Archivo | Modificado | Servidores | ¿Afecta a este chat de VS Code? |
| --- | --- | --- | --- |
| `c:\Users\pc\.copilot\mcp-config.json` | 2026-11-08 12:49:51 | `my-mcp-server-913062e0` → `npx -y @playwright/mcp@latest`<br>`my-mcp-server-debba442` → `npx -y @playwright/mcp@latest --extension` | **No** (es la configuración de Copilot CLI) |
| `.vscode/mcp.json` (workspace) | 2026-11-05 08:55:16 | `microsoft/playwright-mcp` → `@playwright/mcp@latest` | **Sí** |
| `%APPDATA%\Code\User\mcp.json` | 2026-09-15 10:02:31 | `microsoft/playwright-mcp` + `figma` (HTTP) | **Sí** |

Conclusiones:

1. **No existe ningún servidor llamado `playwright` ni `playwright-chrome`.** El nombre real en VS Code es
   `microsoft/playwright-mcp`; en CLI son nombres autogenerados.
2. En VS Code hay **un solo** servidor Playwright y **sin** `--extension`.
3. El archivo de configuración **no cambió** entre la primera verificación y esta (fechas de modificación
   idénticas), por lo que el estado funcional es el mismo.

---

## 2. Estado de conexión del servidor independiente

| Dato | Valor | Etiqueta |
| --- | --- | --- |
| Procesos del servidor | **2 instancias** de `@playwright/mcp\cli.js`: PID 39932 (2026-11-07 21:38, huérfana) y PID 39956 (2026-11-08 12:55, activa) | `HECHO` |
| Chrome del servidor | 8 procesos con `--user-data-dir=C:\Users\pc\AppData\Local\ms-playwright-mcp\mcp-chrome-b1b4e46`, `--remote-debugging-pipe` | `HECHO` |
| Página actual | `about:blank` (instancia reiniciada a las 12:55) | `HECHO` |
| Entorno del navegador | Chrome/156.0.0.0, viewport 1920×889, pantalla 1920×1080, `navigator.webdriver = false`, `chrome.runtime` no disponible | `HECHO` |
| Herramientas ejecutadas en este turno | `browser_evaluate` (2 veces) y `browser_console_messages` → respondieron con datos reales | `HECHO` |
| Herramientas **deshabilitadas por el usuario** | `browser_navigate`, `browser_snapshot`, `browser_tabs`, `browser_take_screenshot` → error `Tool … is currently disabled by the user` | `HECHO` |

**Consecuencia:** la conexión está **viva y es real** (ejecuta JavaScript y lee la consola del Chrome
aislado), pero **no se puede repetir el ciclo completo** de la primera verificación (navegar → snapshot →
captura) porque esas cuatro herramientas están desactivadas. **No se intentó eludir el bloqueo** (por
ejemplo navegando desde `browser_evaluate`): una herramienta deshabilitada se respeta.

---

## 3. Estado del servidor Chrome (`--extension`)

| Dato | Valor | Etiqueta |
| --- | --- | --- |
| Servidor en VS Code | **No configurado** | `HECHO` |
| Procesos con `--extension` | **Ninguno** (las 2 instancias activas son sin bandera) | `HECHO` |
| Extensión en Chrome | «Playwright Extension» **v0.5.0**, perfil `Profile 1`, id `mmlmfjhmonkocbjadbfplnigmagldckm` | `HECHO` |
| Host de mensajería nativa de Playwright | **No registrado** en `HKCU\Software\Google\Chrome\NativeMessagingHosts` (solo `com.microsoft.browsercore`, `com.notion.meeting_notes`, `com.openai.codexextension`) | `HECHO` |
| Chrome del usuario | en ejecución (~59 procesos sin perfil aislado) | `HECHO` |

`HIPÓTESIS`: si la versión instalada de la extensión depende de mensajería nativa, faltaría ese registro;
si usa el canal WebSocket local (habitual en versiones recientes), el registro no es necesario. No se puede
determinar sin arrancar el servidor con `--extension`, lo que requiere autorización.

**Resultado:** **no verificable** en esta sesión. No se declara funcional.

---

## 4. Configuración propuesta (NO aplicada — requiere autorización)

```jsonc
// .vscode/mcp.json — añadir la segunda entrada; NO tocar la existente
"playwright-chrome": {
  "type": "stdio",
  "command": "npx",
  "args": ["@playwright/mcp@latest", "--extension"]
}
```

Pasos posteriores: guardar → VS Code reinicia el servidor → abrir Chrome con `Profile 1` → icono de la
extensión → **«Share this tab»** → usar solo esa pestaña.

Alternativa (no toca el repositorio): añadirlo en `%APPDATA%\Code\User\mcp.json`.

---

## 5. Hallazgos de higiene operativa (HECHO)

1. **Instancia huérfana**: el servidor PID 39932 sigue vivo desde el 2026-11-07 21:38 y su Chrome fue
   cerrado en la verificación anterior. No se ha terminado (podría pertenecer a otra ventana de VS Code).
   `RECOMENDACIÓN`: cerrarla manualmente para evitar bloqueos futuros del perfil `ms-playwright-mcp`.
2. **Doble instancia = doble consumo** de memoria (~un Chrome por instancia si ambas arrancan navegador).
3. `Browser is already in use` (visto en la primera verificación) proviene del perfil compartido
   `ms-playwright-mcp`; se resuelve cerrando la instancia que lo retiene. Nunca cerrar el Chrome del usuario.

---

## 6. Habilidad `auditor-visual-pos`

Existe en `.github/skills/auditor-visual-pos/SKILL.md`. **No requiere cambios para seguir funcionando.**
Menciona Playwright en singular y su límite es «solo páginas públicas o autorizadas», lo que ya cubre el
uso futuro de `playwright-chrome` si se documenta así:

- `playwright` (independiente) → páginas públicas, documentación y demos.
- `playwright-chrome` (`--extension`) → **solo pestañas compartidas expresamente en el turno**, revocando
  el compartido al terminar y sin leer cookies, tokens, almacenamiento ni datos bancarios.

`RECOMENDACIÓN`: añadir 3 líneas a la habilidad cuando el segundo servidor esté operativo (no ahora).

---

## 7. Respuestas directas

1. **¿Funciona Playwright independiente?** Sí: conexión viva y verificada con `browser_evaluate` y
   `browser_console_messages`. La prueba visual completa está bloqueada por 4 herramientas deshabilitadas.
2. **¿Funciona Playwright Chrome?** No verificable: no existe el servidor en VS Code ni hay proceso
   `--extension`.
3. **¿Puedo compartir una pestaña autenticada?** La extensión está instalada (v0.5.0, `Profile 1`), así que
   es viable una vez registrado el servidor y compartida la pestaña.
4. **¿Puede Copilot inspeccionar una interfaz interna autorizada?** Hoy no desde este chat; sí tras los dos
   pasos del punto 4.
5. **¿Qué falta?** (a) habilitar `browser_navigate`, `browser_snapshot`, `browser_take_screenshot` y
   `browser_tabs` en el selector de herramientas del chat; (b) autorizar la entrada `playwright-chrome`.

---

## 8. Evidencia previa reutilizable (primera verificación, mismo día)

- `docs/design-research/mcp-verification/2026-11-08-playwright-standalone-todomvc.png` (27 227 bytes):
  TodoMVC cargado con el servidor independiente, snapshot con `heading "todos"` y `textbox "What needs to be
  done?" [active]`, y CSS computado del `h1` (100 px / 100 / «Helvetica Neue», `rgba(175,47,47,0.15)`).
---

## 9. Configuración aplicada (autorizada por el usuario)

Se añadió el servidor `playwright-chrome` en la **configuración global de VS Code**
(`%APPDATA%\Code\User\mcp.json`), sin modificar `microsoft/playwright-mcp` ni `figma`:

```jsonc
"playwright-chrome": {
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "@playwright/mcp@latest", "--extension"]
}
```

| Verificación | Resultado | Etiqueta |
| --- | --- | --- |
| JSON válido (`ConvertFrom-Json`) | **VÁLIDO** | `HECHO` |
| Servidores tras el cambio | `microsoft/playwright-mcp`, `playwright-chrome`, `figma` | `HECHO` |
| `--extension` soportado por la versión instalada | Sí: «Connect to a running browser instance (Edge/Chrome only). Requires the "Playwright Extension" to be installed.» | `HECHO` (`npx @playwright/mcp@latest --help`) |
| Opción adicional disponible | `--profile-dir-name <name>` (p. ej. `"Profile 1"`); por defecto usa el último perfil con la extensión | `HECHO` |
| Servidor arrancado por VS Code | **Todavía no**: no existe proceso `cli.js` con `--extension` (los 2 activos son sin bandera) | `HECHO` |
| Extensión instalada | Carpeta + `manifest.json` «Playwright Extension» 0.5.0 en `Profile 1` | `HECHO` |
| Extensión habilitada | No verificable: Chrome guarda ese estado en `Secure Preferences` (cifrado/HMAC), no en `Preferences` | `HIPÓTESIS` (probablemente habilitada) |

**Pendiente para operar** (requiere acción del usuario, no automatizable por el agente):

1. **Recargar la ventana de VS Code** (`Developer: Reload Window`) o reiniciar el servidor MCP para que se
   registren las herramientas `playwright-chrome`.
2. Abrir la pestaña de **Alegra POS** en Chrome `Profile 1`, pulsar el icono de la extensión →
   **«Share this tab»**, y autorizar explícitamente la inspección.
3. Habilitar, si aparecen desactivadas, las herramientas: `browser_navigate`, `browser_snapshot`,
   `browser_take_screenshot`, `browser_evaluate`, `browser_tabs`.

`RECOMENDACIÓN`: si el servidor conecta al perfil equivocado, añadir `"--profile-dir-name", "Profile 1"` a
los argumentos. No se añadió para respetar la especificación exacta solicitada.
