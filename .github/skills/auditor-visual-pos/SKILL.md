---
name: auditor-visual-pos
description: 'Investiga interfaces reales con Playwright MCP (DOM, CSS computado, medidas, tipografía, color, sombras, espaciado, iconografía, animaciones y motion, navegación y menús, estados interactivos y responsive) y traduce los hallazgos a propuestas originales en Flutter para FullPOS Cloud, con informe en docs/design-research. Use when: auditoría visual, benchmarking visual o UX, research de diseño, inspección de páginas web, análisis de componentes UI, análisis de navegación, revisión de iconografía, revisión de animaciones y motion, propuesta de rediseño, mejoras de UX/UI, design research, UI/UX improvements, visual audit, responsive review, navigation review, motion review. NO usar para: modificar código de la app, backend, base de datos, facturación, inventario, caja o autenticación.'
argument-hint: 'Indica la URL o pantalla a investigar y el objetivo visual (ej.: "benchmark de tablas de productos en Linear")'
user-invocable: true
---

# Auditor Visual POS — investigación visual para FullPOS Cloud

## Propósito

Convertir observaciones **medidas** de interfaces reales (páginas públicas o autorizadas) en
**propuestas originales** de UX/UI para el cliente Flutter de FullPOS Cloud, sin tocar el código de
la aplicación durante la investigación.

Esta habilidad es de **investigación y documentación**, no de implementación.

## Cuándo usar

- Investigaciones de diseño, benchmarking visual o competitivo (UI/UX research).
- Inspección de una página pública para entender cómo resuelve un patrón (tablas, filtros, POS,
  dashboards, formularios, estados vacíos, navegación responsive).
- Necesidad de medidas reales antes de proponer un rediseño de componente.
- Comparar un flujo de FullPOS con referencias externas y detectar oportunidades de mejora.

## Cuándo NO usar

- Implementar el cambio visual (para eso se usa el flujo normal de Flutter + `docs/DESIGN_SYSTEM.md`,
  con autorización explícita).
- Depurar un bug funcional, de backend, de estado o de datos.
- Tocar facturación, inventario, caja, autenticación, base de datos, API o lógica de negocio.

## Límites duros (no negociables)

| Regla | Detalle |
| --- | --- |
| **Investigación ≠ implementación** | Esta habilidad **no modifica** archivos de `apps/fulltech_app`. Ningún cambio de código se hace hasta autorización expresa del usuario en el turno actual. |
| **Solo lectura en la web** | Navegar y medir. No enviar formularios con datos reales, no crear cuentas, no comprar, no publicar, no borrar. |
| **Solo páginas públicas o autorizadas** | Nada de zonas privadas de terceros. Nunca producción con datos de clientes. Nunca credenciales reales en sitios externos. |
| **Dominios excluidos** | Facturación, inventario, caja, autenticación, base de datos, API y lógica de negocio: fuera de alcance incluso como propuesta de cambio de comportamiento. |
| **Sin despliegues** | No deploy, no migraciones, no seeds, no release, no cambios de configuración del servidor. |
| **Sin dependencias nuevas** | Playwright MCP ya está disponible y configurado **globalmente** en `C:\Users\pc\.copilot\mcp-config.json` (servidor `my-mcp-server-913062e0`, salida en `%LOCALAPPDATA%\PlaywrightMCP\output`); el `.vscode/mcp.json` del proyecto está vacío. No ejecutar `npm install`, `playwright install`, `flutter pub add` ni equivalentes. |
| **Sin código propietario** | No copiar código, CSS, logos, iconografía, tipografías licenciadas ni identidad visual de terceros. |
| **Sin afirmaciones sin evidencia** | Toda medida es `HECHO` (extraída del navegador), `HIPÓTESIS` (inferencia) o `RECOMENDACIÓN` (propuesta). |
| **Secretos** | Nunca imprimir tokens, cookies, cabeceras `Authorization`, ni valores de `.env`. |

## Contexto real del proyecto (rutas verificadas)

Raíz Flutter: **`apps/fulltech_app`** (no confundir con `APPYRA_CRM`, `APPYRA_AI` ni
`finalesdaleventas/website`, que están en el mismo workspace multi-root).

