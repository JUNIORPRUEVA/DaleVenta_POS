# Auditoría visual de referencia (Material Design 3) — validación de la habilidad `auditor-visual-pos`

> Investigación de solo lectura. No se modificó ninguna interfaz de FullPOS ni código de la app.

## 1. Objetivo y alcance

Validar la habilidad `auditor-visual-pos` ejecutando una auditoría **real y medida** sobre una página
pública autorizada, y traducir los hallazgos a propuestas aplicables a FullPOS Cloud.

Alcance: una sola página pública, dos temas (claro/oscuro), dos anchos (360 y 1280 px). Excluido:
zonas autenticadas, formularios con datos reales, facturación, inventario, caja.

## 2. Fuentes y fecha de observación

| URL | Título real | Fecha | Autorización |
| --- | --- | --- | --- |
| https://m3.material.io/ | `Material Design 3 - Google's latest open source design system` | 2026-11-08 | Página pública; sin cuenta ni datos personales |

Herramienta: navegador integrado de VS Code controlado con la API de **Playwright**
(`page.goto`, `page.evaluate`, `setViewportSize`, `emulateMedia`, `screenshot`).

> Desviación registrada: las herramientas del **Playwright MCP global** (`my-mcp-server-913062e0`)
> estaban **deshabilitadas en esta sesión**, por lo que no se usaron los nombres de herramienta
> `browser_*` que cita la habilidad. Las mediciones son igualmente reales (mismo motor Playwright).
> Para seguir la habilidad al pie de la letra hay que reactivar esas herramientas en la vista MCP.

## 3. Evidencia

- Capturas: `C:\Users\pc\AppData\Local\Temp\visual-audit-m3\1280-home.png` (42,6 KB) y
  `...\360-home.png` (56,6 KB). Carpeta temporal, no versionada.
- Snapshot de accesibilidad: `navigation "Main"`, `main "Main Content"`, `tabpanel`, `region` por
  sección y botones "Copy link" por bloque.
- Consola: 2 errores, ambos idénticos: directiva CSP con nombre inválido
  (`feedback-pa.clients6.google.com`). No impiden la carga ni la interacción.

## 4. Medidas verificadas (HECHO)

### 4.1 Tipografía

| Elemento | Propiedad | Valor | Cómo se midió |
| --- | --- | --- | --- |
| `h1` | font-size | **88 px** (escritorio) / **45 px** (360 px) | `getComputedStyle` a 1280 y 360 |
| `h1` | line-height / weight | 96 px / **475** | `getComputedStyle` |
| `h2` | font-size / line-height | 45 px / 52 px (escritorio); 36 px (360) | `getComputedStyle` |
| Cuerpo | font-size / line-height | 16 px / 24 px | `getComputedStyle` |
| Cuerpo secundario | font-size | 14 px (a 360) | `getComputedStyle` |
| Escala total | tamaños distintos | **10** (12, 13.33, 14, 16, 20, 22, 24, 40, 45, 88 px) | recuento sobre h1–h4, p, a, button, span, li |

### 4.2 Color y contraste (fondo efectivo resuelto subiendo por el DOM)

| Estado | Elemento | Color texto | Fondo efectivo | Ratio |
| --- | --- | --- | --- | --- |
| Oscuro | `h1` | `rgb(230,225,227)` | `rgb(28,27,29)` | **13.27:1** |
| Oscuro | `h2` | `rgb(230,225,227)` | `rgb(20,19,20)` | **14.34:1** |
| Oscuro | párrafo | `rgb(203,196,204)` | `rgb(28,27,29)` | **10.06:1** |
| Oscuro | botón primario | `rgb(26,0,86)` | `rgb(159,134,255)` | **6.22:1** |
| Oscuro | enlace | `rgb(159,134,255)` | `rgb(20,19,20)` | **6.47:1** |
| Claro | `h1` | `rgb(28,27,29)` | `rgb(248,241,246)` | **15.45:1** |
| Claro | `h2` | `rgb(28,27,29)` | `rgb(254,251,255)` | **16.71:1** |
| Claro | párrafo | `rgb(77,66,86)` | `rgb(248,241,246)` | **8.48:1** |
| Claro | botón primario | `rgb(255,255,255)` | `rgb(100,66,214)` | **6.38:1** |
| Claro | enlace | `rgb(100,66,214)` | `rgb(254,251,255)` | **6.21:1** |

### 4.3 Forma, densidad y objetivos táctiles

| Elemento | Medida | Valor |
| --- | --- | --- |
| Botón CTA | caja / radio / padding | 224×80 px / **48 px** / `0 48px` |
| Botón CTA | tipografía | 24 px, peso 475 |
| Icon-button de barra | caja | **48×48 px** |
| Barra superior (360 px) | alto | **64 px**, `position: static` |
| Ítem de navegación lateral (1280) | caja | **80×60 px** |
| Elementos `<a>` / `<button>` | recuento | 50 / 2 |

