# Postulación DGII — Incremento 1: documentos del expediente

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-19**.

> Este incremento **no** envía nada a Alanube ni a la DGII. `isInternalTrackingOnly`
> sigue en `true` y la emisión real sigue bloqueada. Lo que se añadió es el flujo
> documental real que faltaba para que el cliente pueda construir su expediente.

## 1. Qué se implementó

| Pieza | Archivo |
| --- | --- |
| Validación por contenido | `apps/api/src/ecf/dgii/ecf-dgii-document.policy.ts` |
| Almacenamiento privado | `apps/api/src/ecf/dgii/ecf-dgii-document.storage.ts` |
| Servicio de carga/descarga | `apps/api/src/ecf/dgii/ecf-dgii-documents.service.ts` |
| DTO de carga | `UploadEcfDgiiDocumentDto` en `dto/ecf-dgii.dto.ts` |
| Rutas | `POST /ecf/dgii/documents`, `GET /ecf/dgii/documents/:id/file` |
| Pruebas | `ecf-dgii-document.policy.spec.ts` (10) |

**Se reutiliza `ecf_evidences`.** No se creó una tabla paralela: la evidencia ya
tenía empresa, procedencia, hash, estado de revisión y autor. Lo que faltaba era
poder **subir y descargar el archivo** de forma segura.

## 2. Propiedades de seguridad (verificadas)

| Riesgo | Mitigación |
| --- | --- |
| Archivo con extensión mentirosa | El tipo se decide por **magic bytes** (`%PDF`, `\x89PNG`, `\xFF\xD8\xFF`, `<?xml`) |
| MIME declarado falso | Si no coincide con el contenido real → `ECF_DGII_DOCUMENT_MIME_MISMATCH` |
| Nombre malicioso (`../../etc/passwd`) | Se conserva solo el basename, sin controles, máx. 180 caracteres |
| Path traversal en la lectura | La ruta resuelta debe quedar dentro de la raíz (`root + sep`) |
| Acceso entre empresas | Búsqueda acotada por `companyId`; un id ajeno responde **404** igual que uno inexistente |
| Doble clic / reintento | Misma empresa + misma clase + mismo SHA-256 → devuelve la evidencia existente (`duplicate: true`) |
| Tamaño abusivo | Límite 5 MB en la política y en el interceptor |
| Fuga de rutas internas | `storageRef` nunca se devuelve al cliente; un archivo ausente responde `ECF_DGII_DOCUMENT_FILE_MISSING` |
| Almacenamiento público | Ruta privada configurable (`ECF_DGII_STORAGE_DIR`), archivos `0o600`, sin carpeta estática |

**La carga nace como `MANUAL_DECLARATION`.** Nunca se convierte en
`DGII_OFFICIAL_RECORD` por subir un archivo: la promoción sigue siendo un acto
aparte, con permiso propio (`recordEcfDgiiOfficialVerification`) y evidencia
revisada.

## 3. Permisos

| Ruta | Permiso |
| --- | --- |
| `POST /ecf/dgii/documents` | `manageEcfOnboarding` o `registerEcfDgiiEvidence` |
| `GET /ecf/dgii/documents/:id/file` | `viewEcfOnboarding` o `viewEcfDgiiHabilitation` |

## 4. Evidencia ejecutada

```text
npx tsc -p tsconfig.build.json --noEmit      -> exit 0
ecf-dgii-document.policy.spec.ts             -> 10/10
run-focused.ps1 -Pattern ecf-dgii            -> 5 suites / 65 pruebas, 0 fallos
```

## 5. Qué falta (y por qué)

| # | Pendiente | Motivo |
| --- | --- | --- |
| 1 | Asistente Flutter por pasos (empresa → requisitos → documentos → resumen → seguimiento) | Trabajo de UI pendiente; el backend ya expone lo necesario |
| 2 | Panel administrativo Fulltech multiempresa | Requiere permisos de plataforma y una vista fuera del ámbito de empresa |
| 3 | Snapshot versionado de la solicitud | Necesita tabla propia y migración; no se creó para no inventar el modelo antes de definir el contrato del proveedor |
| 4 | Adaptador Alanube (`POST /company`) | **Bloqueado**: falta la respuesta del proveedor sobre campos, facultades y custodia de certificados |
| 5 | Webhooks de habilitación | **Bloqueado**: no está documentado que existan para certificación |
| 6 | Notificaciones | Depende de los estados que produzca el adaptador |

## 6. Regla que no se rompió

Ninguna parte de este incremento puede declarar una empresa habilitada. Subir
documentos, revisarlos y aprobarlos internamente **no** produce autorización
oficial; `APPROVED` sigue exigiendo registro oficial verificado.
