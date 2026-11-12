# Control de navegación del AppBar — investigación visual (DaleVentas POS / FullPOS Cloud)

**Fecha:** 2026-11-08
**Alcance:** rediseño conceptual del elemento de navegación situado en la esquina superior izquierda del
AppBar de la pantalla de facturación (`Facturación`). **Investigación únicamente: no se ha modificado
ningún archivo de la aplicación.**

Etiquetado usado en todo el documento:

| Etiqueta | Significado |
| --- | --- |
| `HECHO` | Verificado en este turno: código real, SDK real, medición real en navegador o píxeles de una captura publicada. |
| `HIPÓTESIS` | Interpretación plausible, no verificada. |
| `RECOMENDACIÓN` | Propuesta de diseño o implementación. |

---

## 1. Objetivo y alcance

### 1.1 Objetivo

Sustituir visualmente **dos elementos** del AppBar de facturación —el botón azul de menú y el texto del
módulo— por **una sola pieza** elegante, moderna, compacta y profesional, conservando **intacta** la
funcionalidad del drawer.

### 1.2 Proyecto identificado (HECHO)

| Elemento | Valor verificado |
| --- | --- |
| Raíz del repositorio | `C:/Users/pc/DEV/PROYECTOS/PRODUCTOS/finalesdaleventas` (`git rev-parse --show-toplevel`) |
| Rama | `ultimos-trabajos` |
| App Flutter | `apps/fulltech_app` (paquete `daleventa_pos`), **no** APPYRA CRM, APPYRA IA, Fulltech Store ni `website` |
| Pantalla | `lib/modules/cotizaciones/cotizaciones_screen.dart`, título `'Facturación'` |
| AppBar real (escritorio) | `FullTechPageHeader(title: 'Facturación', preferDrawerLeading: true, …)` en `cotizaciones_screen.dart` L7329 → delega en `CustomAppBar` |
| AppBar real (móvil, < 900 px) | `_buildMobileAppBar()` en `cotizaciones_screen.dart` L7355 (header propio de 50 px) |
| Botón que abre el drawer (escritorio) | `_ElegantAppBarMenuButton` + glifo `_ModernMenuGlyph`, en `core/widgets/custom_app_bar.dart` |
| Botón que abre el drawer (móvil) | `_AnimatedDrawerButton`, en `cotizaciones_screen.dart` L9972 |
| Texto junto al botón | Título del AppBar: `'Facturación'` (17 px, w900, `#111827`) + `AppUpdateMiniControl` en línea |
| Drawer | `buildAdaptiveDrawer(...)` → `AppDrawer` (`core/widgets/app_drawer.dart`), ancho 318 px escritorio / 80 % móvil |

> Nota de convivencia: el árbol de trabajo tiene cambios de otros agentes (incluidos widgets de
> `core/ai_assistant/`). No se ha leído ni modificado nada fuera de los archivos citados, y el único
> artefacto creado es esta carpeta `docs/design-research/`.

---

## 2. Fuentes y fecha de observación

Navegación real ejecutada con Playwright MCP el **2026-11-08**. Ninguna fuente requirió credenciales.

| # | URL consultada | Título real devuelto | Autorización | Resultado |
| --- | --- | --- | --- | --- |
| 1 | `https://www.odoo.com/app/point-of-sale` (redirige a `/point-of-sale-shop`) | POS software for retail stores \| Odoo | Pública | Cabecera web medida + captura publicada de la UI del POS |
| 2 | `https://squareup.com/us/en/point-of-sale` | POS Systems \| Point of Sale Systems for all Businesses \| Square | Pública | Captura publicada de Square Retail POS (iPad) |
| 3 | `https://www.shopify.com/pos` | Point of Sale (POS) for Business - Shopify | Pública | Solo vídeo/imagen promocional → sin UI medible |
| 4 | `https://apps.shopify.com/shopify-pos` | Point of Sale - Unify online and in-person sales… \| Shopify App Store | Pública | Captura publicada del panel con módulo Point of Sale |
| 5 | `https://help.shopify.com/en/manual/sell-in-person/shopify-pos/customize-pos` | Shopify Help Center \| Customizing your Shopify POS with the POS editor | Pública | Sin imágenes estáticas en el artículo |
| 6 | `https://www.lightspeedhq.com/pos/retail/` | Retail POS System \| Point of Sale Software | Pública | Solo foto de dispositivo (UI no legible) |
| 7 | `https://loyverse.com/` (`/pos` devuelve 404) | Free POS Software. Point of Sale System. Loyverse POS | Pública | Foto de tablet en ángulo (UI no medible) |
| 8 | `https://joinposter.com/en` (`/pos` devuelve 404) | Cloud-Based iPad & Android Point-of-Sale (POS) System \| Poster POS | Pública | Captura publicada de la UI del POS (alta resolución) |
| 9 | `https://www.alegra.com/pos/` (redirige a `/rdominicana/pos/`) | Sistema POS y Facturación Alegra en República Dominicana | Pública | Captura publicada de la UI **medida píxel a píxel** |
| 10 | `https://www.sumup.com/en-gb/point-of-sale/` | SumUp POS Pro: the enterprise point of sale software | Pública | Sin capturas estáticas de UI (solo vídeo/canvas) |

**Ninguna de las 8 aplicaciones POS expone su interfaz operativa sin autenticación.** Por eso las
medidas de UI provienen de **capturas oficiales publicadas** (analizadas al píxel cuando fue posible) y
no de CSS computado de la app en vivo. El CSS computado solo se pudo medir en las **webs** de Odoo,
Square y Alegra, y se reporta como tal.

