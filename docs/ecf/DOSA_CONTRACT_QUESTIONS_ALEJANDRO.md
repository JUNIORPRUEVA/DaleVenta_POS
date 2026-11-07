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
