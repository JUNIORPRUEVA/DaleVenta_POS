# Alegra POS (interfaz real autenticada) — AppBar, control de navegación y drawer

**Fecha:** 2026-11-08
**Proyecto objetivo:** DaleVentas POS / FullPOS Cloud (`apps/fulltech_app`)
**Tipo:** investigación visual con la habilidad `auditor-visual-pos`. **Sin cambios de código.**

Etiquetas: `HECHO` (medido en este turno) · `HIPÓTESIS` · `RECOMENDACIÓN`.

---

## 1. Objetivo y alcance

Medir la **interfaz real** del POS de Alegra —ya autenticada por el usuario— para fundamentar el rediseño
del control de navegación del AppBar de FullPOS: barra superior, botón/menú lateral, drawer, iconografía,
tipografía, color, medidas, sombras y motion.

Fuera de alcance: datos de clientes, importes, credenciales, cookies, tokens, operaciones comerciales.

---

## 2. Método, herramientas y limitaciones

| Elemento | Estado |
| --- | --- |
| Servidor usado | **Playwright MCP independiente** (`microsoft/playwright-mcp`), perfil aislado `ms-playwright-mcp` |
| `browser_evaluate` | ✅ Usada (navegación, DOM, `getComputedStyle`, `getBoundingClientRect`, CSSOM) |
| `browser_snapshot` | ❌ Deshabilitada por el usuario durante la sesión |
| `browser_take_screenshot` | ❌ Deshabilitada por el usuario |
| `browser_navigate` | ❌ Deshabilitada → la navegación se realizó con `browser_evaluate` (`location.href`) |
| `browser_hover` | ❌ Deshabilitada → **no se pudo disparar el estado expandido** con un hover real |
| Capturas | Vía **Windows `PrintWindow`** sobre la ventana de Chrome (funciona aunque esté detrás de VS Code) |
| Sesión | La autenticó el usuario manualmente; **el agente no vio, leyó ni almacenó credenciales** |

**Limitación principal:** el sidebar expandido (`.s-sidebar--expanded`, 280 px) **no tiene control visible
en el DOM** y su disparo es por hover real, herramienta que estaba deshabilitada. Se documenta su
especificación por CSSOM (`HECHO`) pero **sin captura visual del estado expandido**.

**Confirmación de que la interfaz es la real y autenticada:**
`location.href = https://pos.alegra.com/#/` · `document.title = "Alegra Punto de venta"` ·
0 campos de contraseña · `document.readyState = complete` · `.app.with-expandable-sidebar` presente.

---

## 3. Evidencia

| Archivo | Contenido |
| --- | --- |
| `docs/design-research/evidence/2026-11-08-alegra-pos-login.png` | Pantalla de login previa (prueba de que se partió de sesión vacía) |
| `docs/design-research/evidence/2026-11-08-alegra-pos-facturacion.png` | **POS autenticado**: rail de iconos, topbar, panel «Factura de venta» |

Clases del producto (BEM propio de Alegra, útiles para futuras mediciones):
`s-topbar`, `s-topbar__actions`, `s-topbar__item`, `s-topbar__item__badge`, `s-topbar__item-menu`,
`s-sidebar`, `s-sidebar--expandable`, `s-sidebar--collapsed|--expanded`, `s-sidebar__header`,
`s-sidebar__body`, `s-sidebar__body-item`, `s-sidebar__body-item--menu(.selected)`.

---

## 4. Estructura medida del layout (HECHO)

Viewport: **1920 × 889**, `devicePixelRatio = 1`.

| Elemento | Posición y tamaño |
| --- | --- |
| `.app.d-flex.flex-column.with-expandable-sidebar` | 0,0 · 1920 × 889 |
| `.s-topbar` | 0,0 · **1920 × 56** |
| `.s-topbar__actions` (visible) | **1375, 8 · 537 × 40** |
| `.s-topbar__actions` (oculta) | 8, 28 · 0 × 0 |
| `.s-sidebar--expandable.sidebar--collapsed` | 0,0 · **52 × 889**, `position: fixed`, `z-index: 40` |
| `.s-sidebar__header` | 0,0 · **52 × 56** |
| `.s-sidebar__body` | 0,56 · 52 × 833 |
| `.main` | 0,56 · 1920 × 833 |
| Panel derecho «Factura de venta» | 1370,56 · **550 × 789**, `border-left: 1px #CBD5E1` |