Fuentes del sistema de diseño a consultar antes de proponer nada:

| Qué | Archivo |
| --- | --- |
| Reglas de UI y comandos | `docs/DESIGN_SYSTEM.md`, `.github/instructions/flutter.instructions.md` |
| Política del repositorio | `AGENTS.md` |
| Colores | `apps/fulltech_app/lib/core/theme/app_colors.dart` |
| Tema | `apps/fulltech_app/lib/core/theme/app_theme.dart` |
| Tipografía | `apps/fulltech_app/lib/core/design_system/typography/app_typography.dart` |
| Branding por rol | `apps/fulltech_app/lib/core/theme/role_branding.dart` |
| Iconos y tamaños | `apps/fulltech_app/lib/core/design_system/icons/` |
| Widgets compartidos | `apps/fulltech_app/lib/core/widgets/` |
| Código por dominio | `apps/fulltech_app/lib/features/`, `apps/fulltech_app/lib/modules/` |

Destino de informes: **`docs/design-research/`** (crear la carpeta si no existe).

## Procedimiento

### Fase 0 — Preflight (obligatorio)

1. Confirmar raíz y estado: `git rev-parse --show-toplevel`, `git branch --show-current`,
   `git status --short`. Si hay cambios ajenos sin explicar, **no escribir** y reportar.
2. Confirmar el alcance: URL(s) a investigar, objetivo, plataforma objetivo (web/Windows/Android/iOS)
   y tamaño de pantalla relevante.
3. Si la URL no es pública, pedir autorización explícita antes de abrirla.

### Fase 1 — Recolección con Playwright MCP

| Herramienta MCP | Uso |
| --- | --- |
| `browser_navigate` | Abrir la URL objetivo. Confirmar `Page URL` y `Page Title` reales. |
| `browser_snapshot` | Estructura de accesibilidad: jerarquía, roles, textos, orden de lectura. Base para nombrar componentes. |
| `browser_take_screenshot` | Evidencia visual (`fullPage: true` para página completa; `element` para un componente). |
| `browser_evaluate` | Medidas reales: `getBoundingClientRect`, `getComputedStyle`, tokens CSS, tipografía, sombras, radios, gaps, iconos, animaciones y navegación. |
| `browser_resize` | Comportamiento responsive (móvil, tablet, escritorio) y puntos de quiebre observados. |
| `browser_hover`, `browser_click`, `browser_type` | Estados interactivos: hover, focus, active, disabled, validación. |
| `browser_select_option` | Estados de `select`/combobox. |
| `browser_emulate_media` | `prefers-color-scheme` y `prefers-reduced-motion` cuando aplique. |
| `browser_console_messages` | Errores de consola relevantes (y distinguir los irrelevantes, p. ej. favicon 404). |
| `browser_network_requests` | Confirmar recursos, fuentes y hojas de estilo cargadas (solo lectura). |

Notas verificadas en este entorno:

- Las capturas se guardan **relativas a una carpeta del workspace multi-root**; tras capturar,
  localizar el archivo real con búsqueda por nombre antes de referenciarlo en el informe.
- Algunas herramientas (resize, hover, network, press_key) pueden requerir activar su categoría la
  primera vez; si una no está disponible, decirlo y usar la alternativa más cercana.
- Medir con el navegador **no** demuestra que un patrón funcione en Flutter; es evidencia de diseño.

### Fase 2 — Extracción de medidas

Ejecutar en `browser_evaluate` un bloque por componente y registrar los valores en el informe:

```js
// Medidas base de un componente: devuelve solo datos, nunca texto de negocio
() => {
  const el = document.querySelector('SELECTOR');
  if (!el) return { error: 'selector no encontrado' };
  const r = el.getBoundingClientRect();
  const s = getComputedStyle(el);
  return {
    box: { w: r.width, h: r.height, x: r.x, y: r.y },
    padding: s.padding,
    margin: s.margin,
    gap: s.gap,
    radius: s.borderRadius,
    border: `${s.borderWidth} ${s.borderStyle} ${s.borderColor}`,
    shadow: s.boxShadow,
    bg: s.backgroundColor,
    color: s.color,
    font: { family: s.fontFamily, size: s.fontSize, weight: s.fontWeight, lineHeight: s.lineHeight, letterSpacing: s.letterSpacing }
  };
}
```