---

## 3. Evidencia

### 3.1 Capturas guardadas (rutas reales)

| Archivo | Fuente | Contenido |
| --- | --- | --- |
| `docs/design-research/evidence/2026-11-08-alegra-pos-facturar.png` | `cdn-websites.alegra.com/rdominicana/pos/pos--hero.webp` (741×530) | Barra superior "Facturar" del POS de Alegra |
| `docs/design-research/evidence/2026-11-08-odoo-pos-interfaz.png` | `odoocdn.com/.../apps/pos/interface.webp` | UI del POS de Odoo (barra + breadcrumb + buscador) |
| `docs/design-research/evidence/2026-11-08-square-pos-ipad.png` | `squareup.com` → `RSTPOS_USEN_iPad_Tablelayout_lightmode.png` | Square Retail POS: pestañas arriba, barra inferior |
| `docs/design-research/evidence/2026-11-08-shopify-admin-pos.png` | App Store de Shopify → `desktop_screenshot/CMij7un77f0CEAE` | Wordmark a la izquierda + módulo como chip |
| `docs/design-research/evidence/2026-11-08-poster-pos-tablet.png` | `joinposter.com/i/site/business/coffeeshop/coffeeshop-tablet-en.png` (2120×1592) | "< Tables" + pestañas + hamburguesa secundaria |
| `docs/design-research/evidence/2026-11-08-loyverse-pos.png` | `loyverse.com/.../us-home/pos.webp` | Solo foto de tablet (limitación) |
| `docs/design-research/evidence/2026-11-08-lightspeed-retail-hero.png` | `assets.lightspeedhq.com/.../hero-united.webp` | Solo foto de dispositivo (limitación) |

### 3.2 Consola

- `squareup.com`: 9 errores de consola (terceros/trackers). Sin impacto en la evidencia visual.
- `alegra.com`: 9 errores de consola (marketing). Sin impacto.
- `odoo.com`, `joinposter.com`: 0–1 errores irrelevantes.

### 3.3 Aviso metodológico

Las capturas de producto son **imágenes publicadas por cada proveedor**, no la app ejecutándose. Por
tanto: `HECHO` = lo que se ve y se mide en la imagen; `HIPÓTESIS` = la equivalencia con puntos y píxeles
lógicos de Flutter. La escala original de cada captura es desconocida → **solo se usan proporciones
respecto a la altura de la barra**, que son invariantes.

---

## 4. Medidas verificadas (HECHO)

### 4.1 Alegra POS — medición píxel a píxel de la captura publicada (741×530)

Medición ejecutada en el navegador sobre el canvas de la imagen (lectura de `getImageData`, detección de
la banda por dominancia de verde y caja envolvente de los píxeles claros).

| Elemento | Dimensión | Propiedad | Valor | Cómo se midió |
| --- | --- | --- | --- | --- |
| Barra superior | Color | fondo | `#01B19F` | Muestra en (400, 6) |
| Barra superior | Alto | `height` | **40 px** (y 0–39) | Última fila con dominancia de verde; fila 40 ya es blanca (ratio 1.0) |
| Icono de menú | Posición | `x` inicial | **10 px** desde el borde | Bbox de píxeles claros en x 0–40, y 6–32 |
| Icono de menú | Tamaño | ancho × alto | **13 × 11 px** | Bbox del glifo (3 barras, separación ≈ 4 px, grosor ≈ 2 px) |
| Título del módulo | Inicio | `x` | **38 px** | Primera columna con trazo claro tras el icono |
| Título del módulo | Altura de mayúsculas | cap-height | **9 px** → ≈13 px de fuente (cap ratio ≈ 0.7, `HIPÓTESIS`) | Bbox vertical del texto (y 15–23) |
| Separación icono → texto | `gap` | — | **16 px** | `x(texto) − (x(icono) + ancho(icono))` |
| Cluster derecho | Alto | — | **26 px** (píldora "Tienda Decko") | Bbox de zona clara x 481–727 |
| Fila de herramientas inferior | Inicio | `y` | **40 px** (blanca) | Primera fila con ratio de claros > 0.9 |
| Texto/icono blanco sobre la banda | Contraste | ratio WCAG | **≈2.4 – 2.7 : 1** | Fórmula WCAG sobre `#01B19F` vs blanco (`#FFFFFF`) y vs trazo muestreado (`#ADFFFF`) |

**Ratios normalizados (invariantes a la escala):**

| Relación | Alegra | Lectura |
| --- | --- | --- |
| alto de glifo / alto de barra | 11 / 40 = **0.28** | Icono discreto, no protagonista |
| ancho de glifo / alto de barra | 13 / 40 = **0.33** | — |
| inset izquierdo / alto de barra | 10 / 40 = **0.25** | — |
| gap icono-texto / alto de barra | 16 / 40 = **0.40** | — |
| inicio del título / alto de barra | 38 / 40 = **0.95** | El texto arranca a menos de una "barra" del borde |

`HECHO`: el POS de Alegra usa **glifo desnudo + palabra del módulo**, sin logo, sin contenedor, sin
color de acento en el control. Es exactamente el patrón que el usuario quiere abandonar… y es el líder
regional. Es decir: copiarlo no diferencia; hay margen para una solución superior.

### 4.2 Odoo POS — observación sobre captura publicada + cabecera web medida

