# Borrado de empresas con datos fiscales — diseño y retención

> **Este documento NO ejecuta ninguna eliminación y NO propone saltarse ningún
> control.** No se borró ni una fila. No se modificó ningún *trigger*. Los plazos
> legales **no se afirman**: no hay fuente verificada en este repositorio, así que
> se marcan como pendientes de asesoría.

## 1. El hallazgo

Las tablas fiscales e-CF son **append-only por diseño** y varias tienen *triggers*
que impiden `UPDATE` y `DELETE`. Algunas de esas tablas cuelgan con
`ON DELETE CASCADE` de otras, así que el borrado en cascada choca contra los
*triggers* y **la operación entera falla a nivel de base de datos**.

Verificado leyendo las migraciones:

| Tabla | Trigger | Alcance verificado |
| --- | --- | --- |
| `ecf_electronic_documents` | `ecf_protect_document_snapshot` | `BEFORE UPDATE OR DELETE` |
| `ecf_evidence_receipts` | `ecf_evidence_immutable` → `ECF_EVIDENCE_APPEND_ONLY` | `BEFORE UPDATE OR DELETE`, **incondicional** |
| `ecf_credit_reservation_events` | `..._append_only` | `BEFORE UPDATE OR DELETE` |
| `ecf_sandbox_e32_trial_events` | `ecf_evidence_immutable` | `BEFORE UPDATE OR DELETE` |
| `ecf_line_classifications` | `ecf_line_classification_protect` → `ECF_LINE_CLASSIFICATION_IMMUTABLE` | `BEFORE UPDATE OR DELETE`, **incondicional** |

Relaciones en cascada relevantes:

- `ecf_line_classifications.company_id` → `companies(id)` `ON DELETE CASCADE`
- `ecf_evidence_receipts (company_id, document_id)` → `ecf_electronic_documents` `ON DELETE CASCADE`
- `ecf_electronic_documents.company_id` → `companies(id)`

**Consecuencia (HECHO, reproducido en prueba):** borrar una empresa que tenga
documentos electrónicos o clasificaciones de partidas **falla**:
`ECF_EVIDENCE_APPEND_ONLY` o `ECF_LINE_CLASSIFICATION_IMMUTABLE`.

**No existe ninguna vía de escape.** Se comprobó que no hay ninguna bandera de
purga: el único `current_setting('fullpos...')` del módulo es
`fullpos.ecf_actor`, que sirve para atribuir autoría, no para autorizar borrados.

## 2. Por qué esto no es simplemente un `bug`

Los *triggers* están ahí por una razón correcta: un documento fiscal emitido y su
evidencia **no deben poder reescribirse ni desaparecer** sin dejar rastro. El
conflicto no es «el trigger estorba», sino que **el producto no tiene definida su
política de ciclo de vida fiscal**. Este documento propone definirla.

## 3. Política propuesta (RECOMENDACIÓN — no implementada)

Escalonado, de menos a más destructivo. Cada escalón es reversible hasta el
último.

### 3.1 Desactivación comercial (ya existe, es el primer paso)

- Licencia bloqueada / límites a cero: la empresa deja de poder operar.
- Acceso de usuarios revocado.
- **No toca ningún dato fiscal.** Es el estado por defecto ante una baja.

### 3.2 Bloqueo de acceso y preservación

- Sesiones invalidadas; el login deniega con un motivo claro.
- Los datos fiscales permanecen **íntegros** y consultables por soporte
  autorizado (lectura).
- Se marca la empresa como «baja solicitada» con fecha. Nada se borra.

### 3.3 Archivo y retención

- Exportación firmada (hash) del paquete fiscal: documentos, evidencia,
  auditoría y secuencias.
- El archivo se guarda en almacenamiento de objetos con retención; la empresa
  puede entrar en un estado `ARCHIVED` de solo lectura.
- **Los plazos de retención son PENDIENTES de asesoría legal dominicana.** No se
  fija aquí ningún número de años: afirmarlo sin fuente sería inventarlo.

### 3.4 Anonimización (solo si es legalmente procedente)

- Seudonimizar los datos personales **que no formen parte del comprobante
  fiscal**: nombre de contacto, teléfono, correo, dirección del cliente en
  registros auxiliares.
- **NO se anonimiza** lo que constituye el comprobante (RNC, importes, e-NCF,
  líneas, huellas) mientras la obligación de conservación siga viva.
- Requiere la misma validación legal que §3.3.

### 3.5 Eliminación definitiva

- Un único camino **autorizado, auditado y explícito**, nunca un `DELETE`
  improvisado ni un `session_replication_role` para desactivar *triggers*.
- Debe quedar registrado: quién, cuándo, con qué autorización y qué se eliminó.
- Si se implementa, la vía correcta es una **función de purga dedicada** que (a)
  verifique que el período de retención venció, (b) exija una autorización
  explícita, (c) escriba un asiento de auditoría **antes** de borrar y (d) borre
  en el orden que respete las claves foráneas. Los *triggers* actuales no la
  permiten hoy: habría que decidir si se les añade una condición de purga
  autorizada, **cosa que este documento no hace**.

## 4. Matriz de riesgos

| # | Riesgo | Severidad | Mitigación propuesta | Estado |
| --- | --- | --- | --- | --- |
| R1 | Una baja de cliente falla hoy si tiene datos e-CF, y el error es un `500` opaco | Alta | Detectar el caso y responder un mensaje claro («esta cuenta tiene datos fiscales sujetos a conservación») | **Pendiente** |
| R2 | Alguien «arregla» el borrado desactivando *triggers* | Crítica | Prohibirlo explícitamente; la purga, si existe, va por función dedicada | **Documentado** |
| R3 | Borrar datos fiscales antes de tiempo incumple la obligación de conservación | Alta | No fijar plazos sin asesoría; bloquear el borrado hasta tenerlos | **Pendiente legal** |
| R4 | Anonimizar el comprobante en lugar de los datos auxiliares | Alta | §3.4 lo separa explícitamente | **Documentado** |
| R5 | Que el archivo de retención no sea verificable | Media | Exportación con hash y verificación de integridad | **Propuesto** |
| R6 | Retención indefinida sin coste controlado | Media | Estado `ARCHIVED` + política de almacenamiento | **Propuesto** |

## 5. Qué NO se hizo (declarado)

- **No se ejecutó ningún `DELETE`** de empresas ni de datos fiscales.
- **No se modificó ningún *trigger*** ni se añadió ninguna vía de escape.
- **No se implementó** ninguna función de purga.
- **No se fijaron plazos legales**, porque no hay fuente verificada.
- **No se cambió** la ruta `DELETE /auth/account`.

## 6. Siguiente paso exacto

1. Asesoría legal sobre plazos de conservación fiscal en República Dominicana.
2. Con los plazos definidos, decidir si se implementa la purga dedicada (§3.5) o
   si el borrado de cuentas con datos fiscales queda **bloqueado de forma
   permanente y documentada** (§3.2).
3. Mientras 1–2 no estén cerrados, la baja de una empresa con datos e-CF debe
   resolverse por **desactivación + archivo**, nunca por borrado.
