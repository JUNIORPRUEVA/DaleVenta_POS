# Preguntas abiertas para DOSA (Alejandro)

Mensaje corto listo para enviar. Solo lo que **bloquea** decisiones de código; el
resto está documentado en `docs/ecf/DOSA_CONTRACT_STATUS.md` y no impide avanzar.

---

## Mensaje

> Hola Alejandro:
>
> Para cerrar la integración multiempresa nos faltan cinco confirmaciones
> puntuales. Ninguna requiere que nos envíen credenciales nuevas:
>
> 1. **`api_secret`**: ¿es **uno por empresa** o hay uno distinto para TEST y
>    para PRODUCCIÓN? Hoy recibimos un solo valor junto a las dos API Keys y
>    necesitamos saber si debemos guardar dos secretos.
> 2. **Firma del webhook**: ¿el campo `t` de `X-Dosa-Signature` va en
>    **segundos** o en **milisegundos**? ¿Y el secreto de 64 caracteres
>    hexadecimales se usa **como texto** o **como 32 bytes decodificados**?
> 3. **Reintentos**: cuando un evento falla, ¿**re-firman** con un `t` nuevo en
>    cada intento? ¿Cuántos intentos hacen y con qué intervalo? Nuestra ventana
>    anti-replay es de 5 minutos y vemos reintentos que llegan caducados.
> 4. **Identificador de entrega**: ¿existe un id único por evento? Si no existe,
>    ¿cómo distinguen dos eventos del mismo día con el mismo estado?
> 5. **Reenvío manual**: ¿su panel permite reenviar una entrega concreta? ¿Bajo
>    qué autorización?
>
> Con eso podemos confirmar el modelo de credenciales y la política de firma sin
> tocar nada de producción. Gracias.

---

## Qué desbloquea cada respuesta

| # | Pregunta | Qué cambia en el código si la respuesta es la otra opción | Riesgo si se asume mal |
| --- | --- | --- | --- |
| 1 | `api_secret` único o por ambiente | El bundle de credenciales y la tabla pasarían de un secreto a dos | Emitir firmando con el secreto del otro ambiente |
| 2 | Unidad de `t` y encoding del secreto | `DOSA_WEBHOOK_TIMESTAMP_UNIT` / `DOSA_WEBHOOK_SECRET_ENCODING` | Rechazar **todos** los eventos (falla cerrado, pero el flujo se detiene) |
| 3 | Re-firma y política de reintento | No cambia código: se documenta y se ajusta la operación | Reintentos inútiles; nunca se relaja la ventana de 300 s |
| 4 | Id único de entrega | `dedupeKeyOf` pasaría a usarlo en vez del hash del cuerpo | Dos eventos distintos con el mismo cuerpo se tratarían como uno |
| 5 | Reenvío manual | No cambia código: define el procedimiento de recuperación | Un evento perdido no tendría recuperación conocida |

**Ninguna de estas respuestas se ha supuesto en el código.** Donde no hay
confirmación, el sistema falla cerrado y lo declara (`DOSA_WEBHOOK_PENDING_QUESTIONS`,
`docs/ecf/DOSA_CONTRACT_STATUS.md`).

## Lo que NO hay que pedirles

Ya está confirmado y no se vuelve a preguntar: cabecera `X-Dosa-Signature`,
formato `t=…,v1=…`, fórmula `HMAC-SHA256(secreto, t + "." + cuerpo)`, estructura
del payload de entrega de credenciales, endpoint de sesiones
(`https://dosasystem.com`) y endpoint `EnviarFactura`.

---

## Triaje: ¿bloquea código o solo bloquea producción?

Clasificación de las cinco preguntas según lo que realmente impide cada una. No
cambia ninguna respuesta pendiente en el código: sirve para decidir qué se puede
cerrar sin DOSA y qué no.

| # | Pregunta | ¿Bloquea CÓDIGO? | ¿Bloquea PRODUCCIÓN? | Por qué |
| --- | --- | --- | --- | --- |
| 1 | `api_secret` único o por ambiente | **No** | **Sí** | El almacén ya cifra por `(empresa, ambiente)` y admite uno o dos secretos sin cambio de esquema. Lo que no se puede es **emitir de verdad** sin saber con qué secreto firmar. |
| 2 | Unidad de `t` y encoding del secreto | **No** | **Sí** | Ambos son configurables (`DOSA_WEBHOOK_TIMESTAMP_UNIT`, `DOSA_WEBHOOK_SECRET_ENCODING`). Si se asume mal, el sistema falla cerrado: rechaza todo, no acepta de más. Se puede desplegar; no se puede operar sin la respuesta. |
| 3 | Re-firma y política de reintento | **No** | **No** (operativo) | No hay código que dependa. La ventana de 300 s no se relaja por comodidad: si sus reintentos llegan caducados, el ajuste correcto es que ellos re-firmen, no que nosotros aceptemos firmas viejas. |
| 4 | Identificador de entrega | **No** | **No** (degradado) | Hoy se deduplica por hash del cuerpo + estado. Es correcto con lo observado. Un id de entrega sería mejor, pero su ausencia no produce un fallo: produce una limitación documentada (dos entregas idénticas se tratan como una). |
| 5 | Reenvío manual | **No** | **No** (operativo) | Define el procedimiento de recuperación ante un evento perdido. Hoy la recuperación es que DOSA reenvíe y la deduplicación reanuda el evento incompleto. |

### Conclusión operativa

- **Nada de lo pendiente bloquea el código ni la validación funcional.** La
  integración está construida para funcionar con cualquiera de las dos respuestas
  y para fallar cerrado cuando la respuesta no llegó.
- **Sí bloquean la PRIMERA EMISIÓN REAL** las preguntas 1 y 2: son las únicas que
  impiden firmar/verificar con certeza en producción.
- Las preguntas 3, 4 y 5 son de operación: conviene tenerlas por escrito antes de
  la puesta en marcha, pero no detienen ni el desarrollo ni la preproducción.

### Condición para cambiar este triaje

Si DOSA confirma que el `api_secret` **sí** es distinto por ambiente, el trabajo
necesario es de datos (una fila más por empresa), no de esquema: la tabla ya
separa por `environment`. Si confirma que el secreto hexadecimal se usa
**decodificado**, el cambio es una variable de entorno, no código.
