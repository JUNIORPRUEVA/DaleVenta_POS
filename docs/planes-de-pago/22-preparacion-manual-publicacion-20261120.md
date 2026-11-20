# Preparación manual de publicación — IA, planes y cobros

Fecha: 20/11/2026. Worktree propio: `C:/src/fullpos-integrate-ia-planes-20261119`.
Rama: `agent/integrate-ia-planes-20261119`.

Este documento prepara acciones revisables; **no autoriza ni ejecuta producción**.
Se mantiene el NO-GO de despliegue. No se hizo push, merge a production-main,
reinicio, migración, seed, cambio de entorno, concesión comercial ni envío real.

## 1. Qué se preparó

1. Generador offline de manifiesto con el commit limpio, siete migraciones
   pendientes exactas, hashes de sus archivos y las imágenes de reversión.
2. Configuración propuesta de cobros y persistencia, sin números de cuenta ni
   secretos: [configuracion-propuesta-20261120.json](configuracion-propuesta-20261120.json).
3. Adaptación opt-in del OCR al contrato de trabajos de APPYRA. El protocolo
   síncrono anterior y el worker CLI mantienen su comportamiento.
4. Procedimiento manual con puntos de parada, sin backfill ni cambio automático
   de condiciones para los clientes vigentes.
5. Subida por bytes en navegador, conservando la ruta de archivo en aplicaciones
   nativas y el límite de 8 MB. No se consulta file.path en web.
6. Espera exclusiva para comprobantes: envío 45 s, recepción 150 s y límite
   exterior 210 s. Las demás consultas conservan 20 s. No se repite el POST
   automáticamente y no se actualiza la pantalla después de cerrarla.

Fuente de la auditoría actual:
[21-auditoria-produccion-solo-lectura-20261120.md](21-auditoria-produccion-solo-lectura-20261120.md).
Las pruebas de integración previas permanecen en el informe 20. No se atribuyen
esas ejecuciones antiguas a una comprobación productiva nueva.

## 2. OCR: causa real y corrección local

El adaptador HTTP existente enviaba `mode=ocr` a `/v1/media/ocr` y esperaba
`{text}` en la misma respuesta. La API de APPYRA consultada en su repositorio
expone otro contrato:

- `POST /v1/media`: multipart con archivo y campos declarados; devuelve 202 y jobId.
- `GET /v1/media/:jobId/result`: estado y resultado normalizado del trabajo.
- Las rutas requieren autenticación y los scopes media:submit / media:read.

La adaptación se selecciona con `APPYRA_MEDIA_OCR_PROTOCOL=appyra-jobs`.
No se cambia el modo de ninguna instalación automáticamente. Envía un solo POST,
elige extracción de imagen o documento según MIME, declara allowExternal=false,
consulta únicamente el trabajo recibido y aplica un tiempo total limitado.
No sigue redirecciones ni acepta identificadores arbitrarios como una URL.

Solo devuelve texto si el trabajo y su capacidad coinciden, está COMPLETED,
declara cero llamadas externas y contiene texto. Una lectura OCR sigue siendo
información no confiable: no confirma por sí sola una transferencia. Se mantienen
la validación bancaria y la activación provisional existentes.

El token corresponde a la integración de la empresa que cobra suscripciones,
no al RNC/certificado/DOSA de los clientes. No usar LICENSE_ADMIN_SECRET como
token OCR. No activar LICENSE_EVIDENCE_TEST_ACTIVATE en producción.

### Fuente contrastada de APPYRA, sin editar ese proyecto

Repositorio leído: `C:/Users/pc/DEV/PROYECTOS/INTERNO/APPYRA_AI`, revisión observada
`7fc0ed6`. Se revisaron MediaController, SubmitMediaDto, MediaJobView/MediaResultView,
el SDK `sdk/appyra-media-client/index.mjs` y la configuración Docker/media.
El SDK privado ESM no está distribuido como dependencia del backend FullPOS;
no se añadió una ruta que dependa de otro worktree para ejecutar el producto.
La adaptación limitada conserva OcrEngine como frontera de integración existente.

