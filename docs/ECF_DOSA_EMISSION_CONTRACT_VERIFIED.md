# DOSA — contrato de emisión verificado contra la documentación oficial

Fuente: `https://github.com/alapaix13/DosaInvoicecloud-Documentation`
(`README.md`, 75 031 bytes, clonado en local el 2026-11-03). Todo lo de abajo es
**HECHO** leído del documento; lo que no está en el documento se marca como
**NO DOCUMENTADO**.

## 1. Endpoint y autenticación

| Dato | Valor |
| --- | --- |
| URL | `https://dosasystem.com/fe/api/emision/ecf/EnviarFactura` |
| Método | `POST` |
| Content-Type | `application/json` |
| Autenticación | cabecera `X-API-KEY` |
| Notas de crédito | `NotaDesdeFactura` (documento aparte) |

## 2. Separación de ambientes — lo que la documentación NO dice

El documento **no describe** cómo DOSA separa TEST de producción para su propia
API. Lo único que menciona son las URLs de la **DGII**:

```
Pruebas:    https://ecf.dgii.gov.do/testecf/...
Producción: https://ecf.dgii.gov.do/ecf/...
```

Esas son URLs de consulta pública de la DGII, **no** endpoints de DOSA. Y la URL
de emisión es única. Recomendación del propio documento: «Implementar diferentes
keys para ambientes». Conclusión verificable: **el ambiente se separa por API
Key, no por URL**. Por eso un requisito del sistema es que una clave de TEST no
pueda apuntar a producción (`DOSA_EMISSION_ENVIRONMENT` + bandera explícita).

**Pendiente del proveedor:** confirmar si una API Key de TEST contra el endpoint
único devuelve comprobantes de prueba de la DGII (`testecf`) y si existe algún
verificador de entorno en la respuesta.

## 3. Respuesta — forma real (plana, no envuelta en `data`)

```json
{
  "trackId": "4cdc9917-8008-4564-a85c-c3f13a4e0ec8",
  "codigo": "4",
  "estado": "Aceptado Condicional",
  "rnc": "101742186",
  "encf": "E320000000004",
  "url": "https://ecf.dgii.gov.do/testecf/consulta...",
  "codigoSeguridad": "EAkbyR",
  "fechaFirma": "15-11-2025 14:46:41",
  "secuenciaUtilizada": true,
  "fechaRecepcion": "2025-11-15T10:46:42",
  "mensajes": [{ "valor": "El campo MontoGravadoI1 del área Totales...", "codigo": 1934 }]
}
```

Hechos que cambian la implementación:

1. La respuesta es **plana**. Nuestro clasificador acepta también `{ data: … }`
   por tolerancia, pero la forma documentada es la de arriba.
2. **`codigo` viene como cadena** (`"4"`), aunque el campo se describa como
   numérico. Se conserva con su tipo primitivo, sin coerción.
3. **`secuenciaUtilizada`** existe y es lo que dice si la secuencia se consumió.
4. **No hay campo `qr`.** El QR se compone de `url` + `codigoSeguridad` +
   `fechaFirma` + `encf` + `rnc`.
5. `mensajes` es un array de `{ valor, codigo }` con el error de DGII.

## 4. Códigos de estado — y el conflicto del 0

| Código | Estado (tabla oficial) |
| --- | --- |
| 0 | No encontrado |
| 1 | Aceptado |
| 2 | Rechazado |
| 3 | En proceso |
| 4 | Aceptado Condicional |

El **mismo documento** incluye un ejemplo de manejo donde `codigo === "0"` se
trata como «Rechazado - analizar errores y corregir». Dos fuentes del mismo
proveedor se contradicen. Decisión: `0` se queda en `UNRESOLVED`, porque
interpretarlo como rechazo daría por fallido un comprobante que quizá sí exista,
e interpretarlo como aceptado sería peor.

`Aceptado` y `Aceptado Condicional` son los estados que el proveedor considera
aprobados; **ninguno de los dos activa nada** en FullPOS: la respuesta del
proveedor es evidencia, no autorización fiscal.

## 5. E32 pequeño = RFCE, sin `trackId`

Las facturas de consumo (E32) menores a RD$250 000 se envían como **Resumen de
Factura de Consumo (RFCE)**. La respuesta trae el estado real de la DGII y
**no lleva `trackId`**. Ya no existe el estado «Enviado Resumen».

Si el resumen no llega a la DGII, la respuesta es **HTTP 502** con
`estado: "Error de envío"`. En ese caso la DGII no recibió nada y el proveedor
indica que se puede **reintentar con el mismo eNCF**. Es el único caso donde el
reintento con el mismo comprobante es seguro, y así está codificado
(`safeToRetrySameEncf` / `retryPermitted`).

## 6. Secuencias — recomendaciones contradictorias

- «Nunca reutilizar una secuencia, incluso si el envío falló».
- FAQ: «Si un envío falla, debe usar una nueva secuencia para el reintento».
- Formato: `E[tipo][11 dígitos]`, p. ej. `E310000000001`.
- Errores 1002 = secuencia duplicada.

Frente a eso, el documento también recomienda «reintentos automáticos para
errores de red (máximo 3)». Ambas cosas no pueden ser ciertas a la vez para el
mismo comprobante. Decisión de FullPOS: el cliente **no reintenta solo**; un
reintento es un acto explícito que consume una secuencia nueva (o el mismo eNCF
solo cuando el proveedor dice que no recibió nada).

## 7. Tipos de eCF documentados

`E31`, `E32`, `E33`, `E34`, `E41`, `E43`, `E44`, `E45`, `E46`, `E47`.
FullPOS implementa y declara **solo E31, E32 y E34**. Los demás están
documentados por el proveedor pero no mapeados aquí.

## 8. Lo que sigue sin documentarse

- Algoritmo de `X-Dosa-Signature` del webhook (el representante escribió
  «`X-Dosa-Signature = secret`», que no especifica algoritmo).
- Endpoint de **consulta de estado** de un eCF ya enviado. El documento solo
  describe el envío. Por eso `querySupported: false` en el adaptador.
- Formato exacto de fecha en el request: el documento dice `DD-MM-YYYY` y el
  catálogo de errores 1003 lo confirma; queda como verificado por el catálogo,
  no por un ejemplo de request completo.
- Alcance de una API Key: ¿una empresa o varias bajo el mismo partner?
