# Preguntas al proveedor (Alanube) — bloqueantes de la emisión real

> Estas preguntas **no** se responden por suposición. Cada una tiene un bloqueo
> asociado: mientras siga abierta, la capacidad correspondiente no se
> implementa. Se derivan de la evidencia real recogida en
> `artifacts/e32-first-trial/` y de los contratos en
> `artifacts/alanube-public-contracts/`.

## A. Esquema y contrato

1. `GET /invoices/{id}` devolvió `stampDate`, `trackId` y `signatureDate` con
   formato/tipo **distinto** al declarado en `checkinvoices.json`. ¿Cuál es el
   esquema **vigente** en producción y cuál en sandbox? ¿El contrato publicado
   está desactualizado?
2. ¿Cuál es el **significado exacto** de `ACCEPTED` en la respuesta del
   proveedor? ¿Qué valor(es) indican aceptación **de la DGII** y cuáles solo
   recepción del proveedor?
3. ¿Qué campos son **obligatorios** por tipo de comprobante (E31, E32, E34) y
   por régimen del contribuyente?

## B. Idempotencia y reintentos

4. ¿El `POST /invoices` admite **clave de idempotencia**? Si no, ¿cómo se
   evita emitir dos veces el mismo comprobante tras un timeout de red?
5. Ante un **timeout** o una respuesta dudosa, ¿es seguro reintentar el `POST` o
   hay que consultar primero? ¿Con qué ventana temporal?
6. ¿Qué `HTTP status` y qué cuerpo devuelve ante un **duplicado** de eNCF?

## C. Secuencias y numeración

7. Si el proveedor consume la secuencia y la respuesta se pierde, ¿cómo se
   obtiene el eNCF realmente asignado? ¿Existe consulta por `remoteId`?
8. ¿Se puede **anular** o revertir un comprobante ya aceptado? ¿Con qué
   endpoint, plazo y efecto fiscal?

## D. Estado y notificaciones

9. ¿Existe **webhook** o **sondeo** para conocer la aceptación **de la DGII**
   (no la del proveedor)? ¿Cuál es la ruta, el formato y la política de
   reintentos?
10. ¿Cuáles son los **límites de tasa** y los **códigos de error**
    documentados, con su significado y si son reintentables?

## E. Habilitación y credenciales

11. ¿Qué hace exactamente `POST /company`? ¿Es obligatorio antes de emitir y
    qué estado deja?
12. ¿Cómo se **rota** el token de producción y cuánto dura?

## Uso interno

Ninguna pregunta de esta lista se responde «por lo que suele pasar». Hasta
tener respuesta escrita:

- la emisión real permanece **no implementada**;
- un comprobante con respuesta dudosa va siempre a **revisión humana**;
- ninguna secuencia consumida se reutiliza.
