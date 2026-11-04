# DOSA — un solo proceso oficial (capacidades reales y límites)

Estado: **implementado en rama aislada, sin desplegar**. Emisión electrónica
sigue apagada. No se ha iniciado ninguna postulación real.

Este documento responde primero a la pregunta técnica: **qué permite realmente
`dosa-cert.js` y la API de DOSA**. Todo lo que sigue está contrastado con el
script oficial descargado y con el código de este repositorio. Nada se infiere.

---

## 1. Qué permite el componente oficial

Fuente: `https://dosasystem.com/static/embed/dosa-cert.js`, tal como quedó
registrado en `ECF_DOSA_ASSISTANT_EMBEDDING.md` y en
`dosa_assistant_config.dart`.

### 1.1 Atributos (`observedAttributes`)

El componente observa **cinco** atributos y ninguno más:

```js
static get observedAttributes() {
  return ['session-url', 'publishable-key', 'base-url', 'theme', 'height'];
}
```

| Atributo | Qué hace | Sirve para precargar datos de empresa |
| --- | --- | --- |
| `session-url` | Enlace de sesión emitido por el **backend del partner** | **Sí**, indirectamente: la sesión la crea nuestro servidor |
| `publishable-key` | Clave pública (viaja en la URL del wizard) | No |
| `base-url` | Base de la API que consume el wizard | No |
| `theme` | `light` / oscuro | No (apariencia) |
| `height` | Alto del iframe en px | No (apariencia) |

**No existe ningún atributo para RNC, razón social, correo ni representante
legal.** Por tanto, la precarga de datos empresariales **no** se hace con
atributos.

### 1.2 Eventos

`cert:ready`, `cert:step`, `cert:postulacion`, `cert:attention`,
`cert:complete`, `cert:error`, `cert:resize`, `cert:asistida_pago`,
`cert:asistida_pagada` y `cert:blocked` (este último emitido por el propio
componente).

Son señales de progreso, **no** una fuente de verdad fiscal. En este repositorio
solo se usan para pedir una recarga del expediente; nunca para escribir estado.

### 1.3 Personalización visual

Únicamente `theme` y `height`. **No hay opciones documentadas** de tipografía,
colores, logos, ocultar campos ni reordenar pasos.

Consecuencia, aplicada en el código: el componente se incrusta **intacto** dentro
de un contenedor FullPOS elegante. No se toca el script, no se inyecta CSS en su
documento y no se manipula su DOM.

---

## 2. Precarga de datos: vía oficial implementada

El script afirma que el enlace de sesión lo crea *«el backend del partner con
`POST /api/certificacion/sesiones` y su secret key»*. Esa es la vía oficial para
que el cliente **no** vuelva a escribir su RNC.

El contrato fue entregado por DOSA el 2026-11-04 y está implementado en el
backend:

- `POST /api/certificacion/sesiones` con `X-Dosa-Secret-Key`.
- Cuerpo `{ rnc_emisor, correo, return_url? }`.
- Respuesta `201` con `url`, `path`, `token`, `expires_at`, `postulacion_id` y
  `prueba`.

La apertura automática reutiliza una sesión vigente, cierra la caducada y no
reintenta un resultado incierto. Sigue **apagada por defecto**: sin
`DOSA_CERTIFICATION_SESSIONS_ENABLED=true` y `DOSA_SECRET_KEY`, el backend
responde `ECF_DOSA_SESSION_DISABLED` y la app usa el portal existente como
fallback seguro.

No se simula escribiendo en el DOM ni interceptando el formulario del proveedor.
Si el contrato del proveedor cambia, el cambio queda localizado en el cliente y
el lanzador de sesiones del backend.

---

## 3. Certificado y contraseñas: quién los pide

**Todos los requisitos del onboarding los captura DOSA dentro de su asistente:**
archivo P12/PFX, contraseña del certificado y contraseña del Portal de
Certificación DGII. No se transmite ninguna de ellas desde FullPOS: la sesión
solo transporta RNC y correo, y el certificado se captura dentro del portal.

Lo que cambió en FullPOS es **quitar el duplicado**, no mover las credenciales:

| Antes | Ahora |
| --- | --- |
| Para llegar a Preparación había que validar el certificado en FullPOS | Se avanza solo con los datos de la empresa; el certificado se pide en DOSA |
| El paso de empresa bloqueaba «Continuar» sin certificado | «Continuar» se habilita y se explica que el certificado se pide en DOSA |
| Preparación mostraba a la vez el motor de prueba legado y el portal | Con el portal presente, el motor legado desaparece: un solo botón |

El bloque de certificado **sigue visible** cuando el usuario no tiene la vía
DOSA (sin `manageEcfOnboarding`), porque ahí no hay sustituto: sigue siendo el
camino para dejar el expediente completo.