| Elemento | Valor | Etiqueta |
| --- | --- | --- |
| Barra del POS | Blanca, **sin hamburguesa a la izquierda**; altura ≈ 6–7 % del alto de la captura | `HECHO` (visual) |
| Identidad de sesión | Chip de usuario arriba a la derecha: avatar circular + nombre + chevron + punto verde | `HECHO` (visual) |
| Identidad de módulo | **Breadcrumb dentro del contenido**: icono de casa + chevron + categoría ("Furniture") | `HECHO` (visual) |
| Búsqueda | Campo a la derecha del breadcrumb, no en la barra | `HECHO` (visual) |
| Cabecera de la web de producto | 60 px, `position: fixed`, fondo blanco; marca textual 68×22; nav 14 px / 600 | `HECHO` (CSS computado) |

Patrón: **la navegación jerárquica vive en el contenido**, la barra se reserva para identidad y estado.

### 4.3 Square POS

| Elemento | Valor | Etiqueta |
| --- | --- | --- |
| Barra superior | Pestañas a la izquierda ("Dining room" activa con subrayado, "Patio") | `HECHO` (visual) |
| Acciones | Texto azul a la derecha ("Settle tips", "Actions"), sin contenedor | `HECHO` (visual) |
| Hamburger en la barra superior | **No existe** | `HECHO` (visual) |
| Navegación principal | **Barra inferior** con 5 destinos icono+texto (Floor plan, Menu, Checks, Transactions, More) | `HECHO` (visual) |
| Overflow | "More" (☰) al extremo derecho de la barra inferior | `HECHO` (visual) |

### 4.4 Shopify (panel con módulo Point of Sale)

| Elemento | Valor | Etiqueta |
| --- | --- | --- |
| Barra superior | Wordmark de marca a la izquierda dentro de panel blanco redondeado; buscador a continuación | `HECHO` (visual) |
| Identidad de módulo | Chip etiquetado ("Point of Sale") con icono, en la cabecera del contenido, no en la barra | `HECHO` (visual) |
| Navegación | Sidebar fija con selector de ubicación + destinos icono+texto | `HECHO` (visual) |

### 4.5 Poster POS

| Elemento | Valor | Etiqueta |
| --- | --- | --- |
| Barra superior | Oscura, con el **control de retorno como "‹ Tables"**: chevron + etiqueta, sin caja | `HECHO` (visual) |
| Pestañas de contexto | "Receipt" (activa: fondo blanco + check azul) y "Customer" | `HECHO` (visual) |
| Centro | "Receipt #96164 ⌄" con subtítulo "Table 3" | `HECHO` (visual) |
| Derecha | Campana + **hamburguesa desnuda** + nombre de usuario + candado + punto verde | `HECHO` (visual) |

Patrón clave: cuando el menú no es la navegación principal, la hamburguesa **pierde la esquina
izquierda** y se degrada a icono secundario a la derecha.

### 4.6 Nuestro AppBar actual — medido en código y en el SDK de Flutter (HECHO)

Constantes del SDK verificadas en `C:\src\flutter`:

- `kToolbarHeight = 56.0` (`material/constants.dart`)
- `AppBar.leadingWidth` por defecto **56.0** (`_kLeadingWidth = kToolbarHeight`, `material/app_bar.dart`)
- `NavigationToolbar.kMiddleSpacing = 16.0` (`widgets/navigation_toolbar.dart`) → `titleSpacing` por defecto

Geometría derivada (escritorio ≥ 900 px):

| Elemento | Propiedad | Valor actual | Origen |
| --- | --- | --- | --- |
| AppBar | alto | 56 px | `kToolbarHeight` |
| AppBar | fondo / borde inferior | blanco / 1 px `#9FB6C8` | `CustomAppBar.build` (color **hardcodeado**) |
| Slot del leading | ancho | 56 px | `leadingWidth` por defecto |
| Botón | caja | **32 × 32**, radio **7** | `_ElegantAppBarMenuButton` |
| Botón | fondo / borde | `#1957E6` / `#1957E6` 1 px | ídem |
| Botón | sombra | `#1957E6` α 0.16, blur 8, spread −5, offset (0,3) | ídem |
| Botón | inset izquierdo | **10 px** (`Padding(left: 10, top: 10, bottom: 10)`) | ídem |
| Glifo | caja | **15 × 11**, 3 barras de 2.2 px, radios 999 | `_ModernMenuGlyph` |
| Hover | transformación | `AnimatedScale` 1.015 + sombra α 0.24 / blur 11 | ídem |
| Pressed | transformación | escala 0.96 + rotación 0.03 turn, 140–150 ms `easeOutCubic` | ídem |
| Título | estilo | 17 px (titleMedium), **w900**, `#111827` (hardcodeado), letterSpacing 0 | `CustomAppBar.build` + `AppTypography` |
| Título | inicio en x | **72 px** (56 leadingWidth + 16 titleSpacing) | cálculo sobre constantes del SDK |
| **Hueco botón → título** | — | **30 px** (72 − 42) | cálculo |
| Contraste glifo blanco / `#1957E6` | ratio | **5.92 : 1** ✓ AA | fórmula WCAG |
| Contraste título `#111827` / blanco | ratio | **17.55 : 1** ✓ AAA | fórmula WCAG |
| Accesibilidad de teclado | — | **`GestureDetector` + `Tooltip`**: no entra en el orden de foco, Enter/Espacio no lo activan | lectura del código |
| Semántica | — | `_ModernMenuGlyph` aporta `Semantics(label: 'Abrir menú')`; el botón no declara `button: true` | lectura del código |

