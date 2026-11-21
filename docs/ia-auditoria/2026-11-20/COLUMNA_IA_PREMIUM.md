# Columna de FullPOS IA: diseño local y comprobaciones

20 de noviembre de 2026. Worktree `C:/src/fullpos-ultimos-ajustes-ia`, rama
`agent/ultimos-ajustes-de-la-ia`. Se conservaron los cambios anteriores.

## Comportamiento final comprobado

- Dos accesos superiores: Reportar una avería y Soporte humano. Se retiraron los
  accesos a explicación de pantalla, capacidades y normas del manual; las preguntas
  siguen disponibles escribiendo al asistente.
- La IA no muestra automáticamente una tarjeta central de contacto. El acceso
  superior de soporte abre únicamente el canal oficial existente, por decisión del
  usuario, con un texto genérico preparado. No envía mensajes, no transmite el chat
  completo y no asegura que un operador ya esté conectado. Si no puede abrirse,
  conserva la alternativa de copia y presenta un aviso breve dentro de la columna.
- Fondo de cristal con desenfoque real de 9px y ondas de marca muy tenues. La
  primera propuesta azul opaca se descartó tras la corrección del propietario.
- Bienvenida breve cuando todavía no existe conversación. Se oculta el mensaje
  introductorio anterior de la presentación, sin alterar el historial enviado.
- Mensajes del cliente en azul con texto blanco y respuestas claras en superficie
  blanca, con entrada suave. Burbuja animada de escritura mientras responde la API.
- Sonido breve en navegador mediante Web Audio y feedback del sistema en nativo.
  Puede silenciarse; la elección se conserva al cerrar/reabrir el panel en la misma
  sesión de la aplicación. No requiere una dependencia nueva ni archivos remotos.
- Movimiento reducido respetado. Controladores de animación y audio se liberan al
  cerrar. Formulario de avería y recursos siguen dentro del Navigator de la columna.
- Los avisos de archivos se muestran con lenguaje comprensible; esto no configura
  ni repara el motor de archivos del backend.

El último mensaje del propietario llegó incompleto en «la columna de…». No se
aplicó una nueva decisión de ancho ni se retiró el acceso superior de soporte a
partir de esa frase incompleta. Se solicitó aclaración.

## Archivos de esta intervención visual

- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_focus_backdrop.dart`
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_chat_experience.dart`
- `apps/fulltech_app/lib/core/ai_assistant/data/assistant_feedback_sound.dart`
- `apps/fulltech_app/lib/core/ai_assistant/data/assistant_feedback_sound_native.dart`
- `apps/fulltech_app/lib/core/ai_assistant/data/assistant_feedback_sound_web.dart`
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_sheet_composer_test.dart`
- Referencias `assistant_1280.png`, `assistant_390.png`, `assistant_button.png` y
  `assistant_dock.png` en `test/core/ai_assistant/goldens/` y su carpeta `linux/`.
- Este informe. No se atribuyen a esta intervención los demás cambios previos del worktree.

## Validaciones ejecutadas

```text
flutter analyze --no-pub lib/core/ai_assistant test/core/ai_assistant/ai_assistant_sheet_composer_test.dart
PASS: sin incidencias.
flutter test --no-pub test/core/ai_assistant/ai_assistant_sheet_composer_test.dart --update-goldens
PASS: 17 pruebas, referencias Windows actualizadas.
flutter test --no-pub test/core/ai_assistant
PASS: 49 pruebas Windows, sin actualizar referencias.
flutter build web --release --no-pub --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true --dart-define=APP_ENV=uat --dart-define=API_BASE_URL=http://127.0.0.1:4004/api --dart-define=APP_BASE_URL=http://127.0.0.1:4004
PASS: build UAT local. Avisos Wasm existentes de dependencias; JavaScript generado.
```

En un fixture Linux propio y separado, sin copiar credenciales, con imagen
`ghcr.io/cirruslabs/flutter:3.41.6`:

```text
flutter test --no-pub test/core/ai_assistant/ai_assistant_sheet_composer_test.dart --update-goldens
PASS: 17 pruebas; referencias Linux actualizadas y copiadas al worktree.
flutter test --no-pub test/core/ai_assistant
PASS: 49 pruebas, red del contenedor deshabilitada.
```

Playwright con Chrome y bases ficticias locales:

- `ia_premium_desktop.cjs`: PASS, 1280×900, dos accesos, ausencia de tarjeta central,
  apertura del destino oficial por clic explícito sin envío, respuesta real de OpenAI,
  escritura visible, AudioContext running con dos tonos iniciados, silencio sin
  nuevos tonos y conservación del silencio al reabrir. Sin errores de página.
- `ia_premium_mobile.cjs`: PASS, 390×844, contexto de navegador aislado tras completar
  la sesión, bienvenida y formulario de avería dentro del viewport. No envió un caso.
- `ia_premium_open.cjs`: vista local visible y chat listo para revisión del propietario.
  Captura de bienvenida de escritorio y móvil inspeccionadas visualmente.
- `git diff --check`: PASS.

Los primeros intentos del script combinado fallaron por un selector que separaba
un texto semántico compuesto y por abrir la hoja antes de finalizar la sesión móvil
en un contexto compartido. Se inspeccionaron DOM y capturas. La escritura estaba
presente; se corrigió el selector y se comprobó móvil en sesión aislada ya iniciada.
No se atribuye una corrección de navegación del producto a esos cambios del harness.

## Límites y estado

No hubo cambios de producción, backend, fiscal, licencias, modelos o credenciales,
ni push, merge, deploy o notificaciones externas. Los mensajes de prueba y datos
son locales; las respuestas de texto sí llamaron a OpenAI.

No se verificó audición física de altavoces, aplicaciones nativas Android/iPhone,
ni continuidad de una hoja durante redirecciones de autenticación. El motor de
archivos del laboratorio conserva su configuración; un aviso mejorado no prueba
su disponibilidad.

GO para revisión visual y prueba local de este diseño. El despliegue sigue pendiente
de autorización y revisión del conjunto de cambios anteriores. Falta completar la
indicación del propietario sobre «la columna de…».
