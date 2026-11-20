# Seccion Planes: cuatro pantallas con indice

Fecha: 2026-11-16 · Worktree `C:\src\fullpos-planes-de-pago-impl`

## Como verlas

```powershell
cd C:\src\fullpos-planes-de-pago-impl\apps\fulltech_app
flutter run -d chrome -t lib/features/plans/preview/plans_preview.dart
```

El preview (`lib/features/plans/preview/plans_preview.dart`) monta las **cuatro pantallas reales** con
datos ficticios y su propio `GoRouter`: se navega con el indice de la izquierda (escritorio) o con las
pestanas (telefono). No llama al backend: los providers estan sobrescritos.

## Las cuatro pantallas

| # | Ruta | Pantalla | Que muestra |
| --- | --- | --- | --- |
| 1 | `/planes` | **Resumen (Plan actual)** | **Cambia segun el estado**: activa → plan, estado, precio, vencimiento y **tres botones** (cambiar a plan superior · transferencias · historial); en prueba → «Elegir plan»; vencida/suspendida → «Tu plan esta suspendido por falta de pago» con **Transferir y subir comprobante** como accion principal, upgrade pequeno e historial |
| 2 | `/planes/catalogo` | **Planes** | Las cuatro tarjetas con precio del catalogo, funciones incluidas y **no incluidas** (tachadas), banda «MAS ELEGIDO» y el boton que genera la orden. Con `?superiores=1` **solo muestra los planes mas caros** que el actual |
| 3 | `/planes/pago` | **Transferencia** | Referencia copiable, monto, datos bancarios, subida del comprobante, cancelar orden y los tres pasos del proceso |
| 4 | `/planes/historial` | **Historial** | Todas las ordenes con su estado (esperando, en revision, pagada, vencida) y si tienen comprobante |

`/licencias` redirige a `/planes` para no romper enlaces guardados.

## Archivos

```
lib/features/plans/
  data/plans_repository.dart
  presentation/
    plans_shell.dart                 # barra superior + indice de opciones
    screens/
      license_overview_screen.dart   # 1 - resumen
      plans_catalog_screen.dart      # 2 - catalogo
      payment_screen.dart            # 3 - transferencia
      orders_history_screen.dart     # 4 - historial
    widgets/
      plan_ui.dart                   # boton recto, chip, panel, formatos, tonos
      plan_card.dart                 # tarjeta de plan + rejilla
      plans_action_mixin.dart        # confirmar / avisar / bloquear doble clic
  preview/plans_preview.dart         # datos ficticios + router de las 4
```

## Diseno

- **Todo recto**: botones, tarjetas, chips y pestanas sin radio (tambien en el CRM).
- Indice de opciones visible siempre: lista lateral en escritorio, `Wrap` de pestanas en telefono
  (las cuatro caben, sin etiquetas cortadas).
- Paleta de la app (`AppColors`), precios desde el servidor, ningun importe escrito en la app.
- Los botones de las tarjetas quedan alineados al pie en los cuatro planes.
- **El estado manda**: la misma pantalla decide que mostrar (activa, en prueba o suspendida) y que
  accion ofrecer primero. Nunca se le ofrece un upgrade a quien ya esta en el plan mas alto: avisa y
  ofrece una excepcion.

## Menu y POS

- En el menu del punto de venta la entrada ya no se llama «Licencias» sino **«Plan actual»**.
- El panel lateral del POS abre con el titulo «Plan actual» y, debajo del detalle, muestra las mismas
  acciones por estado (tres botones si esta activa; transferencia + upgrade pequeno si esta
  suspendida).

## Estados de la vista previa

La barra inferior «VISTA PREVIA» alterna entre **activo** y **suspendido** sin tocar el backend.

## Verificacion

| Comprobacion | Resultado |
| --- | --- |
| `flutter analyze lib` | **No issues found** |
| `flutter test test/features/plans/plans_sections_test.dart` | **5/5** — estado activo con tres acciones, filtro de upgrade (solo planes superiores), pantalla de suspension, navegacion por el indice y 390 px sin desbordes |
| Capturas reales (navegador, app web) | `docs/design-research/2026-11-16/`: `planes-1-resumen.png`, `planes-2-catalogo.png`, `planes-3-transferencia.png`, `planes-4-historial.png`, `planes-5-movil.png` |
