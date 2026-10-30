# e-CF — Requisitos para acceder al sandbox de Alanube

Worktree `FULLPOS-ECF-ALANUBE`. Fecha: **2026-10-16**.
**No se ha llamado al sandbox ni a producción.** Este documento es la lista de lo que
hay que solicitar antes de poder hacerlo.

---

## 1. Compuerta ya implementada (fail-closed)

`apps/api/src/ecf/alanube/alanube-sandbox-access.policy.ts`, aplicada por la fábrica
de transportes. El transporte **real** solo se construye si se cumple **todo**:

| Condición | Valor exigido |
| --- | --- |
| Interruptor de transporte | `ALANUBE_HTTP_TRANSPORT_ENABLED=true` |
| Interruptor de llamadas reales | `ALANUBE_ENABLE_REAL_CALLS=true` |
| Ambiente | `ALANUBE_ENV=sandbox` |
| URL | `https://` y host exacto `sandbox.alanube.co` |
| Credencial | `ALANUBE_TOKEN_SECRET_REF` con esquema `env://`, `secret://`, `vault://` o `uat://` |

Se **rechaza**: la URL de producción (`api.alanube.co`), infraestructura remota
conocida, HTTP sin TLS, otros hosts y un token escrito en claro. Si algo falta, el
sistema se queda en el **simulador local** en lugar de fallar el arranque.

Configuración actual del entorno de validación (todo apagado):

```
APP_ENV=uat  UAT_LOCAL_ONLY=true
ALANUBE_ENV=sandbox
ALANUBE_ENABLE_REAL_CALLS=false
ALANUBE_HTTP_TRANSPORT_ENABLED=false
ECF_EMISSION_ENABLED=false
```

## 2. Lo que hay que solicitar a Alanube

### 2.1 Credenciales

| # | Elemento | Para qué | Formato |
| --- | --- | --- | --- |
| 1 | **JWT de sandbox** | Autenticar todas las llamadas (`Authorization: Bearer <token>`) | Cadena JWT; se guardará como **referencia** a un secreto, nunca en código ni en logs |
| 2 | Vigencia y política de **rotación** del token | Planificar la renovación sin cortar operación | Documento |
| 3 | Identificador de **compañía** en el sandbox (`companyId`) | Amarrar la empresa UAT con su contraparte en el proveedor | El que devuelva la creación de compañía |
| 4 | **Secreto de firma de webhooks** | Verificar que el evento viene del proveedor | Cadena; se guardará como referencia |

> Nota: el token **no** debe incrustarse en la aplicación ni en el repositorio. En
> FullPOS se maneja por referencia (`EcfSecretResolverService`) y se redacta en logs.

### 2.2 Contratos que necesitamos por escrito

| # | Contrato | Por qué lo necesitamos |
| --- | --- | --- |
| 5 | **Creación de una compañía** (campos obligatorios y respuesta) | Es el paso previo a poder emitir; hoy está enumerado pero no leído |
| 6 | **Emisión E31 / E32 / E34**: ruta, campos obligatorios, códigos de respuesta y errores | Contrastar con nuestro esquema local antes de activar el transporte real |
| 7 | **Consulta de estados** y **consulta de salud** de la API | Reconciliación y monitorización |
| 8 | **Webhooks**: URL de callback exigida, firma, esquema de `general.governmentStatusChanged`, `documents.emissionFinished` y `documents.reception` | Hoy solo tenemos los nombres oficiales |
| 9 | **Set de pruebas** (`reference/createsettest`) y flujo de certificación | Requisito para certificar empresas |
| 10 | Límites de tasa, política de reintentos y **ventana de idempotencia** | Ajustar `alanube-retry.policy.ts` |
| 11 | Procedimiento de **habilitación a producción** (`api.alanube.co`) | Salida de sandbox con criterios claros |

### 2.3 Datos y autorizaciones internas necesarias

| # | Elemento | Responsable |
| --- | --- | --- |
| 12 | Empresa UAT de pruebas con datos **ficticios** (RNC y razón social de prueba) | FullPOS |
| 13 | Autorización explícita para iniciar llamadas al sandbox | Responsable de producto |
| 14 | Confirmación de que el sandbox **no** consume numeración fiscal real | Alanube (por contrato) |
| 15 | Ventana de pruebas y contacto técnico del proveedor | Alanube |

## 3. Cómo se activará (procedimiento, aún no ejecutado)

1. Guardar el JWT como secreto y exponer su **referencia** en `ALANUBE_TOKEN_SECRET_REF`.
2. Poner `ALANUBE_ENV=sandbox` y `ALANUBE_BASE_URL=https://sandbox.alanube.co/dom/v1`.
3. Activar `ALANUBE_HTTP_TRANSPORT_ENABLED=true` y `ALANUBE_ENABLE_REAL_CALLS=true`.
4. Verificar la compuerta: `GET /ecf/provider/status` debe reportar el ambiente
   sandbox y el estado de configuración; si falta la credencial, la fábrica seguirá
   entregando el **simulador** y el motivo aparecerá tipado.
5. Ejecutar **una** operación de prueba y conservar la evidencia (sin secretos).
6. Desactivar los dos interruptores: el simulador local sigue disponible como
   herramienta independiente.

## 4. Salvaguardas que no deben relajarse

- El **simulador local** se conserva como herramienta independiente: no depende del
  token ni de la red.
- Una respuesta 2xx del proveedor **no** es aceptación de la DGII: la cadena acaba en
  revisión humana con evidencia correlacionada.
- Ninguna credencial se registra en logs; el cliente HTTP redacta la cabecera
  `Authorization`.
- La activación productiva exige, además, `productionEnabled` + estado
  `PRODUCTION_READY` y autorización humana auditada.

## 5. Estado

**BLOQUEADO** hasta recibir los elementos 1–15. Todo lo que depende solo de nosotros
(compuerta, cliente, referencias de secretos, simulador, pruebas con mocks) está
implementado y verificado.
