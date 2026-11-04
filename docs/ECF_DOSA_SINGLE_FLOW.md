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

## 2. Precarga de datos: la única vía oficial y por qué está bloqueada

El script afirma que el enlace de sesión lo crea *«el backend del partner con
`POST /api/certificacion/sesiones` y su secret key»*. Esa es la vía oficial para
que el cliente **no** vuelva a escribir su RNC.

**Ese contrato no está publicado.** `ECF_DOSA_PROVIDER_CONTRACTS.md` documenta
las ocho incógnitas pendientes: URL base por entorno, cabecera de autenticación,
cuerpo de la petición (nombres de campo), forma de la respuesta (¿`session-url`
listo o un identificador?), códigos de error, idempotencia, vigencia y límite de
sesiones activas.

Consecuencia honesta:

- Hoy la postulación se abre con `publishable-key`, y **el cliente vuelve a
  escribir RNC y correo dentro del asistente de DOSA**.
- Eso **no se puede evitar** sin el contrato de sesiones. No se simula escribiendo
  en el DOM ni interceptando el formulario del proveedor: sería frágil,
  indocumentado y podría corromper una postulación oficial.
- En cuanto DOSA entregue el contrato, el cambio queda localizado en el backend
  (crear sesión → devolver `session-url`) y en el montaje del portal. El modelo
  `DosaAssistantConfig` ya soporta `session-url` y ya lo prioriza.

---

## 3. Certificado y contraseñas: quién los pide

**Todos los requisitos del onboarding los captura DOSA dentro de su asistente:**
archivo P12/PFX, contraseña del certificado y contraseña del Portal de
Certificación DGII. No se transmite ninguna de ellas desde FullPOS, porque el
mecanismo oficial para hacerlo es precisamente el de la sesión (bloqueado) y no
existe ninguna otra vía documentada.

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
4. Pide el ticket de un solo uso (120 s) con las validaciones ya existentes.
5. Abre el portal oficial con el asistente.

Qué **no** hace: no crea ninguna postulación en DOSA, no pulsa «Conectar» por el
usuario, no activa la emisión y no envía nada a la DGII. La intención registrada
es local; el vínculo con el proveedor lo crea el usuario dentro del asistente.

Protecciones contra duplicados: un guardia de un solo disparo (`_autoOpened`),
el flag `_openingPortal` que corta ráfagas de tickets, y la idempotencia del
backend, que devuelve el intento existente con `created: false`.


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

Esto es lo que hoy **no** se puede automatizar de forma oficial:

1. Escribir RNC y correo en el primer formulario de DOSA (falta el contrato de
   sesiones).
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
| Contrato de `POST /api/certificacion/sesiones` | Precarga real de RNC, razón social y correo: el cliente deja de escribirlos |
| Fórmula de `X-Dosa-Signature` | Webhooks verificables |
| Enumeración oficial de estados | Distinguir «postulación presentada» de «DGII certificó» |

### 7.1 Qué debemos solicitar exactamente al proveedor

Para implementar el autorrelleno por `session-url` —sin inventar nada ni tocar
su DOM— necesitamos, por escrito:

1. **URL base** del endpoint por entorno (pruebas y producción) y si el prefijo
   `/api` forma parte de la ruta.
2. **Cabecera de autenticación** exacta para la *secret key*: nombre, esquema y
   si hay allowlist de IPs de origen (la nuestra es `31.97.99.70`).
3. **Cuerpo de la petición**: nombre, tipo y obligatoriedad de cada campo.
   Necesitamos enviar al menos RNC, razón social, correo y representante legal,
   pero **no damos por hecho ningún nombre de campo**.
4. **Respuesta**: ¿devuelve el `session-url` listo para el componente, o un
   identificador con el que componerlo? ¿Qué vigencia tiene?
5. **Idempotencia**: qué ocurre al repetir la petición para el mismo RNC, con y
   sin clave de idempotencia.
6. **Límite de sesiones activas** por empresa/RNC y qué pasa si se supera.
7. **Códigos de error** completos y cuáles son reintentables.

Con esos siete puntos, la precarga es un cambio localizado en el backend (crear
la sesión y devolver el enlace) y en el montaje del portal: `DosaAssistantConfig`
ya prioriza `session-url` sobre `publishable-key`.