Lectura clave: **la barra superior no contiene ni título ni botón de menú**. Sus únicos hijos son dos
contenedores de acciones (uno oculto); todo el espacio de x=0 a x=1375 está **vacío**. La identidad y la
navegación viven en el **rail fijo de 52 px**, que se superpone a la barra por `z-index`.

---

## 5. AppBar (HECHO)

| Propiedad | Valor medido |
| --- | --- |
| Alto | **56 px** (`height: 56px`) |
| Fondo | `#FFFFFF` |
| Borde inferior | `1px solid #E2E8F0` (contraste ≈ **1.23 : 1** con el blanco: separador mínimo) |
| Sombra | **ninguna** (`box-shadow: none`) |
| Radio | 0 |
| Padding | 8 px |
| Posición | `static` (no sticky) |
| Tipografía base | **Inter**, 16 px |
| Contenido izquierdo | **vacío** (sin título de módulo, sin hamburguesa, sin logo) |

Cluster derecho de acciones (x = 1375 → 1912, con 8 px de margen derecho):

| Acción | Caja | Detalle |
| --- | --- | --- |
| Píldora «Activa tu POS» | **120 × 28** (y=14) | icono 16×16 `#4F46E5`, borde 1 px, radio 6 |
| Píldora «Disponible» | **101 × 28** | punto de estado 12×12 blanco sobre fondo primario |
| Botones de icono | **32 × 32** (y=12) | regla `.s-topbar__item > button { width:32px!important; height:32px!important }` |
| Botón apps (rejilla) | **40 × 40** (y=8) | el único de 40 px: destaca por tamaño, no por color |
| Píldora de empresa | **157 × 40** (y=8) | avatar + nombre + chevron; `.s-topbar__item-menu { height:40px; radius:6px; padding:8px; gap:8px; border:1px }` |
| Iconos | **20 × 20**, `stroke-width: 1.5`, color `#0F172A` | `fill: none`, `stroke: currentColor` |
| Hover de la píldora | `background: rgba(226,232,240,0.45)` | sin cambio de color de texto |
| Badges | punto **6 px** (10 px «big»); éxito = primario, aviso `#FBBF24`, error `#F43F5E`, info `#4F46E5` | |

---

## 6. Control de navegación lateral (HECHO)

### 6.1 Rail colapsado (estado real observado)

| Propiedad | Valor |
| --- | --- |
| Ancho | **52 px**, altura 100 vh, `position: fixed`, `z-index: 40` |
| Fondo | `#FFFFFF`, **sin borde derecho, sin sombra** |
| Marca | `<img>` **40 × 40** en `(6, 8)`, dentro del header de 52 × 56 (`padding: 14px 6px`) |
| Separador del header | `border-bottom: 1px solid rgba(148,163,184,0.2)` |
| Ítem | `32 × 32`, `border-radius: 8px`, `padding: 6px 8px`, `gap: 8px` |
| Paso vertical | **36 px** (32 + 4) |
| Icono | **16 × 16** renderizado (SVG 24 viewBox), `stroke-width: 1.5`, `fill: none`, `stroke-linecap/linejoin: round` |
| Color del icono inactivo | `#64748B` (contraste **4.76 : 1** sobre blanco ✓) |
| Color del icono activo | `#0F172A` (contraste **≈16.3 : 1** sobre el fondo activo ✓) |
| Fondo del activo / hover | `rgba(226, 232, 240, 0.45)` |
| Indicador del activo | `::before` → **3 × 12 px**, `left: 2px`, `top: 10px`, fondo `primary-600` |
| Transición | `width 0.35s cubic-bezier(0.4, 0, 0.2, 1)` |

### 6.2 Rail expandido

| Regla | Valor |
| --- | --- |
| `.s-sidebar--expandable.s-sidebar--expanded` | **`width: 280px`**, `overflow: visible` |
| ítems al expandir | dejan de forzar 32 px (`:not(.s-sidebar--expanded)` fuerza `width:32px !important; justify-content:center`) |
| Separación de submenú | `padding-left: 16px`, `margin: 4px 0` |
| Scrollbar | `3px` de ancho, fondo transparente |

**No verificable visualmente** (hover deshabilitado). `HECHO` solo por CSSOM.

### 6.3 Tokens de color del producto