En el servidor se localizaron servicios APPYRA existentes. La comprobación de
solo lectura confirmó para `ventas_appyra-ia`: health HTTP200, controlador de media,
worker y Python presentes. El health también respondió desde el contenedor de
FullPOS por la red interna. Esto permite proponer `http://ventas_appyra-ia:4400`;
no sustituye un token autorizado ni una prueba funcional de OCR.

**No se subió ningún archivo al APPYRA productivo.** La presencia de Python/worker
y health no acredita calidad OCR, modelos cargados, permisos ni el alcance del
token. Esas verificaciones quedan para una fase expresamente autorizada.

## 3. Manifiesto offline

Herramienta: `scripts/ops/prepare-plans-release.cjs`.

- Solo lee Git, SQL originales y JSON de auditoría ya obtenidos.
- No contiene modo Apply ni llamadas SSH, Docker, Prisma o servicios externos.
- Exige un worktree limpio y obtiene los SQL desde los blobs del commit.
- Se detiene si cambia la lista exacta de pendientes, existe un intento sin
  resolver o hay una diferencia histórica distinta de LF/CRLF.
- Excluye intentos revertidos al comparar el historial exitoso.
- Exige digests inmutables de reversión y hashes de configuración protegida.
- No exporta empresas, contactos, licencias ni valores de entorno.
- No sobrescribe un manifiesto existente.

Ejemplo de generación **local** después del commit limpio:

```powershell
node scripts/ops/prepare-plans-release.cjs `
  --snapshot C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/production-license-readonly.json `
  --runtime C:/Users/pc/.codex/backups/fullpos-prepublish-readonly-20261120/runtime-before.json `
  --out-dir C:/Users/pc/.codex/backups/fullpos-release-preparation-20261120/paquete