### 4.4 Navegación

- Landmark `navigation "Main"` con 8 destinos: Search, Home, Get started, Develop, Foundations,
  Styles, Components, Blog (4 enlaces + 4 botones desplegables).
- En **360 px**: barra superior con "open menu" y "search" (48×48) + `mwc-drawer`.
- En **1280 px**: la barra superior desaparece (`[role="banner"]` no encontrado) y la navegación
  pasa a un **riel lateral persistente** en x≈4, con contenido desde x=88.
- Enlace "skip to main content" fijo, de 2×2 px, visible solo al enfocar (patrón *skip-link*).

### 4.5 Responsive

| Ancho | `h1` | Contenido principal | Overflow horizontal |
| --- | --- | --- | --- |
| 360 px | 45 px | x=40, w=265 | **ninguno** (`scrollWidth` = `innerWidth`) |
| 1280 px | 88 px | x=152, w=959 | **ninguno** |

### 4.6 Animaciones y motion

| Aspecto | Valor medido |
| --- | --- |
| Elementos con transición (1280) | **23** |
| Duraciones típicas | **0.2 s** y **0.3 s** (0.5 s en ítems de navegación) |
| Curva | `cubic-bezier(0.2, 0, 0, 1)`; `transform` con `linear` |
| Con `prefers-reduced-motion: reduce` | duraciones **sin atenuar** (siguen 0.5 s) |
| Control manual | interruptor accesible `"Pause animations"` (`aria-checked=true`) |

## 5. Observaciones de UX/UI

1. **Jerarquía por escala, no por color**: el peso tipográfico se mantiene en 475 y la jerarquía se
   construye con tamaño (88/45/36/16) y contraste, no con negritas.
2. **Objetivos táctiles holgados**: 48×48 en iconos y 80 px de alto en CTA; por encima del mínimo de
   44 px recomendado.
3. **Radio muy alto en CTA (48 px = píldora completa)**: refuerza la acción principal pero reduce
   densidad; en pantallas operativas con muchas acciones puede competir visualmente.
4. **Navegación adaptativa real**: barra superior en móvil, riel lateral persistente en escritorio.
   No hay menú hamburguesa redundante en escritorio.
5. **Motion no respeta `prefers-reduced-motion` por CSS**; se resuelve con un interruptor manual.
   Es una decisión deliberada, pero obliga al usuario a encontrarla.
6. **Escala de 10 tamaños**: riqueza expresiva alta; coste de disciplina alto para un equipo pequeño.
7. **Contraste muy por encima de AA** en texto (8.48–16.71) y suficiente en acciones (6.2–6.4).

## 6. Comparación con el sistema de diseño FullPOS

Tokens verificados en este turno: `app_typography.dart` (Manrope; display 34, headline 28, title 22,
body 15/14, label 14/12) y `app_colors.dart`.

| Referencia (observado) | Equivalente en FullPOS | Estado |
| --- | --- | --- |
| `h1` 88 px en escritorio | `displayLarge` 34 px | **propuesta**: escalar títulos en desktop con un token nuevo, no reutilizar 34 px |
| `h1` 45 px en móvil | `headlineLarge` 28 px | **mejora**: 28 px es conservador para portada; evaluar 32–36 solo en home |
| Peso único 475 | Manrope w400/w500/w600 | **existe**: FullPOS ya tiene jerarquía por peso |
| 10 tamaños distintos | 10 niveles definidos en `AppTypography` | **existe** (misma complejidad; no ampliar) |
| Objetivos 48×48 | botones Material con altura ≥48 | **existe** |
| Radio 48 px (píldora) | radios del tema | **propuesta**: reservar píldora para la acción principal |
| Nav: barra móvil + riel escritorio | navegación por rol | **propuesta**: riel persistente en escritorio |
| Contraste texto 8.5–16.7 | `textPrimary`/`surface` **16.13**; `textSecondary` **5.91** | **existe** en primario |
| Contraste secundario alto | `textMuted`/`surface` **4.76** | **mejora**: 4.76 pasa AA por poco; subir a `textSecondary` en textos pequeños |
| Acción primaria 6.2–6.4 | blanco/`primary` **5.92** | **existe** (AA) |
| Error legible | `error`/`surface` **4.83** | **existe** (AA justo) |

## 7. Propuesta original en Flutter (RECOMENDACIÓN)

- **Escala tipográfica responsiva**: mantener `AppTypography` intacto y añadir un factor por
  breakpoint solo para títulos de portada (`displayLarge` 34 → 40/44 en ≥1200 px). No copiar 88 px:
  es una portada editorial, no una pantalla operativa.
