# 16 — Rediseño de la pantalla «Catálogo de planes»

Fecha: 2026-11-19
Alcance: **solo la pantalla de catálogo** (`PlansCatalogScreen`). No cambia
lógica, precios, permisos ni llamadas al servidor.

## Qué pedía el cliente

- Menos azul.
- Que no se vea «tan cuadrado».
- Más fino y elegante.
- El mínimo texto posible.
- Que en teléfono también quede bien.

## Qué se cambió

### 1. Tarjetas (`plan_card.dart`)

| Antes | Ahora |
| --- | --- |
| Borde recto de 1 px azul en el plan recomendado | Tarjeta blanca con radio 18 y borde fino gris; el recomendado lleva borde grafito y sombra suave |
| Franja azul «MÁS ELEGIDO» a todo el ancho | Etiqueta pequeña «Más elegido» en la esquina |
| «FULLPOS» + nombre en mayúsculas | Solo el nombre del plan |
| Frase descriptiva por plan (`planSummary`) | Eliminada |
| 6 funciones con checks y texto a 12.5 | 6 en escritorio y 4 en teléfono, texto más contenido |
| Botón recto azul «Cambiar plan a este» | Botón redondeado «Elegir plan»: grafito en el recomendado, contorno gris en el resto y gris plano «Tu plan» en el actual |
| 4 columnas con separación 14 | 4 / 2 / 1 columnas con separación 18 y huecos reservados (un solo plan no se estira a todo el ancho) |

Los tonos nuevos viven en una clase privada `_Ink` dentro de `plan_card.dart`
(grafito `#111827`, texto `#5A6572`, líneas `#E8ECF1`, check `#0F9D6E`). **No**
se tocaron `AppColors` ni el botón `SquareButton`, que siguen usando las demás
pantallas.

### 2. Encabezado (`plans_catalog_screen.dart`)

- Se quita el rótulo «CATALOGO» y el párrafo de tres líneas.
- Queda el título y **una** línea: «Cambia cuando quieras. Tus datos no se tocan.»
- En el camino de mejora: «Sube de plan» + «Planes superiores a Pro.»
- En el plan máximo: «Ya estás en el último plan» y el panel de soporte, ahora
  también con tarjeta redondeada y botón redondeado.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze lib/features/plans` | Sin problemas |
| `flutter test test/features/plans/plans_sections_test.dart` | 12/12 en verde |
| Captura 1280 × 800 (catálogo) | Revisada |
| Captura 390 × 844 (catálogo) | Revisada |
| Solo planes superiores (`?superiores=1`) 1280 × 800 | Revisada: la tarjeta conserva su ancho |
| Panel «último plan» | Cubierto por pruebas (sin excepción de layout); **no verificado visualmente** |

Capturas: `docs/design-research/2026-11-19/2-catalogo-pc.png`,
`2-catalogo-movil.png`, `2b-catalogo-superiores-pc.png` y
`2b-catalogo-superiores-movil.png`. Se ven en el visor
`docs/design-research/2026-11-19/revision-pantallas.html` con el conmutador
PC / Móvil.

## Lo que **no** se tocó

- Lógica de compra, prorrateo, `orderQuoteProvider` ni el paso a pago.
- `AppColors`, `SquareButton`, `PlansPanel` ni las otras tres pantallas
  (plan actual, transferencia, historial), que siguen con el estilo recto.
- La barra superior azul del teléfono: es el color de marca global
  (`CustomAppBar`), no del catálogo.

## Pendiente de decisión del cliente

1. ¿«Elegir plan» es suficientemente claro o prefiere «Cambiar a este plan»?
2. ¿Se echa en falta alguna frase por plan (para quién es cada uno)?
3. Si le gusta este estilo, el siguiente paso es aplicarlo a las otras tres
   pantallas para que la sección quede coherente.