Medir también, cuando exista: altura de fila de tabla, tamaño de touch target (≥ 44×44 recomendado),
contraste de texto frente a fondo, y comportamiento en 360/768/1280/1920 px de ancho.

#### Dimensiones obligatorias

Ninguna dimensión se declara «revisada» sin al menos una medida real (`HECHO`):

| Dimensión | Qué se registra |
| --- | --- |
| Medidas y layout | `width`, `height`, `x`, `y`, relación de aspecto, posición fija/sticky |
| Tipografía | familia, tamaño, peso, `line-height`, `letter-spacing` y cuántos niveles se usan |
| Espaciado | `padding`, `margin`, `gap`, ritmo vertical entre bloques, densidad de fila |
| Color y contraste | `background`, `color`, `border-color` y ratio de contraste calculado |
| Sombras, radios y bordes | `box-shadow`, `border-radius`, `border` |
| Iconografía | tamaño del glifo, grosor de trazo, color y `opacity`, alineación con el texto, `gap` icono-texto, tamaño del botón con icono |
| Animaciones y motion | `transition-property/duration/delay/timing-function`, `animation-name/duration`, propiedades animadas, respuesta a `prefers-reduced-motion` |
| Navegación | niveles, elemento activo, breadcrumb, cabecera fija, patrón móvil (drawer / bottom navigation), profundidad y retorno |
| Responsive | puntos de quiebre observados y qué se reordena, oculta o colapsa en 360 / 768 / 1280 / 1920 |

Bloques auxiliares de medición:

```js
// Iconos y botones con icono
() => {
  const el = document.querySelector('SELECTOR');
  if (!el) return { error: 'selector no encontrado' };
  const svg = el.matches('svg') ? el : el.querySelector('svg');
  const target = svg ?? el;
  const r = target.getBoundingClientRect();
  const s = getComputedStyle(target);
  return {
    box: { w: r.width, h: r.height },
    strokeWidth: s.strokeWidth,
    color: s.color,
    opacity: s.opacity,
    iconButtonBox: el.getBoundingClientRect().width,
    gapToLabel: s.gap
  };
}
```

```js
// Animaciones y motion
() => {
  const el = document.querySelector('SELECTOR');
  if (!el) return { error: 'selector no encontrado' };
  const s = getComputedStyle(el);
  return {
    transition: `${s.transitionProperty} ${s.transitionDuration} ${s.transitionTimingFunction} ${s.transitionDelay}`,
    animation: s.animationName === 'none' ? null : `${s.animationName} ${s.animationDuration} ${s.animationIterationCount}`,
    transform: s.transform,
    reducedMotion: window.matchMedia('(prefers-reduced-motion: reduce)').matches
  };
}
```

```js
// Navegación: estructura, estado activo y patrón en móvil
() => {
  const nav = document.querySelector('SELECTOR_NAV');
  if (!nav) return { error: 'selector de navegación no encontrado' };
  const items = [...nav.querySelectorAll('a, button, [role="menuitem"]')];
  const s = getComputedStyle(nav);
  return {
    items: items.map(i => ({
      label: i.textContent.trim().slice(0, 40),
      active: i.getAttribute('aria-current') ?? i.getAttribute('aria-selected'),
      box: i.getBoundingClientRect().height
    })),
    orientation: s.flexDirection,
    position: s.position,
    visible: s.display !== 'none' && s.visibility !== 'hidden'
  };
}
```

Para motion, repetir la medición con `browser_emulate_media` (`reducedMotion: 'reduce'`): si la
animación no se atenúa, se registra como hallazgo de accesibilidad.

### Fase 3 — Comparación con FullPOS Cloud

1. Leer `docs/DESIGN_SYSTEM.md` y los tokens reales (`app_colors.dart`, `app_typography.dart`,
   `app_theme.dart`).
2. Identificar el widget compartido más cercano en `lib/core/widgets/` o el módulo afectado.
3. Mapear hallazgo externo → equivalente FullPOS, indicando:
   - lo que **ya existe** y no hay que tocar,
   - lo que **se puede mejorar** con tokens existentes,
   - lo que requeriría un **token o widget nuevo** (propuesta, no implementación).