| Token | Valor |
| --- | --- |
| `--sm-color-primary-500` | `rgb(48, 187, 183)` → **#30BBB7** |
| `--sm-color-primary-600` | `rgb(48, 171, 169)` → **#30ABA9** (indicador activo) |
| `--sm-color-primary-100` | `rgb(207, 242, 241)` → **#CFF2F1** |
| Texto principal | `#0F172A` / `#334155` (título del panel: `#334155`) |
| Bordes | `#E2E8F0` (barra) y `#CBD5E1` (panel) |

---

## 7. Tipografía (HECHO)

| Uso | Medida |
| --- | --- |
| Familia | **Inter** (`font-family: Inter`), variante «Inter Semibold» para pesos altos |
| Título del panel «Factura de venta» | **18 px / 700**, `#334155`, `letter-spacing: 0.16px`, caja 149 × 29 |
| Cabecera del panel | alto **60 px** (y 56→116) |
| Botones de icono de la cabecera | **40 × 40** (x = 1795, 1835, 1875) |
| Escala general | 12–18 px; sin títulos de más de 18 px en la zona de trabajo |

---

## 8. Sombras, bordes y profundidad (HECHO)

- **Cero sombras** en barra, rail y cabeceras: la jerarquía se resuelve con **bordes de 1 px** y fondos.
- Bordes: `#E2E8F0` (barra, separadores) y `#CBD5E1` (división de paneles).
- El rail **se superpone** a la barra (`position: fixed`, `z-index: 40`) en lugar de convivir en el flujo.
- Radios: 6 px (píldoras de la barra), 8 px (ítems del rail), 9999 px (badges).
- Un único punto de color saturado: el **indicador activo de 3 × 12 px** y el punto de estado.

---

## 9. Animaciones y responsive (HECHO parcial)

- Transición declarada del rail: **`width 0.35s cubic-bezier(0.4, 0, 0.2, 1)`**.
- Animaciones en curso al medir: **0** (`document.getAnimations().length = 0`) → interfaz en reposo, sin
  motion decorativo.
- La hoja de estilos **incluye `prefers-reduced-motion`** → respeta la preferencia del sistema.
- Responsive: no se pudo redimensionar (herramienta `browser_resize` no verificada en esta sesión). El
  layout usa un rail fijo de 52 px y áreas flexibles; en pantallas estrechas el rail no cambia de ancho
  según el CSS leído (`width: 52px` fijo). `HIPÓTESIS`: en móvil el rail podría ocultarse, no verificado.

---

## 10. Comparación con el AppBar de FullPOS (HECHO en ambos lados)

| Aspecto | Alegra POS (medido hoy) | FullPOS Cloud (código actual) |
| --- | --- | --- |
| Alto de la barra | 56 px | 56 px (`kToolbarHeight`) |
| Fondo / borde | `#FFFFFF` / `1px #E2E8F0` | `#FFFFFF` / `1px #9FB6C8` (≈2.1:1, **más marcado**) |
| Sombra | ninguna | ninguna |
| Título de módulo en la barra | **no existe** | `'Facturación'` 17 px / w900 `#111827` |
| Botón de menú en la barra | **no existe** | `_ElegantAppBarMenuButton` **32 × 32**, radio 7, fondo `#1957E6`, glifo 15 × 11 |
| Punto de anclaje de la marca | **logo 40 × 40 en el rail** (`6,8`) | `_DrawerWordmark` solo **dentro** del drawer |
| Navegación | **rail fijo de 52 px** siempre visible | drawer de 318 px bajo demanda |
| Ítem de navegación | 32 × 32, radio 8, icono **16 px**, paso 36 px | ítems de drawer ~40–44 px con texto e icono 22 px |
| Indicador de activo | barra **3 × 12 px** + fondo `rgba(226,232,240,.45)` | sin indicador de ese tipo |
| Iconografía | 1.5 px de trazo, 16 px en rail, 20 px en barra | 20–22 px Material, trazo por defecto |
| Tipografía | Inter 12–18 px; título 18/700 `#334155` | Manrope; título 17/900 `#111827` |
| Densidad del cluster derecho | 28–40 px, gap 4 px, alineado a 8 px del borde | acciones `CashTurnMenuButton`, `SyncStatusMenuButton`, avatar |
| Motion | ancho 350 ms `cubic-bezier(.4,0,.2,1)`; respeta reduced-motion | scale 1.015 / 0.96, 140–180 ms |