Móvil (< 900 px, código distinto en `cotizaciones_screen.dart`):

| Elemento | Valor |
| --- | --- |
| Header | 50 px, gradiente `#2F6BFF → #2472F3`, título centrado 19.5 w800 |
| Botón | `_AnimatedDrawerButton`: área 44 × 44, contenedor **38 × 32**, radio 9, blanco α 0.18→0.24, borde blanco α 0.28, `Icons.menu_rounded` 21 |
| Accesibilidad | también `GestureDetector` (sin foco de teclado) |

**Diagnóstico cuantificado del problema (HECHO + `HIPÓTESIS` de causa):**

1. El control ocupa **32 px de color saturado** en una barra blanca: se convierte en el punto de mayor
   contraste cromático del AppBar y compite con el título.
2. Entre el botón y el título hay un **hueco de 30 px** (56 − 42 + 16). Los dos elementos no se leen
   como una unidad; se leen como "botón suelto" + "texto suelto". `HECHO` (cálculo) → explica la
   percepción de "combinación poco elegante".
3. El conjunto consume **72 px** antes del nombre del módulo, un 29 % más que el referente regional más
   cercano (Alegra: 0.95 × altura de barra ≈ 53 px equivalentes a 56 px de barra).
4. El botón **no tiene marca**: es un cuadrado azul genérico que podría ser de cualquier producto.
5. **No es accesible por teclado** (Windows y web incluidos), y no expone `Semantics(button: true)`.

### 4.7 Activos de marca disponibles (HECHO)

| Archivo | Tamaño | Observación |
| --- | --- | --- |
| `assets/image/logo.png` | 1.58 MB | Logotipo 3D "FP" con anillos orbitales y destellos |
| `assets/image/nuevologo.png` | 1.20 MB | Misma familia visual, alta resolución |
| `assets/image/logo-web.webp` | 7.9 KB | Versión web del mismo logotipo 3D |
| `assets/image/logo_launcher.png` | 672 KB | Icono de lanzador |

Inspección visual directa: el logotipo es **3D glossy con degradados, brillos y anillo**. A 20–34 px
(escala del AppBar) pierde legibilidad: se convierte en una mancha azul/negra. `HECHO` visual + `HIPÓTESIS`
de resultado a tamaño real. **Conclusión:** usar el logotipo completo en el AppBar no es viable; hace
falta una marca plana derivada (monograma) o el wordmark tipográfico.

---

## 5. Observaciones de UX/UI

### 5.1 Cuatro arquetipos verificados para "identidad + acceso al menú"

| Arquetipo | Sistemas observados | Cómo resuelven el problema | Coste en la barra |
| --- | --- | --- | --- |
| **A. Glifo desnudo + palabra del módulo** | Alegra | Icono sin contenedor a 10 px del borde y texto 16 px después | Muy bajo (≈0.95 × barra) |
| **B. Marca + navegación fuera de la barra** | Shopify (wordmark + sidebar), Square (barra inferior) | La barra no contiene hamburguesa; el menú es persistente o inferior | Bajo para el menú, alto para la marca |
| **C. Jerarquía dentro del contenido** | Odoo | Breadcrumb en el área de trabajo; barra solo para identidad de sesión | Nulo en la barra |
| **D. Contexto en pestañas + hamburguesa secundaria** | Poster, Square | Pestañas/breadcrumb arriba; hamburguesa degradada a icono de utilidad a la derecha | Bajo, pero requiere sistema de pestañas |

### 5.2 Buenas prácticas coincidentes (HECHO transversal)

1. **Ningún líder de mercado usa un cuadrado de color saturado como disparador del menú.** El color de
   marca se reserva para acciones primarias (Alegra: "Nuevo producto"; Square: "Pay"; Poster: "Pay").
2. **La marca, cuando existe, es tipográfica o plana** (Shopify: wordmark; Poster: sin marca; Alegra: sin
   marca). Nunca un logotipo 3D dentro de la barra.
3. **El indicador de "hay menú" es el propio glifo o el contexto de pestañas**, no un borde ni un badge.
4. **Movimiento discreto:** en las capturas no hay animaciones visibles; la jerarquía se resuelve con
   tipografía, no con efectos. `HIPÓTESIS`: los líderes evitan el motion llamativo en caja.
5. **Estado de sesión siempre a la derecha** (avatar/nombre/usuario + candado o punto de conexión). Los
   cuatro sistemas con barra lo muestran ahí.
6. **Contraste:** el único caso medido con números (Alegra) **no cumple AA** (≈2.4–2.7:1 sobre la banda
   teal). Oportunidad clara de superar al referente en accesibilidad.

### 5.3 Qué funciona mejor según el caso de uso de DaleVentas

| Necesidad del producto | Implicación de diseño |
| --- | --- |
| Windows escritorio con drawer de 318 px y muchas secciones | El acceso al menú debe ser **permanente y evidente**, no oculto en una barra inferior |
| Uso intensivo con teclado (`HECHO`: hoy no es accesible por teclado) | El control debe ser **foco + Enter/Espacio** con anillo visible |
| Marca multi-tenant con logo 3D inservible a 20 px | Se necesita **monograma plano propio** |
| Barra blanca de 56 px con borde inferior | Cualquier solución debe pesar poco: **sin sombras ni degradados propios** |
| Móvil con header azul de 50 px | La misma pieza debe funcionar invertida (blanco sobre azul) |
| Densidad: POS con catálogo, carrito y detalle | Cada píxel horizontal cuenta: objetivo ≤ 60 px hasta el nombre del módulo |

