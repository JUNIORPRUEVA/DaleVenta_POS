# Acceso ADMIN para UAT Alanube aislada

2026-10-14. Solo FULLPOS-ECF-ALANUBE / feature/ecf-alanube.
Identificador preparado: **alanube.admin@fullpos.local**.

## Auditoría inicial

- VERIFIED_BY_DATABASE_READ: host 127.0.0.1, puerto 56550, base
  fullpos_alanube_uat, binding único del contenedor 127.0.0.1:56550.
- La base contiene **0 usuarios ADMIN**. El identificador configurado no tenía
  cuenta; por eso el login anterior devolvió 401 antes de verificar contraseña.
- scripts/isolated-uat/_common.ps1 prepara configuración privada, pero no crea
  usuarios. Su contraseña generada en el archivo local no prueba que exista una
  cuenta ni se usará como sustituto de una nueva contraseña interactiva.
- El identificador uat.admin@daleventa.local de la captura pertenece al valor
  por defecto de apps/api/scripts/seed-uat-local.ts; ese script apunta a
  daleventa_uat_local/daleventa_uat e incluye inventario/compras. No ejecutarlo
  en esta base ni modificar el POS para resolver el acceso.
- Hash oficial: AuthService.registerBusiness/resetPassword y seed UAT utilizan
  bcryptjs.hash(password,10); login usa bcrypt.compare. No hay hash improvisado
  ni JWT firmado artificialmente en el procedimiento nuevo.

## Backup previo a cualquier escritura

artifacts/uat-backups/ecf_before_admin_access_20261014_192227.dump,
1059034 bytes, SHA-256:
F4D87719212FD540BFB7B8F904A2A455161E341F0DBA0C75864317DE6E519CC4.
Creado con pg_dump -Fc, lectura completa pg_restore --file=/dev/null verificada,
copia local comprobada. Ignorado por Git. No se hizo restore sobre la base.
Constancia no sensible: artifacts/e32-first-trial/admin-access-backup.json.
El helper exige hash/tamaño/fecha del backup (máximo una hora) antes de escribir.

## Procedimiento autorizado y límites

Se abre PowerShell con:

```powershell
./scripts/isolated-uat/e32-operator-login-preflight.ps1 -CreateSyntheticAdmin
```

Pide contraseña nueva y confirmación ocultas. Nunca ponerla en comandos, chat,
archivos ni logs. El proceso pasa la contraseña al helper Node por stdin UTF-8,
no por argumentos ni archivos. No usa la contraseña vieja de configuración.

create-synthetic-admin.cjs valida rama/worktree, URL estricta sin overrides,
contenedor, current_database(), interruptores desactivados y backup verificado.
En una transacción con bloqueo crea exclusivamente:

1. Empresa nueva SYNTHETIC Fullpos Alanube UAT Access,
   slug fullpos-alanube-uat-access, STANDARD/TRIAL siete días según el patrón de
   registro del backend, máximos estándar 2 usuarios/100 productos, NCF/impuestos
   tradicionales desactivados. No activa una licencia pagada ni modifica otra.
2. Usuario alanube.admin@fullpos.local, ADMIN, no bloqueado, contraseña bcrypt10.
3. Membresía OWNER/ACTIVE en esa empresa sintética.

Si ya existe cualquiera de esas identidades, se niega a adoptar, mover,
promover o restablecer registros. No escribe productos, caja, ventas, inventario,
configuración fiscal, migraciones ni otros tenants. No ejecuta el seed general.

Después hace POST **solo local** a 127.0.0.1:4002/auth/login, mantiene JWT en
memoria y ejecuta el CLI de preflight. JwtStrategy valida firma/expiración,
sesión/usuario/empresa/membresía/rol/licencia. Reporta solo status/HTTP/checks y
datos no secretos de la cuenta sintética en operator-preflight.json, ignorado.
No guarda respuesta de login, tokens, contraseña ni hash de contraseña.

## Estado de ejecución

**ACCESO ADMIN GO — verificado funcionalmente.** El operador definió y confirmó
la contraseña en la ventana oculta. Cuenta creada el 2026-10-14T19:25:42.469Z,
login local HTTP201 y preflight terminado 2026-10-14T19:25:43.3467231Z.
OPERATOR_CONTEXT=true confirma validación real de JWT/sesión/empresa/ADMIN/licencia.
Relectura de la cuenta sintética confirma ADMIN no bloqueado, membresía OWNER
ACTIVE, empresa ACTIVE, TRIAL válida hasta 2026-10-21T19:25:42.469Z y una sesión
activa. NCF/impuestos tradicionales siguen desactivados. Ningún usuario previo
modificado; no se alteraron licencias existentes. API permanece en 127.0.0.1:4002.

No se conoce ni conserva la contraseña definida en el flujo del agente. No se
actualizó UAT_ADMIN_PASSWORD del archivo privado: ese valor antiguo no se usa.
El operador debe usar la contraseña que acaba de definir.

Pruebas ejecutadas: node --test scripts/isolated-uat/create-synthetic-admin.test.cjs
(3 PASS), node --check create-synthetic-admin.cjs (PASS), parser PowerShell
(0 errores), Jest e32-sandbox.spec (35 PASS), git diff --check PASS. No cambios
de código de arranque en esta tarea; API corregida previamente ya estaba activa.

**E32 continúa BLOCKED**, separado del acceso resuelto:
TEST_COMPANY_CONFIRMED=false y SECRET_REFERENCE=false porque la empresa sintética
nueva aún no tiene EcfCompanyConfiguration (verificado en DB). No se configuró
fiscalmente un tenant como efecto secundario de crear acceso. E32_PAYLOAD=false
por dirección Sandbox null. Los demás checks, incluido NUMBER_UNUSED_LOCALLY,
son true. Cero solicitudes externas/POST fiscales en esta tarea.

## Próximos accesos y recuperación

API local: http://127.0.0.1:4002. Usuario **alanube.admin@fullpos.local** y la
contraseña que el operador defina, no la del portal Alanube ni la antigua del env.
Para login/preflight posterior, usar el helper sin -CreateSyntheticAdmin.
La captura [UAT] no demuestra el endpoint del cliente: si ese cliente apunta a
otra API, esta cuenta no existirá allí. No se cambió Flutter ni su configuración.

Si se pierde la contraseña después de crear la cuenta: auditar de nuevo usuario,
empresa sintética y membresía, crear/verificar un backup nuevo, y preparar un
restablecimiento exclusivo de esa identidad con bcrypt10 y revocación de sus
sesiones como hace AuthService.resetPassword. No usar seed/upsert masivo, hashes
de ejemplo ni activar licencias para superar un fallo. No se ejecuta un reset
automático al repetir este helper de creación.

La dirección del emisor Alanube sigue pendiente; no usar address como domicilio.
La cuenta nueva no habilita emisión ni reemplaza la configuración e-CF por tenant.
