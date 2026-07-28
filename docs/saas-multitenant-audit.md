# Auditoria SaaS Multiempresa - DaleVenta POS

Fecha: 2026-07-28

## 1. Estructura Actual

- Backend: NestJS + Prisma + PostgreSQL.
- Frontend: Flutter con auth por JWT y `AuthState`.
- Modelo actual tiene `Company` y muchos modelos operativos con `companyId`.
- Modelo actual todavia usa `User.companyId` y `User.role` como fuente principal de empresa/rol.
- Storage R2 ya existe con rutas separadas por `uploads/companies/{companyId}/...`.
- `requireTenant()` obtiene `companyId` desde `request.user.companyId`.

## 2. Riesgos Detectados

- No existia `CompanyMember`, por lo que un usuario no podia pertenecer formalmente a varias empresas.
- El rol era global en `User.role`, no por empresa.
- `companyId` venia del JWT basado en `User.companyId`; esto es compatible, pero insuficiente para SaaS multiempresa.
- Hay modelos con `companyId` opcional que deben auditarse antes de volverlos obligatorios.
- Hay consultas `findUnique`, `update`, `delete`, `groupBy` y jobs que deben revisarse por tenant antes de declarar aislamiento completo.
- Hay caches/frontend con nombres `fulltech_*` que deben migrar a namespaces por empresa.
- Hay endpoints publicos y administrativos que deben separarse de los empresariales.

## 3. Modelos Sin Tenant Directo o Con Tenant Indirecto

Ejemplos detectados para auditoria profunda:

- `CompanyMember` no existia antes de esta fase.
- `ServiceOrder`, `ServiceEvidence`, `ServiceReport`, `ServiceFile` no tienen `companyId` directo; dependen de relaciones padre.
- Varias tablas hijas dependen del padre para seguridad, lo cual puede ser correcto si todos los accesos verifican el padre.
- Algunos modelos ya tienen `companyId` opcional: productos, clientes, ventas, caja, compras, contabilidad, cotizaciones, scheduling, IA.

## 4. Endpoints y Consultas a Revisar

Prioridad alta:

- `users.service.ts`: hay operaciones por `id` que deben validar pertenencia a empresa.
- `work-scheduling.service.ts`: contiene consultas globales y `findUnique` por fecha/usuario que requieren scope por empresa.
- `notifications/*`: jobs y listeners deben validar empresa antes de enviar.
- `sales`, `reports`, `cash`, `products`, `clients`, `purchases`, `contabilidad`: ya usan tenant en partes, pero requieren pruebas cruzadas.
- Storage `/media/object` ya valida prefijo `uploads/companies/{companyId}/`.

## 5. Plan De Migracion

Fase 1 completada:

- Agregar `CompanyMember`.
- Crear migracion no destructiva.
- Backfill desde `users.company_id`.
- Mantener `User.companyId` y `User.role` para compatibilidad.
- Login devuelve `companies`, `activeCompany`, `activeMembership` y flags de flujo.
- JWT valida membresia activa si existe.

Fase 2:

- Crear endpoints `companies/my-companies`, `companies/current`, `companies/switch`, onboarding.
- Crear pantalla real de registro/onboarding.
- Crear `Branch`, `Warehouse`, `CashRegister`/terminales si no existen o normalizar equivalentes.
- Agregar `AuditLog`, `Plan`, `Subscription`/`License`.

Fase 3:

- Convertir `companyId` opcional a obligatorio por grupos, despues de backfill y auditoria.
- Reemplazar unicos globales por compuestos por empresa.
- Endurecer todos los servicios con patrones tenant-aware.

Fase 4:

- Pruebas de acceso cruzado A/B para productos, clientes, ventas, reportes y archivos.
- Namespaces de cache frontend por empresa.
- Selector de empresa y limpieza de estado.

## 6. Archivos Modificados En Fase 1

- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20260728190000_add_company_members/migration.sql`
- `apps/api/prisma/seed.cjs`
- `apps/api/src/auth/auth.service.ts`
- `apps/api/src/auth/jwt.strategy.ts`
- `apps/api/src/auth/jwt-user.type.ts`

## 7. Criterio De Seguridad Actual

Esta fase no declara el SaaS completo como terminado. Deja la base real de membresias por empresa y mantiene compatibilidad con la empresa existente. Todavia faltan pruebas cruzadas, endpoints de onboarding, selector de empresa y endurecimiento total de consultas.