---

## 6. Comparación con el sistema de diseño FullPOS

| Referencia observada | Equivalente en FullPOS | Estado |
| --- | --- | --- |
| Glifo desnudo + texto (Alegra, 0.95 × barra) | `_ElegantAppBarMenuButton` (32 px + hueco 30 px = 1.29 × barra) | **Mejora** (reducir peso y hueco) |
| Marca tipográfica plana (Shopify) | `_DrawerWordmark` ("FullPOS" + "Cloud", Manrope w900) — ya existe, pero **solo dentro del drawer** | **Mejora** (reutilizar en la barra) |
| Logo/monograma | `assets/image/logo*.png` 3D, ilegible a 20 px | **Propuesta** (monograma plano derivado) |
| Pestañas de contexto (Poster, Square) | No existe en la arquitectura actual | Propuesta de otra fase; cambiaría navegación → **fuera de alcance** |
| Identidad de sesión a la derecha | `_CompanyAccountMenu` + `_buildDefaultPrimaryAvatar` | **Ya existe** (no tocar) |
| Estado/sincronización visible | `SyncStatusMenuButton`, `CashTurnMenuButton` | **Ya existe** (no tocar) |
| Foco de teclado en el control | `GestureDetector` (no focusable) | **Mejora obligatoria** |
| Contraste del control | 5.92 : 1 (mejor que el referente medido) | **Existe** (mantener) |
| Tokens: borde inferior `#9FB6C8` y título `#111827` hardcodeados | `AppColors.border` = `#DDE7EE`, `AppColors.textPrimary` = `#102235` | **Mejora** (usar tokens) |
| Radios: 7 px en el botón vs 8–12 px predominante en la app | `AppColors`/tema usan 8–18 px | **Mejora** (alinear a 10) |

---

## 7. Propuestas originales (RECOMENDACIÓN)

Todas usan **solo** tokens existentes: `AppColors.primary #1957E6`, `primarySoft #EAF1FF`,
`secondaryBorder #CFE0FF`, `textPrimary #102235`, `textMuted #64748B`, `border #DDE7EE`,
`AppTypography.fontFamily = Manrope`, `AppIconSizes.navigation = 22`. Ninguna introduce color nuevo.

### Alternativa A — Monograma funcional "FP"

| Aspecto | Especificación |
| --- | --- |
| **Apariencia** | Teja cuadrada 34×34, radio 10, fondo `primarySoft`, borde 1 px `secondaryBorder`, con el monograma **"FP"** en Manrope 15 / w900 / `primary`. Sustituye por completo al cuadrado azul con hamburguesa. |
| **Estructura visual** | Marca (teja) + nombre del módulo como texto plano a su derecha. Sin contenedor secundario, sin sombra en reposo. |
| **Dimensiones** | Teja 34×34; inset izquierdo 12; `leadingWidth: 46`; `titleSpacing: 8`; título 15 / w800 / `textPrimary`. Total hasta el texto: **54 px** (hoy 72). |
| **Posición del elemento interactivo** | Toda la teja (34×34) más 6 px de padding interno → área de toque ≥ 40×40 (cumple el mínimo de 44 con el inset). |
| **Cómo se abriría el drawer** | `onTap` de la teja → mismo `Scaffold.openDrawer()` actual. **Cero cambios de comportamiento.** |
| **Cómo se indica que hay menú** | (1) `Tooltip('Abrir menú')`; (2) hover: la teja pasa a `primary` y el monograma a blanco, 140 ms `easeOutCubic`; (3) opcional en ≥ 1200 px: chevron de 12 px `textMuted` que aparece a la derecha del título. |
| **Ventajas** | Marca propia en el lugar de mayor jerarquía; ahorra 18 px; elimina el hueco de 30 px; idéntico en Windows/web/móvil; sin assets nuevos (texto, no imagen). |
| **Desventajas** | Un monograma tipográfico exige disciplina (si se cambia el wordmark del drawer, hay que sincronizarlo); a 15 px "FP" puede confundirse si el usuario no conoce la marca (`HIPÓTESIS` a validar visualmente). |
| **Compatibilidad con el AppBar actual** | Alta: `CustomAppBar` ya recibe `leading`; basta pasar un `leadingWidth` y un widget nuevo. No toca `AppBar` ni el drawer. |
| **Windows / web / móvil** | Escritorio: teja suave + texto oscuro. Móvil: misma teja en blanco α 0.16 (hover α 0.26), monograma blanco. Web: hover y foco visibles. |

### Alternativa B — Logotipo de navegación (lockup)

