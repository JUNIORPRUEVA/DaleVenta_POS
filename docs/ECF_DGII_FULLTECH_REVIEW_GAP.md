# Revisión Fulltech del expediente DGII — estado y bloqueo

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-19**.

## 1. Lo que se implementó en este turno

| Pieza | Archivo |
| --- | --- |
| Regla de motivo obligatorio | `apps/api/src/ecf/dgii/ecf-dgii-correction.policy.ts` |
| Aplicación en la actualización | `ecf-dgii-habilitation.service.ts` (`updateHabilitation`) |
| Pruebas | `ecf-dgii-correction.policy.spec.ts` (7) |

**Regla:** pasar el expediente a `REQUIRES_CORRECTION` o `REJECTED` sin un motivo
escrito devuelve `400 ECF_DGII_CORRECTION_REASON_REQUIRED`. Se acepta el motivo
nuevo **o** uno ya registrado: no se obliga a repetir una explicación existente.

Motivo: una devolución sin motivo no es auditable y deja al cliente sin saber qué
corregir. Es la pieza que faltaba para que el ciclo de corrección sea usable.

## 2. El bloqueo del panel multiempresa (no es una limitación de tiempo)

El requisito es que **solo personal de Fulltech** revise expedientes de varias
empresas, sin reutilizar permisos administrativos de un cliente.

Hoy eso **no es posible sin cambiar el modelo de autorización**, y así se
verificó en el código:

```ts
// apps/api/src/auth/roles.guard.ts
if (role === Role.ADMIN) {
  return true;   // <-- cualquier ADMIN de empresa pasa TODOS los permisos
}
```

Consecuencias concretas:

1. Un permiso nuevo como `reviewEcfDgiiApplications` **lo tendría automáticamente
   el ADMIN de cada empresa cliente** por el bypass del rol.
2. Una ruta global que liste expedientes de todas las empresas quedaría expuesta
   a cualquier administrador de cualquier tenant → **fuga entre empresas**.
3. Por eso no se implementó: hacerlo exigiría modificar el guard y el modelo de
   identidad, que es una operación de **frontera de tenant**.

## 3. Qué hace falta para desbloquearlo

Una identidad de plataforma explícita. Dos opciones, ambas requieren autorización
del propietario por tocar autorización:

| Opción | Cambio | Riesgo |
| --- | --- | --- |
| **A** Rol `PLATFORM_STAFF` en `Role` + rama propia en `RolesGuard` | Enum + migración + guard + permisos de plataforma | Medio: toca el guard que protege todo |
| **B** Tabla `platform_staff` independiente y guard propio para rutas de plataforma | Tabla + guard nuevo, sin tocar el guard actual | Bajo/medio: aísla el cambio |

**Recomendación:** opción **B**. No altera el comportamiento de los clientes
existentes y el panel queda separado por diseño.

## 3.1 Resolución aplicada (variante de B, sin tabla nueva)

Estado: **resuelto**. La pertenencia al equipo de Fulltech se declara en la
variable de entorno `ECF_PLATFORM_STAFF_USER_IDS` (identificadores de usuario
separados por comas). Motivo: no exige migración, no crea una fuente de verdad
paralela a `User` y el fallo es **cerrado** por diseño.

- `apps/api/src/ecf/platform/platform-staff.guard.ts` — `PlatformStaffGuard`.
  Sin variable, sin lista o sin usuario ⇒ `403 PLATFORM_STAFF_REQUIRED`. Un
  `ADMIN` no listado también es rechazado.
- `apps/api/src/ecf/platform/ecf-platform.controller.ts` — rutas
  `/ecf/platform/*`, **fuera** de `EcfController` (que nunca acepta `companyId`):
  - `GET /ecf/platform/me` — prueba de pertenencia.
  - `GET /ecf/platform/dgii/applications` — cola multiempresa (metadatos).
  - `GET /ecf/platform/dgii/applications/:companyId` — detalle + evidencias, sin
    la referencia interna de almacenamiento.
  - `PATCH /ecf/platform/dgii/applications/:companyId` — decisión de revisión.

### Por qué la decisión no duplica reglas

`EcfDgiiHabilitationService.updateHabilitationForCompany` delega en el mismo
método privado que usa la empresa (`applyHabilitationUpdate`). Consecuencias
verificables en el código:

- Las transiciones se siguen decidiendo con `stateUpdateRefusal`.
- El motivo obligatorio se sigue decidiendo con `correctionReasonRefusal`.
- La auditoría (`DGII_HABILITATION_UPDATED`) es la misma y registra el actor real.
- **`APPROVED` sigue siendo inalcanzable** sin `DGII_OFFICIAL_RECORD` + evidencia
  + fecha + identificador externo (`ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD`).

### Cliente Flutter

- `lib/features/ecf/data/ecf_platform_repository.dart` — cliente separado del de
  la empresa; `isPlatformStaff()` trata el `403` como "no es personal" y
  **propaga** cualquier otro error.
- `lib/features/ecf/ui/ecf_platform_review_page.dart` — cola, detalle y tres
  acciones (en revisión / pedir corrección / rechazar). No existe botón de
  aprobación y el texto de la pantalla lo explica.
- El acceso aparece en la pantalla de habilitación solo si `/me` confirma
  pertenencia: la ruta existe para todos, los datos no.

### Pendientes declarados

- **Sin prueba de integración dedicada** del camino `PATCH /ecf/platform/...`
  contra la base de datos: se valida por compilación, por el guard (7 pruebas) y
  por delegación estructural en la política compartida. Es un hueco conocido, no
  una afirmación de cobertura.
- `ECF_PLATFORM_STAFF_USER_IDS` **no está configurada** en ningún entorno: hoy la
  superficie responde `403` a todo el mundo, administradores de empresa
  incluidos. Configurarla es una decisión operativa.
- No hay UI para revisar evidencias una por una desde plataforma (solo listado y
  decisiones de estado).

## 4. Qué ya está listo para cuando se autorice

- Expediente por empresa con estados, requisitos, evidencias y auditoría.
- Evidencias con procedencia y revisión.
- Regla de motivo obligatorio (nueva).
- Asistente Flutter que envía a revisión (`APPLICATION_PENDING`).
- Documentos con carga/descarga segura.
- `APPROVED` sigue exigiendo registro oficial verificado.

## 5. Evidencia ejecutada

```text
npx tsc --noEmit                 -> exit 0
run-focused.ps1 -Pattern ecf-dgii -> 6 suites / 72 pruebas, 0 fallos
flutter analyze                  -> No issues found
```