```

El resultado es un manifiesto para revisión, no SQL aplicado ni una autorización.
Antes de ejecutar cualquier operación productiva debe repetirse la auditoría:
un manifiesto del 20/11 no demuestra que otro día el servidor siga igual.

## 4. Configuración que se revisará antes de aplicar

La cuenta oficial ya fue confirmada por el propietario. Preparar su registro
explícito con los mismos datos de Planes; no inventar otra ni incluirla en Git.

La ruta de evidencias propuesta es privada y persistente. Agregar un volumen
dedicado sin sustituir montajes existentes. Si la ruta ya tiene archivos cuando
se vaya a intervenir, detenerse y preparar su respaldo/traslado verificado;
un montaje vacío no debe ocultar comprobantes ya guardados.

Para OCR, configurar el destino interno propuesto, protocolo de trabajos y token
de integración con permisos mínimos, verificando empresa y vencimiento. No usar
127.0.0.1 para acceder desde FullPOS a otro contenedor.

Para WhatsApp se observó una integración existente en APPYRA CRM. Su presencia
no autoriza copiar secretos, cambiar emisor ni enviar mensajes. Antes de enlazar
credenciales, preparar dry-run explícito y confirmar el emisor autorizado.

Conservar los permisos fiscales y la configuración actual de cada empresa.
Mantener las migraciones automáticas y el seed general desactivados.

## 5. Secuencia manual propuesta — no ejecutada

### A. Publicación de código

Publicar únicamente esta rama y abrir PR contra origin/production-main tras
autorización. Comprobar los controles del commit final; no ejecutar merge
automático. La rama local antigua llamada production-main no se utiliza como base.

### B. Preparación de artefactos y reversión

Construir fuera del host productivo desde el commit aprobado y limpio.
Verificar el cliente Prisma, contenido fiscal, módulos IA/planes y contrato
API/PWA. Publicar imágenes inmutables solo con autorización. El manifiesto
conserva las imágenes actuales como reversión; el digest candidato aún debe
obtenerse de una construcción verificada, no inventarse.

No usar los scripts antiguos e-CF con ExpectedCount=25 o imágenes latest para
estas siete migraciones. No reutilizar la imagen incompleta que causó la regresión
anterior del backend.

### C. Respaldo y migraciones manuales

Con autorización específica y ventana acordada:

1. Repetir el snapshot de esquema/licencias y comprobar que el alcance coincide
   con el manifiesto. Si aparece una nueva migración, intento fallido o cambio de
   condiciones, detenerse y revisar; no reparar el historial automáticamente.
2. Preparar un respaldo completo y registrar tamaño/checksum y destino protegido.
   `pg_restore --list` solo comprueba que el índice es legible: no equivale a
   demostrar restauración. El ensayo de restauración requiere un destino aislado
   aprobado; nunca restaurar encima de la base productiva como verificación.
3. Aplicar las siete migraciones originales mediante un trabajo manual separado
   de la API, desde el artefacto revisado. Usar límites de bloqueo y tiempo para
   detenerse si existe actividad incompatible; no cambiar RUN_MIGRATIONS a true.
4. Verificar esquema e historial y ausencia de intentos fallidos. No reescribir
   los 43 checksums CRLF ni eliminar las migraciones históricas fuera del árbol.
5. Comparar estado, vencimiento, cupos y configuración de las licencias existentes.
   La numeración fiscal no se reinicia ni se reutiliza. Si hay emisiones legítimas
   durante la ventana, sus contadores pueden avanzar; nunca deben retroceder.

No hay respaldo ni migración productiva ejecutados por este procedimiento todavía.

### D. Catálogo y clientes existentes

Autorizar por separado la inicialización del catálogo. El seed específico existente
usa upsert y puede actualizar precios/cupos de filas existentes: **no** se ejecuta
sin revisar que el catálogo está vacío y que nadie lo inicializó desde la auditoría.
No activar el seed general ni el backfill de clientes.

Los siete clientes vigentes conservan sus condiciones previas. Para su futura
renovación debe acordarse plan y concesiones individualmente; no asignar Básico
por defecto ni deducir su contrato solo del uso actual.

### E. Configuración y despliegue

Aplicar únicamente los ajustes de volumen/cobros/integraciones aprobados,
conservando los demás campos. El propietario mantiene la decisión de desplegar.
No emitir facturas fiscales ni enviar WhatsApp reales como smoke test.

Tras despliegue autorizado: salud, autenticación, siete licencias vigentes,
lecturas de planes y acceso fiscal por empresa; sin crear pagos/ventas reales.
Si una licencia pierde condiciones o falta una capacidad fiscal, detener y volver
al artefacto anterior aprobado. La reversión de imagen no deshace datos ni
autoriza revertir pagos o borrar estructura automáticamente.

## 6. Validaciones de esta preparación

| Comprobación | Resultado |
| --- | --- |
| `npm run api:build` | PASS, Prisma y TypeScript |
| `npm --workspace apps/api test` | 261 suites / 3.036 PASS; 57 suites / 594 pruebas opt-in omitidas |
| Suite `src/license/evidence/ocr.engine.spec.ts` | 13 PASS, HTTP real en loopback; respuestas OCR simuladas |
| `node --test scripts/ops/prepare-plans-release.test.cjs` | 6 PASS |
| TypeScript estricto de las pruebas nuevas, configuración privada noEmit | PASS |
| `flutter analyze --no-pub` | PASS, sin incidencias |
| Suite `test/features/plans/plans_evidence_upload_test.dart` | 3 PASS: bytes, respuesta a los 30 s sin repetir POST y ruta nativa |
| Regresión Flutter de planes, chat y repositorio e-CF | 112 PASS |
| `flutter build web --release --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:4000` | PASS, 84,2 s de compilación; artefacto exclusivamente local |

No se vuelven a atribuir a este cambio las pruebas completas Flutter de la fase
anterior. El diseño no se modificó; se corrigió el transporte del comprobante.
No se subió ningún archivo al APPYRA productivo ni se envió WhatsApp.

Logs y comprobaciones fuera de Git:
`C:/Users/pc/.codex/backups/fullpos-release-preparation-20261120/`.

Archivos de esta fase: `apps/api/.env.example`, `ocr.engine.ts` y su prueba,
`plans_repository.dart`, `payment_screen.dart`, `plans_evidence_upload_test.dart`,
el generador `scripts/ops/prepare-plans-release.cjs` y su prueba, este informe y
`configuracion-propuesta-20261120.json`.

Estado: GO para preparación local y revisión; producción sigue NO-GO hasta
completar permisos, configuración, artefactos y verificaciones correspondientes.
El manifiesto final se genera fuera de Git a partir del commit limpio y conserva
el digest de reversión y los siete hashes SQL. No contiene credenciales ni una
autorización implícita de aplicación.
