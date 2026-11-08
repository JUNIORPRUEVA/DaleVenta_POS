# Validación funcional de la interfaz e-CF — procedimiento manual

## 1. Por qué este documento

En la sesión de cierre no se pudo ejecutar la automatización de navegador:
`mcp_playwright_browser_navigate` respondió *«currently disabled by the user, and
cannot be called»*. No hubo ninguna interacción de interfaz ejecutada.

**Estado real: UI NO VALIDADA.** Cualquier informe que dijera «PASS» sobre la
interfaz en esta sesión sería falso. Lo que **sí** se validó es el contrato HTTP
que la interfaz consume, con pruebas reales contra PostgreSQL
(`ecf-portal-enroll-http.e2e-spec.ts`, 8 casos) y el servicio del portal
(`ecf-certification-portal.service.spec.ts`, 30 casos).

Este documento es el procedimiento que falta ejecutar, con la evidencia exigida.

## 2. Preparación (una vez)

1. Backend local en `127.0.0.1:4004` apuntando a una base **desechable**.
2. Web compilada con el perfil UAT y verificada:

```powershell
cd apps/fulltech_app
flutter build web --release `
  --dart-define=APP_ENV=uat `
  --dart-define=FULLPOS_UAT_PROFILE=true `
  --dart-define=API_BASE_URL=http://127.0.0.1:4004 `
  --dart-define=APP_BASE_URL=http://127.0.0.1:4004
cd ../..
npm run verify:bundle:env -- --bundle apps/fulltech_app/build/web/main.dart.js `
  --expect-api 127.0.0.1:4004      # debe imprimir VERIFICACIÓN CORRECTA
```

3. Servir la web: `python -m http.server 8080 -d apps/fulltech_app/build/web`.
4. Comprobar el tráfico antes de tocar nada:
   `Get-NetTCPConnection -State Established | Where-Object LocalPort -eq 4004`.
   Si aparece una IP pública, **detener**: el artefacto está mal compilado.

## 3. Casos a ejecutar

Cada caso registra: captura, texto observado y respuesta HTTP asociada.

### Caso 1 — Empresa sin autorización

1. Entrar con un administrador de una empresa sin fila en
   `ecf_portal_enrollments`.
2. Abrir la pantalla de certificación e-CF.
3. **Esperado**: la entrada del asistente **no** aparece, o aparece deshabilitada
   con el motivo «sin autorización». La consola del navegador no muestra errores.
4. **Evidencia**: captura + `GET /ecf/certification-portal/eligibility` con
   `{"eligible": false, "reason": "NO_AUTHORIZATION"}`.

### Caso 2 — Autorizar desde plataforma y volver a entrar

1. Autorizar por API (`POST /ecf/platform/dosa/portal-enrollments/<id>/grant`)
   con `source=ADMIN_AUTHORIZATION` y motivo.
2. Recargar la pantalla **sin reiniciar el backend**.
3. **Esperado**: la entrada aparece habilitada; el motivo ya no es «sin
   autorización».
4. **Evidencia**: captura antes/después + `eligibility` con
   `{"eligible": true, "reason": "ENROLLED"}`.

### Caso 3 — Preparar certificación

1. Pulsar «Preparar certificación».
2. **Esperado**: se crea el Intento 1 y la pantalla muestra el estado del
   intento, sin abrir sesión privada del proveedor.
3. **Evidencia**: captura + `POST /ecf/certification-portal/tickets` → `201` con
   `ticket`.

### Caso 4 — Sesión del portal

1. Continuar hasta abrir la sesión del portal.
2. **Esperado**: se muestra la empresa y el intento; se navega el asistente.
3. **Evidencia**: captura + `POST /ecf/certification-portal/sessions` → `201`.

### Caso 5 — Revocación con sesión abierta

1. Con la sesión del portal abierta, revocar por API
   (`POST …/revoke`).
2. Refrescar la pantalla.
3. **Esperado**: el portal rechaza la sesión viva (no se puede seguir operando) y
   la interfaz lo explica; no queda una pantalla en blanco ni un bucle de
   reintentos.
4. **Evidencia**: captura + código/`reason` devuelto.

### Caso 6 — Responsive y estados

1. Repetir el Caso 1 en 1280×800 y 390×844.
2. **Esperado**: sin desbordes, sin texto truncado, botones con área táctil
   suficiente, estados de carga y error visibles.

## 4. Criterio de cierre

- Los 6 casos con evidencia adjunta → **UI VALIDADA**.
- Un caso sin captura o sin la respuesta HTTP asociada → **NO VALIDADA**.
- Cualquier petición del artefacto a un host que no sea `127.0.0.1:4004` →
  **NO-GO**, aunque la pantalla se vea bien.
