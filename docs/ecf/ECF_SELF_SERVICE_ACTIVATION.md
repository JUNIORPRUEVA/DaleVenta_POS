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

## 7. Lo que ve el cliente

No hay pantallas nuevas. El recorrido es el que ya existía —Bienvenida →
Preparación → Seguimiento— y lo único que se añadió es **un bloque dentro de los
dos últimos pasos**:

```
Bienvenida (vídeo)          →  «Empezar»
Preparación                 →  datos ya registrados + abrir el asistente DOSA
                               + bloque de autorización
Asistente DOSA              →  todo el trabajo pesado ocurre allí
Seguimiento                 →  en qué quedó + qué falta + «Actualizar estado»
```

El bloque (`EcfDosaActivationStatus`):

- **Consulta solo al aparecer**, sin que el cliente pulse nada: quien vuelve días
  después ve su estado actualizado.
- Si ya está autorizado, lo dice en una línea y no deja nada por hacer.
- Si falta algo, lista los motivos en español (los seis códigos de
  `activationBlockers`). Un motivo nuevo se muestra en crudo: esconderlo dejaría
  al cliente sin nada que decirle a soporte.
- Un fallo de red se distingue de «falta evidencia»: son cosas distintas.
- No se muestra ni se consulta sin el permiso `manageEcfOnboarding`, porque el
  backend respondería 403.

### Entrada al asistente sin intervención de Fulltech

La elegibilidad del asistente ya no exige que alguien inscriba a la empresa:

| Antes | Ahora |
| --- | --- |
| Sin fila de inscripción → sin elegibilidad → **sin botón de asistente** | La empresa que cumple la regla entra sola |
| La regla automática exigía una sesión de DOSA que solo existe *después* de entrar (circular) | La regla exige e-CF habilitado + RNC registrado |
| `ECF_PORTAL_AUTO_ENROLL_ENABLED` apagada por defecto | **Encendida por defecto** (opt-out) |

Lo que NO cambia:

- **Una revocación gana siempre.** Si la empresa tiene una inscripción revocada o
  caducada, la regla automática no la resucita.
- **La lectura no escribe.** `eligibility` decide, pero la inscripción se persiste
  en el camino de escritura (al emitir el ticket del portal), con origen
  `AUTO_ELIGIBLE`, fecha y motivo.
- **Interruptor de emergencia:** `ECF_PORTAL_AUTO_ENROLL_ENABLED=false` vuelve al
  comportamiento anterior sin desplegar código.

### Numeración de comprobantes (e-NCF)

`EcfSequenceRangeSection`, también dentro del recorrido:

- Sin rango activo **no se puede preparar ningún comprobante**: el backend
  responde `ECF_SEQUENCE_EXHAUSTED`, que no explica nada. Antes no existía
  ninguna pantalla para declararlo y el cliente quedaba autorizado pero incapaz
  de facturar.
- Solo pide **dos números** (desde / hasta). El prefijo lo deriva el backend del
  tipo de comprobante.
- **Se oculta sola** cuando ya hay un rango `E31` activo con números disponibles.
- Valida en local (final ≥ inicial, solo dígitos) y traduce los rechazos del
  servidor (`ALREADY_EXISTS`, `REUSE_BLOCKED`, `RANGE_INVALID`).
- Gateada con `manageEcfSequences`, el mismo permiso que exige el backend.

### Lo que se simplificó del recorrido

Con DOSA gobernando el certificado, el paso de Preparación ocultaba el bloque del
certificado (ya lo hacía) y ahora además:

- no ofrece «Revisar» cuando los datos ya están completos —no hay nada que
  revisar—,
- no muestra la fila «Datos fiscales: Completos», que solo era ruido,

pero **conserva** el RNC y el correo fiscal con su botón de copiar, porque son
exactamente los dos datos que el asistente de DOSA vuelve a pedir y no acepta
prellenado.

## 8. Lo que aún falta

1. **El vídeo de bienvenida** se configura en el backend y la pantalla ya tiene su
   espacio; falta cargar la URL.
2. **La primera emisión real contra DOSA**, que sigue pendiente de autorización
   de negocio.
3. **P1/P2/P5** (firma de webhooks entrantes): sin confirmar, una empresa nueva no
   puede recibir credenciales. Ver `DOSA_WEBHOOK_AUDIT_2026-11.md`.
4. **Encender el webhook** en el ambiente: bandera + estrategia + secreto.