- **Contraste de texto secundario**: usar `textSecondary` (5.91) para cuerpo ≤14 px y reservar
  `textMuted` (4.76) para metadatos no críticos.
- **Riel de navegación en escritorio**: patrón reutilizable con icono + etiqueta, ítem 80×56,
  estado activo por `primarySoft` + barra de 3 px. En móvil, `NavigationBar` inferior.
- **Objetivos táctiles**: mantener altura mínima 48 px en acciones de cabecera y 44 px en listas.
- **Motion**: duraciones 150–250 ms con curva de salida rápida; **respetar
  `MediaQuery.disableAnimations`** y ofrecer el ajuste del sistema, no un interruptor propio.
- **Estados obligatorios**: loading (skeleton), vacío, error, disabled, focus visible con contraste.

## 8. Limitaciones

- **NO VERIFICADO**: estados `hover`, `focus-visible` y `active` (no se provocaron de forma
  sistemática), orden real de tabulación, anuncios de lector de pantalla, y conformidad ARIA completa.
- **NO VERIFICADO**: rendimiento (LCP/CLS/INP) y peso de fuentes.
- **NO VERIFICADO**: comportamiento a 1920 px y zoom 200 %.
- El tema oscuro y el claro se midieron en momentos distintos (el recargado volvió a claro); los
  valores de cada tema son válidos por separado, no comparables entre sí por simultaneidad.
- La tipografía de la referencia es propietaria: se midió, **no** se copia ni se propone adoptarla.
- El viewport inicial del navegador integrado era 768×729; las medidas de 360/1280 se tomaron con
  `setViewportSize`.

## 9. Archivos Flutter relevantes

| Ruta | Qué se revisó |
| --- | --- |
| `apps/fulltech_app/lib/core/design_system/typography/app_typography.dart` | Escala Manrope y pesos |
| `apps/fulltech_app/lib/core/theme/app_colors.dart` | Tokens de color y contrastes calculados |

No se abrió ni modificó ningún widget de la app.

## 10. Próximos pasos (requieren autorización explícita)

1. Decidir si se adopta la escala responsiva de títulos (token nuevo, no cambio global).
2. Revisar el uso de `textMuted` en textos ≤14 px.
3. Si se aprueba, implementar con el flujo normal del repositorio (`AGENTS.md`,
   `docs/DESIGN_SYSTEM.md`, `flutter analyze`, `flutter test`).

## 11. Globalidad de la habilidad (análisis, sin cambios)

**Ya cubierto globalmente**: `engineering-standards` (evidencia, GO/NO-GO) y `project-memory`
(registro del estado). Ninguno cubre la investigación visual.

**Candidato a habilidad global nueva** (`~/.copilot/skills/web-visual-audit/`): el procedimiento
genérico — abrir página pública, medir layout/tipografía/color/contraste/motion/navegación/responsive
con `getBoundingClientRect` + `getComputedStyle`, resolver fondo efectivo, comprobar consola, y
etiquetar HECHO/HIPÓTESIS/RECOMENDACIÓN.

**Debe permanecer en FullPOS** (`.github/skills/auditor-visual-pos/`): rutas del design system,
tokens `AppColors`/`AppTypography`, mapeo a widgets propios, destino `docs/design-research/` y los
dominios excluidos (facturación, inventario, caja, autenticación).

**Recomendación**: crear la habilidad global y dejar que la de FullPOS la referencie, sin duplicar
las tablas de medición. No se implementó porque requiere su propia validación.

## 12. Siguiente paso para QA interactivo Flutter (Windows)

Esto es **automatización funcional**, distinta de esta auditoría web: aquí se mide una página de
terceros; allí se opera una app propia y se comprueban resultados.

Evidencia previa ya obtenida en este entorno:

| Capacidad | Estado | Evidencia |
| --- | --- | --- |
| Captura de ventana nativa | **Funciona** | `tools/flutter-qa/ui-window.ps1 -Action capture` (PrintWindow) |
| Clic real sobre la app | **Funciona** | La navegación al formulario se confirmó por captura |
| Escritura en `TextField` | **No fiable** | `SendKeys`, `SendInput` Unicode y portapapeles no insertan texto |

**Herramienta recomendada**: `flutter_driver` + `integration_test`, ya incluidos en el SDK
(no requieren instalación nueva), ejecutados con `flutter drive`. Resuelven la escritura porque
envían texto a través del framework, no por inyección de teclado del sistema. La captura de ventana
sigue siendo la evidencia visual.

**Alternativa**: Patrol, solo si se necesita control nativo del dispositivo (permisos, notificaciones,
cámara). Implica instalación y validación propia; no se instaló nada.
