# DOSA — contrato de emisión verificado contra la documentación oficial

Fuente: `https://github.com/alapaix13/DosaInvoicecloud-Documentation`
(`README.md`, 71 668 bytes descargados de `raw.githubusercontent.com` el
2026-11-02). Todo lo de abajo es **HECHO** leído del documento; lo que no está en
el documento se marca como **NO DOCUMENTADO**.

## 0. Campos de línea (`detallesItems.items`) — verificados

| Campo | Tipo según el documento | Valores |
| --- | --- | --- |
| `numeroLinea` | Integer, requerido | secuencial |
| `indicadorFacturacion` | Integer, requerido | **tasa de ITBIS de la línea**: 1 = ITBIS 18 %, 2 = 16 %, 3 = 0 %, 4 = exento, 0 = no facturable. NO indica si es bien o servicio |
| `nombreItem` | String, requerido | descripción |
| `indicadorBienoServicio` | Integer, requerido | **1 = bien · 2 = servicio** |
| `cantidadItem` | Decimal, requerido | cantidad |
| `unidadMedida` | Integer, **opcional** | código del catálogo de la DGII (**43 = Unidad**, 41 = Yarda…) |
| `precioUnitarioItem` | Decimal, requerido | precio unitario |
| `montoItem` | Decimal, requerido | cantidad × precio |

> **Corregido el 2026-11-07.** Esta tabla describía el contrato **anterior** del
> proveedor. DOSA publicó una corrección («Versiones anteriores de este
> documento tenían códigos que no son los de la DGII») y el mapeador
> (`dosa-ecf.mapper.ts`) ya la implementa. La **referencia canónica** es
> [`docs/ecf/research/DOSA_EMISSION_API_2026-11.md`](ecf/research/DOSA_EMISSION_API_2026-11.md)
> §4 y §4.1. Enviar los códigos antiguos produce comprobantes con indicadores
> fiscales equivocados.

### Catálogo de Unidades de Medida (tabla vigente de la DGII)

Tabla completa y fuentes en
[`DOSA_EMISSION_API_2026-11.md`](ecf/research/DOSA_EMISSION_API_2026-11.md) §4.1.
Solo se listan las unidades que FullPOS puede producir:

| Código DGII | Unidad | Código FullPOS |
| --- | --- | --- |
| 43 | Unidad | `UNIT` |
| 6 | Caja | — |
| 21 | Kilogramo | `KILOGRAM` |
| 17 | Gramo | `GRAM` |
| 23 | Libra | `POUND` |
| 26 | Metro | `METER` |
| 8 | Centímetro | — |
| 55 | Pulgada | `INCH` |
| 33 | Pie | `FOOT` |
| 41 | Yarda | `YARD` |
| 24 | Litro | `LITER` |
| 15 | Galón | `GALLON` |
| 13 | Docena | — |
| 31 | Paquete | — |
| 19 | Hora | — |
| 12 | Día | — |

**Onza, mililitro, servicio y mes no existen en la tabla de la DGII.** El campo
es opcional: si la unidad de FullPOS no tiene equivalencia, se omite en lugar de
inventar un código.

Implementado en `DOSA_UNIDAD_MEDIDA_BY_FULLPOS_CODE`
(`apps/api/src/ecf/provider/dosa/dosa-ecf.mapper.ts`). Un código de unidad que no
esté en la tabla **bloquea el documento** con
`DOSA_UNIT_OF_MEASURE_UNMAPPED:<línea>:<código>`: no se adivina la equivalencia ni
se envía un valor por defecto. Los códigos 2, 8 y 15–20 existen en DOSA pero hoy
FullPOS no puede producirlos porque no tiene esas unidades en
`unit_of_measures`.

### `codigoModificacion` (notas de crédito)

Causa de la nota de crédito, en `Referencia.CodigoModificacion`:

| Código | Causa |
| --- | --- |
| 1 | Anulación |
| 2 | Corrección de texto |
| 3 | Corrección de montos |

Procedencia: el documento **`NOTAS_CREDITO_DESDE_FACTURA.md` entregado por el
propietario del producto**. El README público del proveedor **no publica la
tabla**: solo sus ejemplos de E34 usan `1`. Por eso el valor viaja desde el
llamador y el mapeador **nunca lo rellena por defecto**:

- sin código → `DOSA_MODIFICATION_CODE_REQUIRED`;
- código fuera de 1/2/3 (por ejemplo el `4` que admite el modelo de Alanube) →
  `DOSA_MODIFICATION_CODE_UNSUPPORTED:<código>`.

Se prefiere bloquear a declarar una causa de modificación que nadie eligió.

### Endpoint: `EnviarFactura` vs `NotaDesdeFactura`

El proveedor documenta dos rutas distintas, y el cliente de emisión **enruta por
tipo de comprobante** (`emissionPathFor`):

| e-CF | Endpoint |
| --- | --- |
| E31, E32 | `/fe/api/emision/ecf/EnviarFactura` |
| E34 | `/fe/api/emision/ecf/NotaDesdeFactura` |

Antes se enviaba todo a `EnviarFactura`: una nota de crédito habría ido al
endpoint equivocado.

Otro conflicto del mismo documento: los ejemplos de `NotaDesdeFactura` usan
claves PascalCase (`Encabezado`, `DetallesItems.Items`, `Referencia`) mientras el
ejemplo de `EnviarFactura` usa camelCase. FullPOS emite camelCase, que es la
forma del ejemplo del endpoint de envío. Queda como brecha declarada.

### Contenido del catálogo de unidades: lo que NO se mapea

DOSA documenta 20 códigos; FullPOS solo puede producir 12. Los códigos **2
Caja, 8 Centímetro, 15 Docena, 16 Paquete, 17 Servicio, 18 Hora, 19 Día y 20
Mes** no tienen unidad equivalente en `unit_of_measures`, así que no se mapean:
`17 = Servicio` es una unidad del catálogo, no una instrucción de «usa 17 para
las líneas de servicio» (la naturaleza del ítem ya viaja en
`indicadorBienoServicio`). Antes de mapearlos hace falta una decisión de producto
(códigos de unidad nuevos), no un cambio silencioso del mapeador.

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