| Aspecto | Especificación |
| --- | --- |
| **Apariencia** | Lockup horizontal: teja 26×26 con "FP" + wordmark en dos líneas "FullPOS" (14 / w900 / `textPrimary`) sobre "Cloud" (9.5 / w900 / `primary`), reutilizando la tipografía de `_DrawerWordmark`. |
| **Estructura visual** | Lockup + separador vertical 1 px `border` (alto 20) + módulo en `labelSmall` mayúsculas `textMuted` ("FACTURACIÓN"). |
| **Dimensiones** | Ancho ≈ 168–190 px; alto 34; `leadingWidth` ≈ 200; `titleSpacing: 0` con el módulo dentro del slot del título. |
| **Posición del elemento interactivo** | Todo el lockup (área 190×40) abre el drawer; el módulo **no** es interactivo (evita un falso destino). |
| **Cómo se abriría el drawer** | Tap sobre el lockup → `openDrawer()`. |
| **Cómo se indica que hay menú** | Hover: fondo `surfaceAlt` + borde `secondaryBorder` en la teja; chevron de 12 px aparece al final del lockup. |
| **Ventajas** | Máxima identidad de producto; el módulo queda como contexto tipográfico (patrón Shopify); excelente para capturas comerciales. |
| **Desventajas** | Consume ~200 px en una barra de 56; en 900–1100 px de ancho total compite con `CashTurnMenuButton`, `SyncStatusMenuButton` y el menú de cuenta; requiere eliminar el título nativo del AppBar (más superficie de regresión). |
| **Compatibilidad con el AppBar actual** | Media: exige `leadingWidth` grande o mover el control al slot `title`, y convive mal con `AppUpdateMiniControl`. |
| **Windows / web / móvil** | Escritorio/web: correcto. Móvil: el header de 50 px **no admite** el lockup (título centrado + 2 iconos a la derecha) → habría que mantener dos piezas distintas. |

### Alternativa C — Navegación minimalista premium

| Aspecto | Especificación |
| --- | --- |
| **Apariencia** | Glifo de 3 barras de 1.5 px (16×12) en `textSecondary`, dentro de un área fantasmal 36×36 (radio 9) sin fondo en reposo. Título 15 / w800 / `textPrimary`. |
| **Estructura visual** | Solo tipografía y un glifo fino; el color se reserva al hover/foco. |
| **Dimensiones** | Área 36×36; inset 10; `leadingWidth: 46`; `titleSpacing: 8` → texto a 54 px. |
| **Posición del elemento interactivo** | 36×36 (con `InkWell` de 44×44 por debajo). |
| **Cómo se abriría el drawer** | Tap/Enter/Espacio → `openDrawer()`. |
| **Cómo se indica que hay menú** | Glifo de barras + `Tooltip`; hover: fondo `primarySoft`, barras `primary`; foco: anillo 2 px. |
| **Ventajas** | La opción más limpia y la más barata de implementar (≈15 líneas sobre el widget actual); elimina por completo la sensación de "botón pegado al título". |
| **Desventajas** | Sigue siendo "una hamburguesa" (el usuario pidió explorar marca/monograma); no aporta identidad; es esencialmente lo que ya hace Alegra, con mejor contraste. |
| **Compatibilidad con el AppBar actual** | Muy alta: cambio quirúrgico en `_ElegantAppBarMenuButton`. |
| **Windows / web / móvil** | Idéntico en las tres; en móvil basta cambiar el color base a blanco. |

### Alternativa D — Encabezado integrado ("module pill")

| Aspecto | Especificación |
| --- | --- |
| **Apariencia** | **Una sola píldora** de 34 px de alto: teja 20×20 con "FP", separador vertical 1 px, nombre del módulo 13 / w800 / `textPrimary`, y chevron de 12 px `textMuted`. Fondo blanco, borde 1 px `border`, sombra `AppColors.shadow`. |
| **Estructura visual** | Un único objeto: marca + contexto + afordancia de menú. Nada fuera de la píldora. |
| **Dimensiones** | Alto 34; padding horizontal 9; ancho 148–190 (máx. 200 con ellipsis); `leadingWidth` ≈ ancho + 12; `titleSpacing: 0`. |
| **Posición del elemento interactivo** | Toda la píldora. |
| **Cómo se abriría el drawer** | Tap en cualquier punto de la píldora → `openDrawer()`. |
| **Cómo se indica que hay menú** | Chevron + hover (borde `secondaryBorder`, fondo `#F7FAFF`). |
| **Ventajas** | Es la solución que **literalmente sustituye los dos elementos por uno**; se lee como "control de software comercial"; excelente jerarquía; el chevron comunica el menú mejor que una hamburguesa. |
| **Desventajas** | El chevron hacia abajo sugiere "desplegable", no "drawer lateral" (riesgo de expectativa, `HIPÓTESIS`); mayor coste de implementación (leading ancho, control del ancho, interacción con `AppUpdateMiniControl`); en móvil necesita variante traslúcida. |
| **Compatibilidad con el AppBar actual** | Media-alta: requiere `leadingWidth` ampliado; no rompe `AppBar`, pero hay que revisar la coexistencia con las acciones y con el control de actualización. |
| **Windows / web / móvil** | Escritorio/web: ideal. Móvil: se puede encapsular en la parte izquierda del header, pero cambiaría el título centrado actual. |

### Alternativa E — "Live anchor" (monograma con anillo de estado real)

