# FULLTECH API (NestJS + Prisma)

## Requisitos
- Node.js 18+ (probado con Node 20)
- Una base de datos PostgreSQL **cloud** ya creada

## Configuración
1) Crear `apps/api/.env` (no se commitea) usando `apps/api/.env.example` como guía.
2) Asegurar `DATABASE_URL` apunta a tu Postgres cloud.

## Despliegue con Docker / EasyPanel
1) Copia variables: `cp .env.docker.example .env.docker` y ajusta secretos.
2) Construye y levanta: `docker compose up --build -d`.
3) La API expone el puerto 4000 y monta un volumen `uploads_data` en `/uploads` para imágenes (ajusta `UPLOAD_DIR`/nombre de volumen si lo cambias).
4) En EasyPanel define `PUBLIC_BASE_URL` con el dominio público HTTPS de la API para que las imágenes sean accesibles desde cualquier dispositivo.
5) El contenedor corre `npx prisma migrate deploy` antes de iniciar `node dist/main.js`.
6) Opcional: para crear/resetear el usuario ADMIN al desplegar, define `RUN_SEED=true` y `ADMIN_PASSWORD` en el entorno (EasyPanel / .env.docker). Esto ejecuta `npx prisma db seed` en el arranque.

### Configuración recomendada en EasyPanel
- Contexto / Root Directory: `apps/api`
- Dockerfile: `Dockerfile`
- Puerto interno: `4000`
- Healthcheck path: `/health`
- Variables obligatorias:
  - `DATABASE_URL` o el grupo `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`
  - `PUBLIC_BASE_URL`
  - `JWT_SECRET`
- Variables recomendadas para evitar arranques frágiles:
  - `MIGRATION_STRICT=false`
  - `REDIS_ENABLED=false` si no tienes un servicio Redis real en EasyPanel
  - `PRODUCTS_SOURCE=LOCAL` hasta que FULLPOS esté configurado

## Troubleshooting: Prisma P3009 (migración fallida en producción)

### Síntoma
- En EasyPanel el contenedor entra en loop y `npx prisma migrate deploy` falla con **P3009**.

### Causa típica
- Existe una migración marcada como *failed* en la tabla `_prisma_migrations` de la DB.

### Ver el error real guardado por Prisma
Prisma no imprime el contenido de `logs` por CLI. Usa el script:

```bash
cd apps/api
node scripts/print-prisma-migration-log.cjs <migration_name>
```

### Resolver el bloqueo sin borrar la DB
1) Verifica si la migración aplicó algo (mira `applied_steps_count` y/o revisa si las columnas/índices existen).
2) Marca correctamente:

```bash
cd apps/api

# Si NO aplicó cambios útiles (applied_steps_count = 0):
npx prisma migrate resolve --rolled-back <migration_name>

# Si SÍ aplicó (o dejó los cambios ya presentes en DB):
npx prisma migrate resolve --applied <migration_name>
```

3) Reintenta deploy:

```bash
cd apps/api
npx prisma migrate deploy
```

### Nota sobre "User" vs "users"
- Algunas migraciones legacy usan la tabla `"User"` porque al inicio del proyecto esa era la tabla creada.
- Más adelante se migra/normaliza a `users` en `prisma/migrations/20260225000000_users_table_compat/migration.sql`.
- Importante: **no edites migraciones ya aplicadas** en una base existente (rompe checksums). Si necesitas mejorar el bootstrap de una DB desde cero, se hace con un baseline/squash planificado.

## Subida de imágenes de productos
- Endpoint: `POST /products/upload` (roles ADMIN/ASISTENTE, header Authorization Bearer).
- Campo: `file` (multipart/form-data), formatos permitidos: PNG/JPG/WEBP, límite 5 MB.
- Respuesta: `{ filename, path, url }` donde `path`/`url` es relativo (`/uploads/<archivo>`). Sirve estático desde `UPLOAD_DIR`.

## Storage (R2 / presigned uploads para Operaciones)

La pantalla **Operaciones Técnico > Gestionar** sube evidencias con este flujo:

1) `POST /storage/presign` (auth) → devuelve `uploadUrl` (presign), `objectKey`, `publicUrl`
2) El cliente hace `PUT uploadUrl` (directo al bucket) con header `Content-Type`
3) `POST /storage/confirm` (auth) → persiste el registro en Postgres
4) `GET /storage/service/:serviceId` → lista/galería

Variables de entorno requeridas (ver también `apps/api/.env.example`):
- `R2_ENDPOINT`, `R2_REGION` (default `auto`)
- `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_PUBLIC_BASE_URL` (ideal: dominio HTTPS público del bucket/CDN)

Opcionales:
- `STORAGE_PRESIGN_EXPIRES_SECONDS` (default 900)
- `STORAGE_IMAGE_MAX_BYTES`, `STORAGE_VIDEO_MAX_BYTES`, `STORAGE_DOCUMENT_MAX_BYTES`

### Nota importante (Web/PWA)
Si el frontend Web hace el `PUT` directo a R2 con `uploadUrl`, el bucket debe tener CORS habilitado para el dominio de la PWA.

Config típico (conceptual):
- **Allowed origins**: `https://TU_PWA_DOMINIO`
- **Allowed methods**: `PUT`, `GET`, `HEAD`
- **Allowed headers**: `Content-Type`
- **Expose headers**: `ETag`

Si no quieres depender de CORS del bucket, puedes servir la API como same-origin vía proxy (`/api`) desde el contenedor de la PWA y mantener el backend bajo HTTPS.

## Comandos (desde la raíz del repo)
- Instalar: `npm install`
- Migraciones (crea/aplica): `npm run api:migrate:dev`
- Migraciones (aplica en prod): `npm run api:migrate:deploy`
- Seed (upsert; crea/resetea ADMIN): `npm run api:seed`
- Dev server: `npm run api:dev`
- Smoke test: `npm run api:smoke`

## Diagnóstico de integridad (usuarios)
Cuando `GET /users` da 500 en producción de forma intermitente, suele ser por datos legacy (NULLs en campos requeridos, roles inválidos, duplicados, etc.) que hacen que Prisma lance errores runtime.

- Endpoint (ADMIN): `GET /admin/diagnostics/users-integrity`
	- Devuelve un reporte con `counts` + `samples` para ubicar los IDs problemáticos.

## Scripts de integridad (Prisma)
Ejecuta estos comandos dentro de `apps/api` o desde la raíz usando workspaces.

- Solo revisar (no cambia nada):
	- `npm --workspace apps/api run integrity:check`
- Aplicar fixes seguros (no borra data):
	- `npm --workspace apps/api run integrity:fix`

Notas:
- El fix normaliza strings vacíos a `NULL` en columnas opcionales.
- Para rellenar `NULL` en campos requeridos con defaults (más agresivo), usa:
	- `ts-node prisma/scripts/fix_integrity.ts --fix --fix-required-nulls`
- No se borran filas huérfanas automáticamente a menos que se habilite explícitamente `--allow-delete`.

## Seed (credenciales)
- `ADMIN_EMAIL` (si no se define, usa `admin@fulltech.local`)
- `ADMIN_PASSWORD` (requerido; define/actualiza la contraseña del ADMIN)
