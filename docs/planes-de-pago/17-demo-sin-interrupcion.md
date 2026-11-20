# 17 — La demo sin interrupciones y la pantalla de Planes en prueba

Fecha: 2026-11-19
Alcance: mensaje de la demo en **Planes** y barra de desarrollo del POS.
No cambia nada del cobro, la licencia ni el servidor.

## 1. La etiqueta que se veía sobre el punto de venta

En la captura del POS durante la demo aparecía, abajo a la derecha, un cuadro
con «DEMO» y un botón «Volver al cuadro». **No es parte de la app del cliente**:
es la barra del *modo demostración de desarrollo* (`_DemoBar` en
`license_expiry_gate.dart`), que solo se construye cuando se arranca con

```
flutter run --dart-define=LICENSE_DEMO_STATE=<escenario>
```

y **nunca** en una compilación de producción (`kDebugMode` es `false`). Sirve
para cambiar de escenario en caliente y para apartar el cuadro de licencia
mientras se recorren las pantallas.

Aun así, para poder enseñar la demo (o tomar capturas) sin ninguna etiqueta, se
añadió un segundo interruptor:

```
--dart-define=LICENSE_DEMO_STATE=TRIAL_EXPIRED --dart-define=LICENSE_DEMO_BAR=false
```

`LicenseDemoScenario.showBar` vale `true` por defecto en desarrollo y `false` en
release. Con `LICENSE_DEMO_BAR=false` el escenario sigue activo pero no se pinta
nada encima del punto de venta.

> Durante la prueba, con la licencia en vigor, `LicenseExpiryGate` devuelve el
> punto de venta **intacto**: no hay banner, ni chip, ni cuadro. La única
> interrupción posible es cuando la prueba ya terminó, y esa es deliberada.

## 2. Pantalla de Planes con el cliente en la demo

Antes se presentaba como «PLAN ACTUAL» con el nombre de la demo y el chip
«Prueba gratis»: parecía un plan contratado.

Ahora, con `status: TRIAL`, se pinta `_TrialState`
(`license_overview_screen.dart`):

- Rótulo **DEMO**.
- Titular: **«Aún no tienes un plan activo»**.
- Una línea: «Te quedan 5 días de prueba.» (según `daysRemaining`; si es 0 o
  negativo, «La prueba termina hoy.»).
- Un único botón: **«Elegir plan»**, que abre el catálogo completo.
- Debajo, el uso de la licencia (usuarios, productos, almacenes) sin cambios.

No se muestra el nombre del plan de la demo, ni la etiqueta «Prueba gratis», ni
la acción «Transferencia» (en la prueba no hay cuota que pagar). En escritorio el
texto y el botón van en la misma fila; en teléfono, apilados.

## 3. Verificación

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze` (planes y licencia) | Sin problemas |
| `plans_sections_test.dart` | 13/13, incluida la nueva prueba del estado de prueba |
| `license_demo_state_test` + `license_expiry_gate_test` + `license_trial_ended_screen_test` | 32/32 (la barra sigue funcionando en desarrollo) |
| `flutter test` completo | Ver informe de la sesión |
| Captura 1280 × 800 de Planes en demo | Revisada |
| Captura 390 × 844 de Planes en demo | Revisada |

Capturas nuevas: `docs/design-research/2026-11-19/1b-plan-demo-pc.png` y
`1b-plan-demo-movil.png`, visibles en el visor como pantalla **13**.

## 4. Pendiente

- Verificar en el **Windows real** con una licencia TRIAL de verdad (la captura
  del POS sigue siendo la de desarrollo, con la barra anotada).
- Decidir si el cliente en demo debe ver el número de días también dentro del
  POS. Hoy no ve nada, que es lo pedido; si se quiere, sería un chip discreto.
- Si se aplica el estilo redondeado a las demás pantallas de Planes (ver
  `16-rediseno-catalogo.md`), este bloque de demo debería seguirlo.