**Conclusión de la comparación:** el POS real de Alegra **elimina exactamente los dos elementos que
molestan en FullPOS** (botón azul de hamburguesa + título de módulo) y traslada la identidad al rail fijo.
FullPOS ya tiene la misma altura de barra (56 px), así que el cambio es de **composición**, no de escala.

---

## 11. Recomendaciones para el rediseño del AppBar de FullPOS

`RECOMENDACIÓN` — coherentes con la auditoría previa
(`docs/design-research/2026-11-08-appbar-navegacion-pos.md`):

1. **Adoptar el patrón «marca en el punto de navegación»** (Alegra: logo 40 × 40 dentro del rail). En
   FullPOS, sin rail permanente, el equivalente es el **monograma funcional (Alternativa A)** de 34 × 34
   con `leadingWidth: 46` y `titleSpacing: 8`.
2. **Bajar el peso del título** de 17/w900 a 15/w800 `AppColors.textPrimary`: Alegra usa 18/700 pero **no
   compite con ningún botón de color** en la barra. Si FullPOS conserva el botón de 32 px azul, el título
   en 17/900 es doblemente protagonista.
3. **Sustituir el borde `#9FB6C8` por `AppColors.border` (#DDE7EE)**: el borde de Alegra es ~1.23:1; el de
   FullPOS ~2.1:1 y es uno de los trazos más duros de la pantalla.
4. **Icono de 16 px con trazo 1.5** para el control de menú, o monograma tipográfico a 15 px w900: la
   métrica de Alegra (16 px de icono en una barra de 56) valida que **un glifo pequeño basta**.
5. **Un único indicador de color**: si el menú necesita acento, usar la barra de **3 × 12 px** con
   `AppColors.primary`, no un bloque relleno de 32 px.
6. **Motion**: `width` a 350 ms `cubic-bezier(0.4, 0, 0.2, 1)` y 0 animaciones en reposo. FullPOS puede
   mantener su pulso del FAB, pero el control de navegación debe quedarse en reposo.
7. **Accesibilidad**: Alegra deja el indicador activo con **2.79 : 1** contra blanco (por debajo de 3:1 para
   objetos gráficos) y lo compensa con cambio de fondo y de color de icono. En FullPOS conviene usar
   `AppColors.primary` (#1957E6) como acento: **5.92 : 1** con el blanco.

Lo que **no** conviene copiar: el rail fijo de 52 px tal cual. FullPOS tiene un drawer de 318 px con
etiquetas y jerarquía propia; sustituirlo sería un cambio de navegación, no de estética, y requiere una
fase aparte con autorización.

---

## 12. Elementos verificados realmente

| Verificado | Cómo |
| --- | --- |
| Sesión autenticada | `location.href` en `pos.alegra.com/#/`, título «Alegra Punto de venta», 0 campos de contraseña |
| AppBar | `getComputedStyle` + `getBoundingClientRect` sobre `.s-topbar` y sus hijos |
| Botón/control de menú | Comprobado que **no existe** en la barra; el control es el rail de 52 px con logo de 40 px |
| Drawer contraído | Medido (52 px) y capturado |
| Drawer expandido | Especificación CSS (280 px) — **sin captura**, hover no disponible |
| Iconos | 16 px / 20 px, `stroke-width: 1.5`, colores medidos |
| Tipografía | Inter; 18/700 `#334155`, `letter-spacing: 0.16px` |
| Colores | Tokens `--sm-color-primary-*` leídos del CSSOM |
| Dimensiones y espaciados | Todas las cajas del layout y los pasos de 36 px del rail |
| Sombras y bordes | `box-shadow: none` generalizado; bordes de 1 px medidos |
| Animaciones | `transition: width .35s cubic-bezier(.4,0,.2,1)`; 0 animaciones activas; media query de reduced-motion presente |
| Responsive | **No verificado** (sin herramienta de resize) |

---

## 13. Próximos pasos (requieren autorización)

1. Decidir la dirección del rediseño (A / C / D de la auditoría previa) e implementarla en
   `core/widgets/custom_app_bar.dart` + la variante móvil de `cotizaciones_screen.dart`.
2. Si se quiere el drawer expandido de Alegra como referencia visual, habilitar `browser_hover` y repetir
   solo esa medición.
3. Opcional: medir el comportamiento del rail en 1280 / 900 px habilitando `browser_resize`.
