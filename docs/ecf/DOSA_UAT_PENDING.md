# DOSA — pendientes externos para iniciar la UAT oficial

Este documento separa lo que depende de DOSA o de operaciones de lo que ya está
implementado y probado localmente. No contiene credenciales ni valores reales.

## 1. Credenciales y entorno

| Pendiente | Para qué se necesita | Estado |
| --- | --- | --- |
| `DOSA_SECRET_KEY` de pruebas (`sk_...`) | Abrir sesiones de certificación | Pendiente de DOSA |
| URL base de pruebas | Evitar usar producción en UAT | Pendiente de DOSA |
| Clave maestra / key ring de sesiones | Cifrado en reposo de `session_url` | Pendiente de operaciones |
| `ECF_PORTAL_PILOT_COMPANY_IDS` de UAT | Limitar la prueba a empresas autorizadas | Pendiente de operaciones |
| Cuenta de administrador UAT | Ejecutar la autorización histórica | Pendiente de operaciones |

## 2. Vinculación certificado ↔ RNC ↔ API Key de emisión

Es el punto más delicado y **no se puede inventar**:

| Elemento | Qué debe confirmar DOSA |
| --- | --- |
| Certificado | Si el titular debe ser la empresa (RNC) o el representante legal, y cómo lo valida DOSA |
| RNC | Si la sesión y la postulación quedan ligadas al RNC emisor y qué ocurre si el certificado pertenece a otro RNC |
| API Key de emisión | Si es por empresa, por partner o por entorno; si puede emitir para cualquier RNC o solo para el RNC vinculado |
| Rotación | Cómo rotar la secret key de sesiones y la API Key de emisión sin cortar el servicio |
| Revocación | Qué invalida una sesión o una API Key y cómo se notifica |

Regla interna: FullPOS **no** almacena certificados ni contraseñas. Solo captura
RNC y correo para crear la sesión; el certificado y las credenciales DGII se
capturan dentro del asistente de DOSA.

## 3. Confirmaciones funcionales de DOSA

1. Idempotencia de `POST /api/certificacion/sesiones` por RNC.
2. Límite de sesiones activas por empresa/RNC.
3. Vigencia exacta de `session_url` y si es de un solo uso.
4. Alcance de `postulacion_id` (empresa o global).
5. Códigos de error completos y cuáles son reintentables.
6. Fórmula de `X-Dosa-Signature` para webhooks.
7. Enumeración oficial de estados: distinguir «postulación presentada» de
   «DGII certificó».
8. Allowlist de IPs de origen y formato de la secret key.

## 4. Qué ya está listo localmente

- Cliente de sesiones con fallo cerrado y validación de respuesta.
- Cifrado autenticado de URLs con rotación de claves.
- Guard de expedientes históricos reconciliados.
- Autorización explícita y auditada de una transición.
- Simulaciones de DOSA en pruebas; ninguna llamada real.
- Migración aditiva validada en PostgreSQL desechable.
- E2E de sesión, intención DOSA y compatibilidad del POS tradicional.

## 5. Qué falta exactamente para UAT oficial

1. Respuesta escrita de DOSA a los puntos 2 y 3.
2. Credenciales de sandbox entregadas por un canal seguro.
3. Key ring de cifrado configurado en el entorno de UAT.
4. Migración aplicada en la base de UAT con autorización.
5. Empresa y administrador de UAT autorizados en el piloto.
6. Ventana de prueba y responsable de aceptación.
7. Confirmación de que no se usará emisión real durante la UAT.
