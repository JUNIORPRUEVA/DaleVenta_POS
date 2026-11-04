# DOSA — pendientes externos para iniciar la UAT oficial

Checklist ejecutable y ordenado: `docs/ecf/DOSA_UAT_OFFICIAL_CHECKLIST.md`.

**Reconciliado el 2026-11-04:** la mayoría de los datos de esta lista ya fueron
entregados por DOSA y están en el historial de WhatsApp. Este documento solo
conserva los pendientes reales; no pide de nuevo lo ya entregado. No contiene
credenciales ni valores reales.

## 1. Credenciales y entorno

| Pendiente | Para qué se necesita | Estado |
| --- | --- | --- |
| `DOSA_SECRET_KEY` de pruebas (`sk_...`) | Abrir sesiones de certificación | Entregada en el historial; no configurada |
| URL base de pruebas | Evitar usar producción en UAT | Entregada: `https://dosasystem.com` |
| Clave maestra / key ring de sesiones | Cifrado en reposo de `session_url` | Pendiente de operaciones |
| `ECF_PORTAL_PILOT_COMPANY_IDS` de UAT | Limitar la prueba a empresas autorizadas | Pendiente de operaciones |
| Cuenta de administrador UAT | Ejecutar la autorización histórica | Pendiente de operaciones |

## 2. Vinculación certificado ↔ RNC ↔ API Key de emisión

Es el punto más delicado y **no se puede inventar**:

| Elemento | Estado | Qué falta |
| --- | --- | --- |
| Certificado | Entregado: DOSA lo custodia, firma y transmite; cada RNC se certifica a nombre de la empresa | Verificar con una prueba controlada |
| RNC | Entregado: el RNC del payload debe coincidir con la API Key | Probar el vínculo con RNC `133306001` |
| API Key de emisión | Entregada: una clave TEST por RNC | Configurarla y verificar que es TEST |
| Rotación | No documentada | Confirmar antes de una rotación real |
| Revocación | No documentada | Confirmar antes de una revocación real |

Regla interna: FullPOS **no** almacena certificados ni contraseñas. Solo captura
RNC y correo para crear la sesión; el certificado y las credenciales DGII se
capturan dentro del asistente de DOSA.

## 3. Únicas dudas abiertas

Ya están confirmados el dominio, la fórmula HMAC, el payload de
`empresa.conectada`, la API Key TEST de RNC `133306001`, las secuencias
`113500–115500`, el endpoint de sesiones y el endpoint `EnviarFactura`.

Solo queda por confirmar:

1. Unidad de `t` en `X-Dosa-Signature` (segundos o milisegundos).
2. Si el secreto de 64 hex se usa como texto o como 32 bytes decodificados.
3. URL pública exacta registrada para el webhook (`/webhook/dosa` o
   `/api/webhook/dosa`).
4. Si la clave `sk_...` del ejemplo es la clave TEST vigente de FULLTECH.
5. Sin bloqueo para iniciar: límite de sesiones activas, TTL de `session_url` y
   alcance de `postulacion_id`; se observan en la primera prueba.

## 4. Qué ya está listo localmente

- Cliente de sesiones con fallo cerrado y validación de respuesta.
- Cifrado autenticado de URLs con rotación de claves.
- Guard de expedientes históricos reconciliados.
- Autorización explícita y auditada de una transición.
- Simulaciones de DOSA en pruebas; ninguna llamada real.
- Migración aditiva validada en PostgreSQL desechable.
- E2E de sesión, intención DOSA y compatibilidad del POS tradicional.

## 5. Qué falta exactamente para UAT oficial

1. Resolver las dudas R1–R4 de la sección 3.
2. Configurar en el gestor de secretos UAT las credenciales ya entregadas.
3. Generar el key ring de cifrado y configurarlo en UAT.
4. Aplicar la migración en la base de UAT con autorización.
5. Autorizar empresa y administrador del piloto.
6. Fijar ventana de prueba y responsable de aceptación.
7. Confirmar por escrito que no se usará emisión real durante la UAT.