| Aspecto | Especificación |
| --- | --- |
| **Apariencia** | Teja 34×34 (radio 10) con "FP" y un **anillo de 2 px** alrededor que refleja el estado real de sincronización ya existente (`SyncStatusMenuButton`): verde `success`, ámbar `warning`, rojo `error`. En reposo el anillo es `secondaryBorder`. |
| **Estructura visual** | Marca + estado + módulo. Un solo ornamento, y **verdadero** (no decorativo). |
| **Dimensiones** | Teja 30×30 + anillo 2 px + 2 px de aire = 34; inset 12; `leadingWidth: 46`; `titleSpacing: 8`. |
| **Posición del elemento interactivo** | Teja; el anillo no es interactivo. |
| **Cómo se abriría el drawer** | Tap/Enter → `openDrawer()`. |
| **Cómo se indica que hay menú** | Tooltip + hover (anillo pasa a `primary` a 3 px) + optional chevron en pantallas anchas. |
| **Ventajas** | Original y útil: aprovecha un estado que ya existe y que hoy está escondido en un menú; comunica "sistema vivo"; refuerza la marca. |
| **Desventajas** | Puede leerse como "avatar de usuario" (riesgo real: ya hay avatar a la derecha); duplica información de estado (existe `SyncStatusMenuButton`); más complejidad técnica y de pruebas; el usuario pidió no recargar. |
| **Compatibilidad con el AppBar actual** | Media: exige conectar el provider de sync al leading y añadir pruebas de estado. |
| **Windows / web / móvil** | Correcto en las tres, pero en móvil el anillo compite con el `statusBar` azul. |

### Propuesta complementaria (fuera del AppBar, requiere autorización aparte)

**Rail lateral persistente en ≥ 1280 px.** Square, Shopify y Poster evitan el drawer en escritorio
grande. DaleVentas ya tiene un patrón de rail colapsado en facturación (`_DesktopCategoryRail`,
`collapsedWidth`). Extenderlo a la navegación global **eliminaría la necesidad del control** en
escritorio ancho. Es un cambio de navegación, no visual → **no incluido en esta investigación**; se
menciona como dirección futura.

---

## 8. Tabla de evaluación

Escala 1–5 (5 = mejor). Pesos orientados al producto: la navegación y la identidad pesan más que la
novedad.

| Criterio | Peso | A Monograma | B Lockup | C Minimalista | D Píldora | E Live anchor |
| --- | --- | --- | --- | --- | --- | --- |
| Elegancia visual | 0.15 | 5 | 4 | 4 | 4 | 4 |
| Claridad de navegación | 0.20 | 4 | 4 | 5 | 4 | 3 |
| Identidad de marca | 0.20 | 5 | 5 | 2 | 4 | 5 |
| Aprovechamiento del espacio | 0.10 | 4 | 3 | 5 | 3 | 4 |
| Integración con el diseño actual | 0.15 | 4 | 4 | 5 | 5 | 3 |
| Accesibilidad | 0.10 | 4 | 4 | 5 | 4 | 3 |
| Adaptabilidad responsive | 0.05 | 5 | 3 | 5 | 4 | 4 |
| Complejidad de implementación | 0.05 | 4 | 3 | 5 | 4 | 2 |
| **Total ponderado** | 1.00 | **4.40** | 4.00 | 4.25 | 4.05 | 3.65 |

**Lectura:** la propuesta más "bonita" (E) pierde por complejidad y por duplicar señal. La más fácil (C)
queda cerca, pero no resuelve la queja central (identidad y peso del botón).

---

## 9. Tres alternativas finalistas

1. **A — Monograma funcional (4.40).** Gana: es la única que aporta marca propia, reduce el hueco de
   30 px a 8 px, ahorra 18 px de ancho y no necesita assets nuevos ni cambios de navegación.
2. **C — Navegación minimalista premium (4.25).** Finalista por accesibilidad y bajo riesgo; sirve como
   **red de seguridad** si la dirección rechaza el monograma.
3. **D — Encabezado integrado (4.05).** Finalista por elegancia de pieza única en pantallas anchas; se
   propone como **variante de A** cuando el ancho disponible ≥ 1200 px.

---

## 10. Recomendación final y especificación visual

### 10.1 Recomendación

**Adoptar A (monograma funcional) como base, con la disciplina de interacción de C y la afordancia de D
en pantallas anchas.** Es la única combinación que, sobre evidencia medida, resuelve las cinco causas del
problema actual (peso cromático, hueco de 30 px, falta de marca, falta de foco de teclado, tokens
inconsistentes) sin tocar el drawer, las rutas ni los permisos.

### 10.2 Especificación (escritorio ≥ 900 px, barra de 56 px)

| Propiedad | Valor | Token / origen |
| --- | --- | --- |
| Slot del control | `leadingWidth: 46` | `AppBar.leadingWidth` (soportado) |
| Inset izquierdo | 12 | — |
| Teja | 34 × 34, radio 10 | — |
| Fondo reposo | `primarySoft` `#EAF1FF` | `AppColors.primarySoft` |
| Borde reposo | 1 px `secondaryBorder` `#CFE0FF` | `AppColors.secondaryBorder` |
| Monograma | "FP", Manrope 15 / w900, `primary` `#1957E6`, `height: 1` | `AppTypography.fontFamily` + `AppColors.primary` |
| Hover | fondo `primary`, texto blanco, sombra `#1957E6` α 0.20 blur 10 offset (0,3) | `AppColors.primary` |
| Pressed | escala 0.98, 90 ms | — |
| Foco | anillo 2 px `primary` α 0.45, radio 12, offset 2 | `AppColors.primary` |
| Transición | 140–160 ms `Curves.easeOutCubic` (color, sombra) | — |
| Título | 15 / w800 / `textPrimary` `#102235`, letterSpacing 0 | `AppColors.textPrimary` |
| `titleSpacing` | 8 | `NavigationToolbar.kMiddleSpacing` es 16 por defecto |
| Chevron (≥ 1200 px) | 12 px, `textMuted`, aparece en hover, 8 px tras el título | `AppColors.textMuted` |
| Semántica | `Semantics(button: true, label: 'Abrir menú')` + `Tooltip('Abrir menú')` + foco de teclado (Enter/Espacio) | obligatorio |
| Borde inferior del AppBar | 1 px `AppColors.border` (sustituir `#9FB6C8`) | `AppColors.border` |
| Color del título | `AppColors.textPrimary` (sustituir `#111827`) | `AppColors.textPrimary` |

