# LAB DOSA WEB — auditoría, respaldo y limpieza reversible

Estado: **auditoría hecha, limpieza NO autorizada y NO ejecutada**.

Este documento existe para que el borrado, cuando se autorice, sea verificable y
reversible. No contiene credenciales: el acceso se toma de variables de entorno.

---

## 1. Origen del registro

Durante la validación del flujo de habilitación (2026-11-02) se creó por error
una empresa de prueba usando el **API de UAT**, no el de laboratorio: el proceso
de UAT ya ocupaba `127.0.0.1:4004`, que es el único puerto que admite el perfil
de validación del cliente. El registro se creó por la vía legítima de la
aplicación (`POST /auth/register-business`) contra el destino equivocado.

## 2. Destino exacto

| Dato | Valor |
| --- | --- |
| Contenedor | `fullpos_alanube_ecf_test_postgres` |
| Base | `fullpos_alanube_uat_test` |
| Puerto | `127.0.0.1:56551` |
| Empresas en la base | **6.059** → base compartida, no desechable |

## 3. Alcance real (auditoría de solo lectura)

Se recorrió `information_schema.columns` y se contaron las filas de la empresa
`576599f9-916f-4821-b008-fcf8c4db5f7c` en **todas** las tablas con columna
`company_id`, más las tablas con claves foráneas al usuario. Resultado:

| Tabla | Filas |
| --- | --- |
| `companies` | 1 |
| `app_config` | 1 |
| `users` | 1 |
| `company_members` | 1 |
| `auth_sessions` | 2 |
| `telemetry_outbox` | 2 |
| `terminals` | 1 |
| `warehouses` | 1 |
| `inventory_zero_config_states` | 1 |
| **Total** | **11 filas en 9 tablas** |

Comprobaciones adicionales:

* Empresa: `LAB DOSA WEB`, slug `lab-dosa-web`, `status=ACTIVE`,
  `license_status=TRIAL`, `tax_enabled=false`, creada 2026-11-02 16:37:32.
* Usuario: `6df9d48e-1fb6-42bc-bdcd-7234a14ad994`, `lab.dosa.web@example.test`.
* RNC `13199988001`: **ninguna otra empresa** de la base lo declara.
* **Cero** ventas, comprobantes, sesiones de caja, productos, secuencias NCF o
  filas de tablas `ecf_*`. No hay actividad comercial ni fiscal.
* No existe ninguna fila que apunte a esta empresa desde una tabla sin
  `company_id` que no esté ya contada.

## 4. Por qué `pg_dump -t` NO sirve aquí

`pg_dump -t tabla` exporta la tabla **completa**, no las filas de una empresa.
Restaurar ese dump sobre una base compartida devolvería las 6.059 empresas y
sobrescribiría datos ajenos. Un respaldo que no se puede restaurar sin daño no
es un respaldo.

## 5. Procedimiento correcto

### Paso 0 — Reglas

* Ventana con aviso: es una base compartida.
* Nada de `DROP`, `TRUNCATE` ni `DELETE` sin `WHERE company_id = …`.
* Todas las credenciales por variable de entorno, nunca en el comando.

```powershell
# Una sola vez por sesión. No se imprime el valor.
$env:PGPASSWORD = (docker inspect fullpos_alanube_ecf_test_postgres `
  --format '{{range .Config.Env}}{{println .}}{{end}}' |
  Where-Object { $_ -like 'POSTGRES_PASSWORD=*' }) -replace '^POSTGRES_PASSWORD=',''
```

### Paso 1 — Respaldo por filas (no por tabla)

Para cada tabla se exporta **solo** el subconjunto de esa empresa, en CSV, más
el DDL de la tabla (estructura) para poder reconstruirla en una base de ensayo:

```sql
-- repetir por cada una de las 9 tablas
\copy (SELECT * FROM companies WHERE id = '576599f9-…') TO 'backup/companies.csv' CSV HEADER
\copy (SELECT * FROM users WHERE company_id = '576599f9-…') TO 'backup/users.csv' CSV HEADER
-- … app_config, company_members, auth_sessions, telemetry_outbox,
--    terminals, warehouses, inventory_zero_config_states
```

Además, respaldo de estructura:

```
pg_dump --schema-only --table=companies --table=users --table=app_config \
        --table=company_members --table=auth_sessions --table=telemetry_outbox \
        --table=terminals --table=warehouses --table=inventory_zero_config_states \
        -f backup/schema.sql
```

### Paso 2 — Ensayo de restauración (obligatorio antes de borrar)

1. Crear una base **desechable** aparte (nunca la compartida).
2. Aplicar `schema.sql`.
3. Importar los CSV con `\copy … FROM`.
4. Comprobar que las 9 tablas devuelven exactamente 1/1/1/1/2/2/1/1/1 filas.

Si el ensayo no cuadra, **no se borra nada**.

### Paso 3 — Consideraciones que el plan anterior no cubría

| Tema | Cómo se trata |
| --- | --- |
| Claves foráneas | Borrado en orden hijo → padre; `companies` al final. La FK `ON DELETE CASCADE` puede hacer el resto, pero se verifica tabla por tabla. |
| Triggers | Se **no** desactivan globalmente. Si algún trigger impide el borrado, se documenta y se para. |
| Secuencias | Las 9 tablas usan `uuid`/`gen_random_uuid()`; no hay seriales que reajustar. Se verifica antes. |
| Otras empresas | Todo `DELETE` lleva `WHERE` por `company_id` o por `id`. Nunca por patrón de nombre. |
| Auditoría | Las filas de auditoría de esa empresa se incluyen en el respaldo y se cuentan antes y después. |

### Paso 4 — Borrado (solo con autorización explícita)

```sql
BEGIN;
DELETE FROM auth_sessions                 WHERE company_id = '576599f9-…';
DELETE FROM telemetry_outbox              WHERE company_id = '576599f9-…';
DELETE FROM inventory_zero_config_states  WHERE company_id = '576599f9-…';
DELETE FROM terminals                     WHERE company_id = '576599f9-…';
DELETE FROM warehouses                    WHERE company_id = '576599f9-…';
DELETE FROM company_members               WHERE company_id = '576599f9-…';
DELETE FROM users                         WHERE company_id = '576599f9-…';
DELETE FROM app_config                    WHERE company_id = '576599f9-…';
DELETE FROM companies                     WHERE id         = '576599f9-…';
-- verificar los 9 conteos; si alguno no es 0, ROLLBACK
COMMIT;
```

### Paso 5 — Verificación posterior

Repetir la consulta de conteo por tabla del §3: los 9 valores deben ser 0.
Comprobar además que el total de empresas baja de 6.059 a 6.058 y que ningún
otro slug/RNC cambió.

### Paso 6 — Reversión

Si algo salió mal: crear una base desechable, aplicar `schema.sql`, importar los
9 CSV y verificar. Solo entonces se decide cómo reintroducir las filas, tabla
padre primero.

## 6. Qué se necesita para autorizar

1. Confirmar la ventana de mantenimiento de `fullpos_alanube_uat_test`.
2. Autorizar explícitamente el `DELETE` sobre esa base compartida.
3. Ejecutar el ensayo del Paso 2 y adjuntar el resultado.

Sin los tres, este procedimiento no se ejecuta.
