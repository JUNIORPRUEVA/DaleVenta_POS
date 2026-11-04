# DOSA — transición auditada de un expediente histórico reconciliado

Estado: **procedimiento implementado, NO ejecutado**. Ninguna fila real fue
modificada, ninguna sesión real fue creada y ninguna bandera de producción fue
encendida.

## Objetivo

Permitir que un expediente histórico reconciliado —como el Intento 1 de
FULLTECH SRL— pueda continuar en una UAT controlada sin borrar su historial, sin
crear un segundo intento y sin que la apertura automática lo mute por sorpresa.

## Regla de seguridad

La apertura automática consulta la auditoría del expediente. Si existe
`INTENT_PROVIDER_RECONCILED` y **no** existe una autorización vigente
`INTENT_HISTORICAL_TRANSITION_AUTHORIZED`, responde:

`ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED`

No modifica estados, fechas, URLs, referencias ni identificadores.

## Autorización explícita

Endpoint:

`POST /ecf/dosa/certification-intent/authorize-historical-transition`

Condiciones, todas obligatorias:

- usuario `ADMIN` con `manageEcfOnboarding`;
- empresa incluida en `ECF_PORTAL_PILOT_COMPANY_IDS`;
- `ECF_DOSA_HISTORICAL_TRANSITION_ENABLED=true` en el entorno aislado;
- cuerpo:
  - `intentId` del expediente;
  - `ownerApprovalReference` (≥ 8 caracteres);
  - `reason` (≥ 20 caracteres);
  - `confirmation: "AUTHORIZE_HISTORICAL_TRANSITION"`.

La operación **solo crea auditoría**. No actualiza la fila del intento.

## Vigencia y unicidad

- La autorización vale 24 horas.
- No se permite una segunda autorización vigente para el mismo intento.
- La fila debe seguir en `NOT_STARTED`, `attemptNo = 1`, con `active_key`, sin
  `session_url`, sin `provider_postulation_id`, sin eventos y sin cierre.
- Debe existir una auditoría `INTENT_PROVIDER_RECONCILED` previa.

## Secuencia de UAT (futura, autorizada)

1. Verificar en la base aislada que el Intento 1 sigue intacto.
2. Configurar bandera, piloto y claves de cifrado en el entorno de UAT.
3. Llamar al endpoint de autorización con un administrador real.
4. Comprobar la auditoría `INTENT_HISTORICAL_TRANSITION_AUTHORIZED`.
5. Comprobar que la fila del intento no cambió.
6. Llamar a `POST /ecf/dosa/certification-session`.
7. Verificar que se reutiliza el MISMO intento (`attemptNo = 1`) y que no se crea
   un segundo registro.
8. Verificar que `session_url` quedó cifrada y que el historial de reconciliación
   sigue presente.
9. Documentar la evidencia y la referencia de aprobación.

## Qué NO hace este procedimiento

- No ejecuta la transición por sí solo.
- No borra ni reescribe auditoría.
- No crea un intento nuevo.
- No activa emisión.
- No marca la certificación como completada.
- No llama a DGII.
- No se ejecutó en esta integración.

## Evidencia mínima para autorizar una ejecución real

- Referencia de aprobación del propietario.
- Motivo escrito.
- Ventana de UAT y entorno identificado.
- Confirmación de que las claves de cifrado están configuradas.
- Confirmación de que el proveedor DOSA está en modo de pruebas.
- Plan de reversión: dejar la bandera apagada y no tocar la fila.