4. Toda propuesta debe ser **original**: describir la intención y el comportamiento, nunca trasladar
   valores arbitrarios de la referencia ni su identidad visual.

### Fase 4 — Informe en `docs/design-research/`

Crear el archivo con esta convención:

```
docs/design-research/YYYY-MM-DD-<tema>-<fuente>.md
```

Estructura obligatoria del informe:

```markdown
# <Tema> — investigación visual

## 1. Objetivo y alcance
## 2. Fuentes y fecha de observación
| URL | Título real | Fecha | Autorización |
## 3. Evidencia
- Capturas: rutas reales de los archivos generados
- Snapshot: hallazgos del árbol de accesibilidad
- Consola: errores observados (y su impacto)
## 4. Medidas verificadas (HECHO)
Cubrir las dimensiones obligatorias que apliquen: layout, tipografía, espaciado, color y contraste,
sombras/radios, iconografía, animaciones/motion, navegación y responsive.
| Elemento | Dimensión | Propiedad | Valor | Cómo se midió |
## 5. Observaciones de UX/UI
## 6. Comparación con el sistema de diseño FullPOS
| Referencia (observado) | Equivalente en FullPOS | Estado (existe / mejora / propuesta) |
## 7. Propuesta original en Flutter (RECOMENDACIÓN)
- Widgets y tokens involucrados
- Comportamiento responsive propuesto
- Estados: loading, vacío, error, hover/focus, disabled
## 8. Limitaciones
- Qué no se pudo medir y por qué
## 9. Archivos Flutter relevantes
| Ruta | Qué se revisó |
## 10. Próximos pasos (requieren autorización explícita)
```

### Fase 5 — Cierre

- Reportar: fuentes, capturas, medidas, propuestas, limitaciones y archivos Flutter relevantes.
- **Detenerse.** No implementar nada, ni siquiera "un ajuste pequeño", sin autorización explícita.
- Si el usuario pide implementar, salir de esta habilidad y seguir el flujo normal del repositorio
  (`AGENTS.md`, `docs/DESIGN_SYSTEM.md`, validación con `flutter analyze` / `flutter test`).

## Reglas de originalidad

- Prohibido copiar logos, marcas, iconos, ilustraciones, tipografías licenciadas, textos de producto
  ni fragmentos de CSS/HTML de la referencia.
- Se copian **conceptos** (jerarquía, densidad, patrón de interacción) y se expresan con tokens y
  widgets propios de FullPOS.
- En el informe, describir el patrón con lenguaje neutro; nunca sugerir "igual que <marca>".

## Etiquetado obligatorio

| Etiqueta | Significado |
| --- | --- |
| `HECHO` | Extraído de código real, navegador, archivo o comando ejecutado en este turno. |
| `HIPÓTESIS` | Interpretación plausible, no verificada. |
| `RECOMENDACIÓN` | Propuesta de diseño o implementación. |

## Anti-patrones

- Presentar una captura como "medida" sin haber ejecutado `browser_evaluate`.
- Proponer valores mágicos (`16px`, `#FF0000`) sin mapearlos a `AppColors` / `AppTypography`.
- Convertir la investigación en un rediseño silencioso del design system.
- Editar widgets "para probar" durante la investigación.
- Declarar que una referencia funciona en Flutter sin haberlo comprobado.
- Usar la habilidad como excusa para tocar facturación, inventario, caja o autenticación.

## Verificación de la propia habilidad

- `name` debe coincidir exactamente con el nombre de la carpeta: `auditor-visual-pos`.
- Frontmatter YAML delimitado por `---`, sin tabulaciones.
- `description` con palabras clave de activación (español e inglés) y límite de 1024 caracteres.
- Ubicación de descubrimiento: `.github/skills/auditor-visual-pos/SKILL.md` (raíz del repositorio).
- Invocación manual: `/auditor-visual-pos` en el chat.
- Invocación automática: por coincidencia semántica con la `description`.
- Comprobación de detección: la habilidad debe aparecer en la lista de skills de la sesión y en el
  selector de `/`; si no aparece, revisar primero que el archivo esté bajo `.github/skills/` de la
  raíz correcta y que `name` coincida con la carpeta.