### 10.3 Responsive

| Ancho | Comportamiento |
| --- | --- |
| ≥ 1200 px | A + chevron sutil en hover |
| 900–1199 px | A sin chevron |
| < 900 px (móvil) | Misma teja 34×34, fondo blanco α 0.16 (hover 0.26), monograma blanco, borde blanco α 0.28; se coloca donde hoy está `_AnimatedDrawerButton` (área 44×44). El título centrado no cambia. |

### 10.4 Estados

| Estado | Comportamiento |
| --- | --- |
| Reposo | Teja `primarySoft` + monograma `primary`; sin sombra |
| Hover (web/Windows) | Teja `primary` + monograma blanco + sombra suave |
| Foco (teclado) | Anillo 2 px; Enter/Espacio abren el drawer |
| Pressed | Escala 0.98 |
| Drawer abierto | La teja se mantiene visible tras el scrim; opcionalmente invierte a `primary` mientras el drawer está abierto (requiere estado del drawer: `HIPÓTESIS` de bajo riesgo) |
| Movimiento reducido | Sin transición de color (solo cambio instantáneo) |

### 10.5 Lo que **no** se debe hacer (derivado de la investigación)

- No usar el logotipo 3D (`logo.png`, `nuevologo.png`) a 20–34 px: ilegible (`HECHO` visual).
- No añadir sombras propias ni degradados en la barra (los líderes usan superficies planas).
- No poner badges, puntos o contadores sobre el control sin un estado real que los justifique.
- No cambiar el drawer, sus 318 px, ni `buildAdaptiveDrawer`.
- No introducir pestañas o rail lateral en esta fase: es navegación, no estética.

### 10.6 Archivos Flutter que habría que tocar **después** (con autorización)

| Ruta | Qué contiene | Cambio previsto |
| --- | --- | --- |
| `apps/fulltech_app/lib/core/widgets/custom_app_bar.dart` | `CustomAppBar`, `_ElegantAppBarMenuButton`, `_ModernMenuGlyph` | Nuevo widget `_AppBarBrandMenu` que sustituye al botón; `leadingWidth`; tokens de borde/título; foco de teclado |
| `apps/fulltech_app/lib/core/widgets/fulltech_page_header.dart` | `FullTechPageHeader` | Exponer `leadingWidth`/`titleSpacing` si hace falta |
| `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart` | `_buildDesktopAppBar` (L7325), `_buildMobileAppBar` (L7355), `_AnimatedDrawerButton` (L9972) | Alinear la variante móvil a la misma teja |
| `apps/fulltech_app/lib/core/widgets/app_drawer.dart` | `_DrawerWordmark` | Solo referencia tipográfica (sin cambios funcionales) |
| `apps/fulltech_app/lib/core/theme/app_colors.dart` | Tokens | Sin cambios (todo existe) |
| `apps/fulltech_app/test/features/account/account_settings_navigation_test.dart` | `expect(find.byTooltip('Abrir menú'), …)` L721 | Se mantiene el tooltip, por lo que el test sigue siendo válido; añadir prueba de foco y de geometría |

---

## 11. Limitaciones

1. **No se pudo acceder a la UI operativa de ninguna de las 8 aplicaciones** (requieren autenticación).
   Todas las medidas de producto provienen de **capturas oficiales publicadas**, no de la app en vivo.
2. **La escala original de las capturas es desconocida**; se reportan proporciones y se evita afirmar
   puntos Flutter exactos a partir de imágenes.
3. Solo se obtuvo **CSS computado** de las webs de marketing (Odoo 60 px fijo, etc.), no de los POS.
4. **Loyverse, Lightspeed y SumUp** no publican capturas estáticas de su pantalla de caja en las páginas
   consultadas (solo fotos de dispositivo o vídeo) → no se midieron y no se describen detalles de su
   barra superior.
5. **Shopify**: el artículo de ayuda consultado no contiene imágenes estáticas; la evidencia usada es la
   captura del panel en la App Store (admin web, no la app POS de iPad).
6. No se ha ejecutado la app de DaleVentas en modo web para medir su AppBar real: las medidas propias
   provienen del **código y de las constantes del SDK** (`kToolbarHeight = 56`, `leadingWidth = 56`,
   `kMiddleSpacing = 16`), que son deterministas.
7. El contraste de Alegra se calcula sobre colores muestreados de un WebP con compresión: el valor real
   puede variar ligeramente, pero el orden de magnitud (por debajo de 3:1) se mantiene.

---

## 12. Próximos pasos (requieren autorización explícita)

1. Elegir dirección: **A** (recomendada), **C** (minimalista) o **D** (píldora integrada).
2. Autorizar la implementación en `custom_app_bar.dart` + la variante móvil de `cotizaciones_screen.dart`.
3. Validación prevista tras implementar: `flutter analyze`, pruebas del área, comparación visual a
   1280×800 / 1024×768 / 390×780, y verificación de foco/teclado en Windows.
4. Nada de esto se ha ejecutado: **esta investigación no modifica código**.

---

**Estado de la auditoría:** completa en investigación; **ninguna modificación aplicada**. Se requiere
autorización para pasar a implementación.
