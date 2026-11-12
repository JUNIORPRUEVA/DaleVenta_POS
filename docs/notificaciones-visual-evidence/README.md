# Aviso de categoría creada: de barra inferior a tarjeta superior derecha (2026-11-11)

## Auditoría

Al crear una categoría desde el formulario de producto (`_createCategoryFromProductForm` en
`features/products/ui/inventory_module_pages.dart`) el aviso se mostraba con
`ScaffoldMessenger.showSnackBar`, es decir, **una barra de una sola línea pegada al borde inferior**
de la pantalla. El mismo patrón se usaba en la pestaña Categorías (`_CategoriesTabState._openEditor`).

Efectos del patrón anterior:

- Aparece abajo, lejos del formulario que el usuario está rellenando.
- Una sola línea con el texto truncado: «Categoría creada: X».
- Se superpone a la barra de acciones del POS (Cobrar / Ventas).

La app ya tiene un sistema propio de avisos: `AppFeedback.showToast` (`core/utils/app_feedback.dart`),
que inserta una tarjeta en el **Overlay raíz** (por encima de todo: diálogos, paneles laterales y
barras), en la **esquina superior derecha**, con icono por tipo, título, párrafo corto, cierre manual,
autocierre y antiduplicados. Es el mismo que usan el resto de avisos profesionales del inventario
(unidad de medida protegida, etc.).

## Solución

1. `_createCategoryFromProductForm`: `AppFeedback.showToast` con `kind: success`,
   título «Categoría creada» y párrafo «La categoría «X» ya está disponible y quedó seleccionada en
   este producto.».
2. `_CategoriesTabState._openEditor`: mismo tratamiento para «Categoría creada» / «Categoría editada».
3. `AppFeedback` (solo la pila de avisos flotantes): margen derecho 24 → **16 px** y separación
   superior 12 → **8 px**, para que la tarjeta quede más pegada a la esquina superior derecha sin
   tapar la barra superior de la pantalla.

## Evidencia visual (Windows UAT, 1280×720)

| Captura | Qué muestra |
| --- | --- |
| `02-antes-dialogo-categoria.png` | Diálogo «Nueva categoría» abierto desde el formulario de producto |
| `01-categoria-creada-arriba-derecha.png` | Tras crear la categoría: tarjeta verde en la **esquina superior derecha**, por encima del panel del formulario, con título, párrafo de dos líneas y botón de cerrar. Sin barra inferior |