Los metadatos y la auditoría de validaciones anteriores **se conservan**. Lo que
desaparece es la obligación de repetir la captura para poder postular.

### Lo que esto NO significa

- No se guarda ninguna contraseña. No se añade ningún campo de contraseña.
- La validación previa del certificado **no** implica tener el archivo para
  firmar después. Se mantienen separadas: emitir e-CF exigirá su propia
  preparación.
- No se elimina ningún registro histórico.

### 3.1 Un solo clic

«Iniciar postulación electrónica» hace, en este orden y en una sola acción:

1. Comprueba empresa autenticada y permiso `manageEcfOnboarding`.
2. Reutiliza el intento existente si lo hay.
3. Si no existe, registra la intención **una sola vez** con el mecanismo actual
   (idempotente en el backend).
4. Intenta la API oficial de sesiones: reutiliza una sesión vigente o crea una
   nueva. Si la API está deshabilitada, usa el ticket de un solo uso (120 s)
   como fallback seguro.
5. Abre el portal oficial con el asistente.

Qué **no** hace: no completa la postulación, no pulsa «Conectar» por el usuario,
no activa la emisión y no envía nada a la DGII. Con la API de sesiones puede
crear o reutilizar una sesión de certificación, pero el vínculo definitivo lo
confirma el usuario dentro del asistente.

Protecciones contra duplicados: un guardia de un solo disparo (`_autoOpened`),
el flag `_openingPortal` que corta ráfagas, la idempotencia del backend, el
lease por empresa, la reutilización de la sesión vigente y el bloqueo de
expedientes históricos reconciliados. Un timeout o un 201 no verificable se
marca incierto y **no** se reintenta automáticamente.


---

## 4. Datos de la empresa: de dónde salen

Del backend, para la empresa autenticada:

- RNC, razón social, dirección, teléfono y representante legal:
  `companySettingsProvider` (respuesta de la configuración de la empresa del JWT).
- `companyId` **nunca** se toma del navegador: el portal lo resuelve desde la
  sesión y el backend lo exige del token.

Si falta un dato obligatorio, el paso de empresa lo indica y abre el formulario
fiscal existente. No se crea un segundo expediente.

---

## 5. Qué sigue requiriendo al usuario

Esto es lo que sigue requiriendo al usuario dentro del asistente oficial:

1. Revisar y confirmar los datos de la empresa que DOSA muestra en la sesión.
2. Subir el certificado y su contraseña dentro del asistente.
3. Escribir la contraseña del Portal de Certificación DGII dentro del asistente.
4. Resolver los pasos que la DGII exige manualmente (pruebas, aceptación).
5. Aceptar dentro del portal lo que el proveedor solicite.

FullPOS **no** promete automatizar nada de eso.

---

## 6. Seguimiento

- Los tres hitos (Solicitud, Pruebas, Certificación) se pintan con el estado
  real del expediente y del intento.
- Abrir una pantalla **no** completa un hito.
- `cert:complete` significa «el asistente terminó», nunca «la DGII certificó».
- Los webhooks siguen firmados-desconocidos y **desactivados**: sin la fórmula
  de `X-Dosa-Signature` no se habilita su verificación.

---

## 7. Pendiente para cerrar del todo

| Bloqueo | Qué desbloquea |
| --- | --- |
| Activación operativa de `DOSA_CERTIFICATION_SESSIONS_ENABLED` y `DOSA_SECRET_KEY` | Habilitar la apertura automática real |
| Confirmación de idempotencia y límite de sesiones activas | Evitar duplicados ante reintentos del proveedor |
| Fórmula de `X-Dosa-Signature` | Webhooks verificables |
| Enumeración oficial de estados | Distinguir «postulación presentada» de «DGII certificó» |

### 7.1 Qué debemos solicitar exactamente al proveedor

Para activar la apertura automática en producción necesitamos, por escrito:

1. **URL base** de pruebas y producción del endpoint de sesiones.
2. **Cabecera de autenticación** y si hay allowlist de IPs de origen (la nuestra
   es `31.97.99.70`).
3. **Idempotencia**: qué ocurre al repetir la petición para el mismo RNC, con y
   sin clave de idempotencia.
4. **Límite de sesiones activas** por empresa/RNC y qué pasa si se supera.
5. **Códigos de error** completos y cuáles son reintentables.
6. **Alcance de `postulacion_id`**: si es único por empresa o global.
7. **Vigencia exacta** de la URL y si es de un solo uso.

Con esos siete puntos confirmados, la activación es un cambio de entorno
(`DOSA_CERTIFICATION_SESSIONS_ENABLED`, `DOSA_SECRET_KEY`) y una migración
aditiva ya validada; no requiere cambiar el flujo de la app.

