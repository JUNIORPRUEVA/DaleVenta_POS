# Registro, acceso y bienvenida — 12 de noviembre de 2026

## Alcance aprobado

Transición lateral entre los pasos de registro; selector de nicho centrado;
acceso directo desde Finalizar a la carga normal de Flutter; sustitución del
cuestionario antiguo por la bienvenida y el panel de activación existentes.
No cambian licencias, valores fiscales, endpoints del backend ni migraciones.

## Flujo final

1. Datos de acceso: nombre, correo y contraseña; borrador temporal por pestaña.
2. Datos del negocio: nombre, nicho y WhatsApp; al Finalizar se crean cuenta y empresa.
3. El formulario obtiene el ticket de un solo uso y abre `/home` en Flutter.
   Se muestra el mismo logo del loader de la app, sin navegar por otra página
   Astro de preparación. Los errores permiten entrar con la cuenta ya creada.
4. Flutter muestra «Bienvenido a FullPOS» con el nombre de la empresa.
5. «¡Comencemos!» abre «Activa tu FullPOS». Se puede posponer y retomar desde
   Configuración, sin abrir el cuestionario anterior.
6. Datos empresariales, impuestos, logo y e-CF se completan en las pantallas
   reales de configuración. El progreso se deriva de los datos de activación;
   el campo legacy se mantiene por compatibilidad, sin falsificar COMPLETED.

## Interacción y accesibilidad

- Transición lateral con View Transitions nativas y entrada CSS de respaldo.
- Preferencia de movimiento reducido respetada, sin retardos artificiales.
- Selector `<dialog>` en la capa superior: centrado, buscador, 29 opciones,
  selección visible, cierre con Escape, botón o fondo y retorno de foco.
- La validación enfoca el control visible del nicho; Escape en el selector no
  abre el aviso de abandonar el registro.
- Tipografía de botones del onboarding vinculada a AppTypography; contador de
  la bienvenida y panel calculado con los mismos apartados.

## Referencia de Alegra: alcance real de la inspección

Se consultaron su guía oficial y los fotogramas de su demostración pública:
https://ayuda.alegra.com/int/primeros-pasos-con-el-sistema-punto-de-venta-pos

| Referencia publicada | Aplicación en FullPOS |
| --- | --- |
| Registro separado de los datos empresariales | Dos pasos cortos, sin repetir datos |
| Indicador de la etapa actual | Progreso visible en el último paso |
| Una acción primaria para continuar | Finalizar y después ¡Comencemos! |
| Introducción antes del recorrido | Bienvenida nueva antes del panel |
| Configuración accesible posteriormente | Panel y pantallas reales de Empresa |

Las capturas de la guía muestran un formulario de acceso lateral, una pantalla
centrada de datos empresariales y una introducción al recorrido. Son material
publicado; no prueban el aspecto de una sesión nueva actual.

Se inspeccionaron además el registro actual de Alegra en Chrome y una sesión
de demostración ya abierta en `pos.alegra.com`. El registro presenta nombre,
correo y contraseña, beneficios en la columna izquierda y prueba de 15 días
sin tarjeta. El panel «Activa tu POS» aparece a la derecha, con dos grupos:
«Vende por primera vez» y «Personaliza tu POS», barras de progreso, tareas
desplegables y posibilidad de omitirlas. Incluye productos, primera venta,
métodos de pago, tickets, facturación electrónica y contabilidad. No se
realizaron ventas ni cambios de configuración en esa sesión.

**No se creó una cuenta nueva de Alegra:** el usuario decidió continuar sin
crearla. No se incorporan al código ni a este informe sus credenciales.

## Verificación y límites

Las pruebas de sesión cubren el ticket directo, caducidad de sesión y errores
de handoff. Las pruebas de Flutter comprueban bienvenida → panel en 390×844 y
1280×900, el destino del enlace legacy y navegación de Configuración/permisos.
Se generaron capturas reales del renderizador de widgets para revisar Flutter.

Resultados sobre el código funcional `b216eb07`:

- Astro check sin errores ni warnings; un hint existente de beforeunload.
- Build Astro: 14 páginas; pruebas de sesión Node: 11 aprobadas.
- Flutter analyze sin incidencias; 19 pruebas dirigidas aprobadas.
- Imagen combinada `fullpos-public-web:auth-b216eb07` compilada; Nginx válido.
- Smoke con API/PostgreSQL exclusivamente locales: 9 grupos aprobados,
  incluidos registro, duplicados, login, ticket de un uso bajo concurrencia,
  aislamiento de empresa, rutas, Brotli, 16 recursos y exclusión de tickets
  en logs.
- Chrome real en `127.0.0.1:4016`: registro con datos ficticios → último paso
  → selector centrado → búsqueda «ferreteria» sin acento → selección correcta.
  Reabrir y pulsar Escape cierra solo el selector, conservando la selección.
- Finalizar abrió Flutter con URL sin ticket visible y mostró la bienvenida
  con el nombre real del negocio de prueba. «¡Comencemos!» abrió el panel
  nuevo con 2 de 5 apartados completos y 3 pendientes, sin cuestionario legacy.

La revisión interactiva de Chrome fue de escritorio. Las capturas no miden
la interpolación de la animación; la reducción de movimiento y el selector
Astro en móvil todavía requieren revisión interactiva específica. Las pruebas
de widgets sí cubren bienvenida/panel móvil y escritorio. El login se verificó
por pruebas de sesión e integración, sin repetir su recorrido visual completo.
No se desplegó ni modificó producción.

Documentación primaria consultada para las técnicas usadas:
- https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@view-transition
- https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/dialog
