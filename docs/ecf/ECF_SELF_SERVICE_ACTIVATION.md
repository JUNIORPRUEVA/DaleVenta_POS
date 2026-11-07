# Autoservicio e-CF: el cliente se autoriza solo

Documento operativo del circuito por el que **un cliente completa su trámite y
queda autorizado para facturar sin que nadie de Fulltech intervenga**.

## 1. El problema que cierra

`DosaActivationService` es la única puerta que puede llevar una credencial de
DOSA a `ACTIVE`, y su cadena de evidencia es **100 % del cliente**:

```
sesión que vincula el RNC a la empresa
  → webhook de DOSA con estado_certificacion = "finalizado"
  → habilitación DGII APPROVED con origen DGII_OFFICIAL_RECORD
  → autorización administrativa registrada por el cliente
```

Esa cadena estaba escrita, probada y conectada al contenedor de dependencias…
pero **nadie llamaba a `activate()`**: no tenía ningún llamador en código de
producción. Consecuencia: el cliente terminaba todo su trámite, la evidencia
quedaba guardada, y la credencial se quedaba en `PENDING_CONFIRMATION` para
siempre. El cliente no podía facturar y no había ningún error que lo explicara.

Además, el estado de certificación que exige el orquestador de emisión
(`AUTHORIZED_SANDBOX`, `PRODUCTION_READY`) no se derivaba de nada: solo se podía
escribir a mano.

## 2. El circuito ahora

```
Cliente completa datos y abre el asistente DOSA        (rutas del cliente)
  → DOSA entrega credenciales (webhook autenticado)     (PENDING_CONFIRMATION)
  → Cliente registra su autorización DGII               (POST /ecf/dgii/authorization)
      → el backend intenta activar en ese mismo momento
      → credencial ACTIVE
      → estado de certificación derivado
  → Cliente factura
```

El último eslabón lo produce el propio cliente, así que el sistema lo usa como
disparador: al registrar su autorización DGII se intenta la activación, sin que
nadie de Fulltech participe.

Ese intento **nunca puede romper** el registro de la autorización: si falla, se
registra en el log y la autorización del cliente queda guardada igual.

## 3. La ruta de reintento

Si en ese momento faltaba algo (por ejemplo, la DGII todavía no había aprobado),
el cliente puede reintentar cuando quiera:

| Método | Ruta | Permiso | Cuerpo |
| --- | --- | --- | --- |
| `POST` | `/ecf/dosa/activation/attempt` | `manageEcfOnboarding` | ninguno |

- La empresa sale del **token** (`requireTenant`): no hay `companyId` en la ruta
  ni en el cuerpo, así que no existe forma de evaluar la de otro.
- No acepta «autorízame»: no hay campo para declarar aprobación. La evidencia se
  lee de la base de datos.
- Es idempotente: repetirla no activa dos veces ni duplica auditoría.
- Responde `200` aunque falte evidencia, con **qué falta exactamente**.

Respuesta:

```json
{
  "ok": true,
  "companyId": "…",
  "changed": true,
  "certificationStatus": "AUTHORIZED_SANDBOX",
  "environments": [
    {
      "environment": "test",
      "status": "ACTIVE",
      "activated": true,
      "blockingReasons": []
    }
  ]
}
```

Cuando falta algo, `ok: false` y cada ambiente trae sus motivos
(`ECF_DOSA_ACTIVATION_RNC_NOT_LINKED`, `ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED`,
`ECF_DOSA_ACTIVATION_AUTHORIZATION_MISSING`, …) para que la interfaz se lo diga
al cliente en lugar de mostrar un error genérico.

## 4. Cómo se deriva el estado de certificación

Una credencial `ACTIVE` implica que la DGII ya autorizó a esa empresa: el control
regulatorio no lo ejerce Fulltech. La derivación es 1:1 con esa evidencia:

| Credencial | Estado de certificación |
| --- | --- |
| `production` en `ACTIVE` | `PRODUCTION_READY` |
| `test` en `ACTIVE` | `AUTHORIZED_SANDBOX` |
| ninguna activa | no cambia nada |

### Lo que la derivación NO hace

| Situación | Comportamiento | Motivo |
| --- | --- | --- |
| No hay credencial activa | Conserva el estado actual | No autorizar no es degradar |
| Credencial `REVOKED` | No se resucita ni se activa | Revocar es un acto administrativo explícito |
| Estado `BLOCKED` | No se promociona; devuelve `ECF_CERTIFICATION_STATE_BLOCKED` | Hay evidencia vigente en contra; un bloqueo se resuelve, no se salta |
| Estado `SUSPENDED` | No se levanta | `SUSPENDED` es pegajoso: exige una autorización administrativa nueva |
| Sin configuración e-CF | `ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND` | No se crea: esa empresa no empezó el trámite |

### Auditoría

Cada cambio deja una fila en `ecf_audit_logs` con
`targetType = ECF_CERTIFICATION_AUTHORIZATION` y
`metadata.operation = CERTIFICATION_STATUS_DERIVED`. El `actorUserId` es `null`
a propósito: lo hizo el sistema al completarse la evidencia del cliente, y
atribuirlo a una persona sería falso.

## 5. Qué sigue siendo acto humano

Solo lo que es una decisión de negocio o de seguridad, nunca un paso del camino
del cliente (`docs/ecf/ECF_CERTIFICATION_AUTHORIZATION.md`):

- **Revocar o suspender** una empresa con incidente fiscal
  (`POST /ecf/platform/dosa/certification/:companyId/revoke`).
- **Corregir** un estado en un caso de soporte, con motivo y auditoría.

Autorizar a un cliente **no** requiere esa ruta: se autoriza completando la
evidencia.

## 6. Verificación

```
apps/api/src/ecf/certification/ecf-certification-activation.policy.spec.ts   (19 casos)
apps/api/src/ecf/certification/ecf-certification-activation.service.spec.ts  (11 casos)
apps/api/src/ecf/certification/ecf-certification-activation-http.e2e-spec.ts (8 casos)
```

El E2E corre con `PLATFORM_STAFF_ENV` **vacío** y sin ninguna concesión de
asistencia: si el circuito necesitara personal de plataforma, fallaría. Comprueba
autorización automática, idempotencia, auditoría con actor nulo, producción,
credencial revocada, `BLOCKED`, `SUSPENDED`, ausencia de configuración,
aislamiento entre empresas y acceso sin token.

## 7. Lo que aún falta

1. **La pantalla del cliente** que muestre `blockingReasons` y ofrezca el
   reintento. Hoy la ruta existe y la activación ocurre sola al registrar la
   autorización DGII, pero la app no muestra qué falta cuando algo falla.
2. **La primera emisión real contra DOSA**, que sigue pendiente de autorización
   de negocio.
3. **P1/P2** (firma de webhooks entrantes): sin confirmar, una empresa nueva no
   puede recibir credenciales, así que el circuito solo funciona con las
   credenciales que ya llegaron.
