# Nombre de Facturación en FullPOS IA

20 de noviembre de 2026. Worktree `fullpos-ultimos-ajustes-ia`, rama
`agent/ultimos-ajustes-de-la-ia`. Se conservaron los cambios locales previos.

## Causa y corrección

La ruta interna `/cotizaciones` es el punto de venta visible **Facturación**.
El resolver Flutter y el backend la etiquetaban como Cotizaciones; las ayudas
estáticas la describían únicamente como propuestas. El asistente recibía ese
contexto contradictorio aunque las guías explicaban cómo vender allí.

Se corrigió la etiqueta para Facturación y su alias `/ventas/nueva`; el historial
conserva **Historial de cotizaciones**. El backend normaliza el nombre incluso si
un cliente anterior envía «Cotizaciones». Se conservan ruta, identificador técnico
del módulo, entidad y permisos. No se cambió navegación, venta, cobro ni fiscal.

Facturación prepara tickets/precuentas y permite cobrar o guardar propuestas con
**Cotizar**. Historial de cotizaciones consulta lo guardado; **Pasar a ticket**
vuelve a Facturación y no cobra automáticamente.

## Archivos de esta tarea

- `apps/fulltech_app/lib/core/ai_assistant/presentation/ai_chat_context_resolver.dart`
- `apps/fulltech_app/test/core/ai_assistant/ai_context_coverage_test.dart`
- `apps/api/src/ai-assistant/ai-assistant.service.ts`
- `apps/api/src/ai-assistant/ai-screen-context.spec.ts`
- Este informe.

Los demás cambios de IA que ya estaban en el worktree no se atribuyen a esta
corrección. No se tocaron otros worktrees.

## Evidencias ejecutadas

```text
flutter test test/core/ai_assistant/ai_context_coverage_test.dart
PASS: 7 pruebas; preserva quoteId y separa pantalla/historial.
flutter analyze lib/core/ai_assistant/presentation/ai_chat_context_resolver.dart test/core/ai_assistant/ai_context_coverage_test.dart
PASS: sin incidencias.
npm --workspace apps/api test -- --runInBand src/ai-assistant
PASS: 7 suites y 54 pruebas, incluyendo clientes anteriores y aislamiento existente.
ia_resources_restart_fullpos.py
PASS: npm run api:build y API local saludable con base ficticia aislada.
flutter build web --release --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true --dart-define=APP_ENV=uat --dart-define=API_BASE_URL=http://127.0.0.1:4004/api --dart-define=APP_BASE_URL=http://127.0.0.1:4004
PASS: 86.5 s. Avisos de compatibilidad Wasm de dependencias; build JavaScript exitoso.
ia_billing_names_probe.py
PASS: 3/3 conversaciones reales en API local con OpenAI y contexto de cliente anterior.
ia_billing_preview.cjs
PASS: navegador real envía screenName=Facturación; respuesta permite vender/cobrar
y Cotizar. Captura ia-billing-context-desktop.png inspeccionada visualmente.
git diff --check
PASS.
```

La primera aserción de «cotizar sin salir» rechazó una respuesta correcta que
decía «ya estás en Facturación»; se corrigió la comprobación de equivalencia. Se
fortaleció además la comprobación para impedir que la respuesta llame al POS
«módulo de Cotizaciones». Las tres comprobaciones finales pasaron.

## APPYRA y publicación

El contexto textual de APPYRA reconoce los nombres visibles para `productKey=fullpos`,
manteniendo intactos los identificadores almacenados y otros productos. El catálogo
y la guía fuente se actualizaron. Las tres guías de ventas, precuentas y cotizaciones
se actualizaron y publicaron con respaldo, índice y vectores, sin dejar borradores.
La publicación no cambió configuración, modelos, recursos ni otros agentes.

El conocimiento está publicado; los cambios de código están solo locales. No se
hizo push, merge o deploy, ni se crearon ventas o documentos fiscales de prueba.
GO para prueba local y publicación de esta aclaración de conocimiento. Se mantiene
NO-GO para desplegar sin el proceso y la autorización de publicación de código.
