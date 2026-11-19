# Definición técnica de cada plan (paquete que se aplica al activar)

**Estado**: matriz **ya publicada en el sitio** (2026-11-16) y **pendiente de implementar en el
servidor** (catálogo de APPYRA y límites por plan).
Base comercial: [`04-catalogo-oficial-planes.md`](./04-catalogo-oficial-planes.md) (web publicada).
Verificado contra `origin/production-main` (`e6e7e8fc`), que es la versión real de producción.

---

## 0. Glosario: qué significa cada estado (esto resuelve la duda)

| Palabra | Significado exacto | Ejemplo |
| --- | --- | --- |
| **Incluido** | El plan da **derecho** a usar esa función. El cliente puede encenderla cuando quiera. | e-CF en Negocio |
| **Encendido** | Viene **ya funcionando** desde el primer día. **Solo** aplica a lo estructural (inventario y módulo de almacenes). | Inventario |
| **Apagado** | Está **incluida**, pero el interruptor viene en off. El cliente lo enciende cuando lo necesite. **No** significa que no lo tenga. | Todas las funciones incluidas |
| **Bloqueado** | **No** está incluida. El servidor la rechaza aunque el cliente la pida. | e-CF e impuestos en Básico |

> **Regla de oro**: todo lo que el cliente paga llega **apagado**. Nada se enciende solo al activar el
> plan. El cliente enciende únicamente lo que necesita, desde Configuración.

> Cuando antes escribí «apagado» quería decir **incluido con el interruptor en off**, nunca
> «no lo tiene». De ahora en adelante uso estas cuatro palabras y nada más.

## 1. Principio: el plan es un paquete que aplica el servidor

1. El cliente **elige** un plan; nunca escribe precios, cuotas ni interruptores.
2. El servidor tiene el **catálogo** (código, precio, cuotas, interruptores).
3. Al **activar** (por comprobante, según tu decisión), el servidor copia ese paquete a la empresa:
   cuotas + interruptores + periodo.
4. El cliente **no puede** cambiar su plan ni sus cuotas: solo puede comprar otro paquete.
5. Cada activación queda en auditoría con el plan aplicado y su versión de catálogo.

## 2. Interruptores reales que existen hoy (verificados)

Todos viven en `Company` (`apps/api/prisma/schema.prisma`) y **ya se aplican** en el código:

| Interruptor | Campo | Qué cambia cuando está en `false` | Dónde se aplica |
| --- | --- | --- | --- |
| Impuestos (ITBIS) | `taxEnabled` | Las ventas no calculan ni cobran impuestos | `settings`, `sales`, `tax` |
| Facturación electrónica | `ncfEnabled` | Rechaza emitir con tipo de comprobante e-CF | `settings`, `sales` (l.1813), `tax` |
| Inventario | `inventoryEnabled` | Desactiva el control de stock (solo si se pone `false` explícito) | `products`, `inventory` |
| Unidad de medida | `measurementUnitsEnabled` | No permite usar unidades distintas de la básica | `products`, `inventory` |
| Multi-almacén | `multiWarehouseEnabled` | **Apaga el módulo entero** (consultar, crear y terminales) | `warehouses` |
| **Mayoreo / listas de precio** | `wholesalePriceListsEnabled` | Bloquea las listas de precio al por mayor | `price-lists`, `sales` |

Cuotas existentes: `maxUsers` (def. 2) y `maxProducts` (def. 100).
**No existe** `maxWarehouses`: hay que añadirlo para que «1 almacén» (Básico y Negocio) y los límites de Pro y Empresa sean verdad.

`guardianEnabled` (APPYRA Guardian) **no** es un beneficio comercial: es instrumentación interna
desactivada por defecto. No entra en ningún plan.

### ⚠ Hallazgo importante sobre `multiWarehouseEnabled`

Este interruptor **no** limita el número de almacenes: **apaga el módulo completo**.
`warehouses.service.ts` llama a `assertMultiWarehouseEnabled` en `list`, `listTerminals`, `create`,
`update`, `activate`, `deactivate` y transferencias; si está en `false` responde
`BadRequestException: «La gestion de multiples almacenes no esta activa para esta empresa»`.

Consecuencia: si Básico se queda con `multiWarehouseEnabled = false`, ese cliente **no puede ni
consultar ni gestionar su único almacén**, y hay pantallas del POS que podrían dejar de funcionar.

**Recomendación**: que el módulo esté **activo en los cuatro planes** y que lo que cambie sea
`maxWarehouses` (1 / 1 / 5 / 10). «Sin multi-almacén» significaría entonces «no puedes crear un
segundo almacén», que es lo que la web promete («1 almacén»).

## 3. Matriz definitiva de los cuatro planes

Leyenda: ✅ incluido y encendido · ⚪ incluido y apagado (el cliente lo enciende) · ❌ bloqueado

| Concepto | **Básico** | **Negocio** | **Pro** | **Empresa** |
| --- | --- | --- | --- | --- |
| **Precio mensual** | **RD$1,000** | **RD$2,500** | **RD$3,500** | **RD$5,000** |
| **Productos** | 100 | 400 | 1,000 | 5,000 |
| **Usuarios** | 1 | 3 | 4 | 7 |
| **Almacenes (máx.)** | 1 | **1** | 5 | 10 |
| **Multi-almacén (función)** | ❌ | ❌ | ✅ | ✅ |
| Módulo de almacenes (técnico) | ✅ | ✅ | ✅ | ✅ |
| Inventario | ✅ | ✅ | ✅ | ✅ |
| **Unidad de medida** | ⚪ incluido, apagado | ⚪ incluido, apagado | ⚪ incluido, apagado | ⚪ incluido, apagado |
| **Mayoreo / listas de precio** | ❌ **bloqueado** | ⚪ incluido, apagado | ⚪ incluido, apagado | ⚪ incluido, apagado |
| **Impuestos (ITBIS)** | ❌ **bloqueado** | ⚪ incluido, apagado | ⚪ incluido, apagado | ⚪ incluido, apagado |
| **Facturación electrónica** | ❌ **bloqueada** | ⚪ **incluida**, apagada | ⚪ incluida, con **más uso** | ⚪ incluida, con **mayor uso** |
| Texto comercial de e-CF | «No incluye» | «Facturación electrónica incluida» | «Más uso de facturación electrónica» | «Facturación electrónica ampliada» |
| Postulación e-CF con asistente | ❌ | ✅ | ✅ | ✅ |
| Soporte (texto, no se valida) | Estándar | Prioritario | Más rápido | Extendido + arranque |
| Prueba | 7 días | 7 días | 7 días | 7 días |

### Qué cambió respecto a la versión anterior

| Punto | Antes (mal) | Ahora (tu decisión) |
| --- | --- | --- |
| e-CF en Básico | Incluida y apagada | **Bloqueada**: el cliente no puede activarla |
| Impuestos en Básico | Incluidos y apagados | **Bloqueados**: el cliente no puede activarlos |
| e-CF en Negocio | Incluida (igual) | **Incluida**, apagada hasta que el cliente la active |
| e-CF en Pro y Empresa | Mismo texto | **«Más uso»** / «mayor uso», sin publicar cifras |
| Cifras de e-CF | No existían | **Hay cupo por plan, pero no se publica el número** |
| **Multi-almacén en Negocio** | Lo tenía | **No lo incluye**: Negocio se queda en **1 almacén** |
| Unidad de medida y mayoreo | Encendidos por defecto | **Incluidos y apagados**: el cliente los enciende |
| Precios | 1.000 / 2.000 / 3.000 / 4.500 | **1.000 / 2.500 / 3.500 / 5.000** |

### Por qué la escalera queda así

Dijiste que el plan que incluye facturación fiscal «debería ser por lo menos 2.500», y que Pro debe ser
3.500 y Empresa 5.000. Como el plan de 2.500 es justamente el que **sí** incluye e-CF (Negocio), la
escalera coherente queda:

**1.000** (sin e-CF ni impuestos) → **2.500** (con e-CF) → **3.500** → **5.000**

Esto elimina el problema anterior: ya no existe un plan barato con facturación fiscal, y ningún plan
cuesta más que el superior.

> **La web publica hoy otra cosa** (2.000 · 3.000 · 4.500 y «facturación electrónica opcional» en
> Básico). Hay que actualizarla el mismo día que el catálogo o volveremos a tener dos verdades.

## 3b. Cupos internos de e-CF (nunca se publican)

Dijiste: «hay un límite por plan, pero no vamos a identificar por eso; en Pro y Empresa debe decir más
uso». Traducción técnica: **el sistema aplica un cupo por plan, pero la interfaz no muestra el número**,
solo las expresiones «incluida», «más uso» y «mayor uso».

| Plan | Comprobantes e-CF al mes (interno) | Lo que ve el cliente |
| --- | --- | --- |
| Básico | **0 (bloqueado)** | «No incluye facturación electrónica» |
| Negocio | 300 | «Facturación electrónica incluida» |
| Pro | 1.500 | «Más uso de facturación electrónica» |
| Empresa | 5.000 | «Facturación electrónica ampliada» |

Los números son **propuesta mía** y viven en el catálogo del servidor: se cambian sin tocar la app.

> ⚠ **Riesgo de un límite invisible**: si el cliente llega al cupo y no lo sabe, deja de poder emitir
> a mitad de una venta. Recomendación: avisar en la app con «uso alto» al 80 % y, al llegar al 100 %,
> ofrecer subir de plan **mostrando el cupo en ese momento**. El número solo se oculta mientras no
> moleste; esconderlo cuando ya bloquea es peor que publicarlo.

## 3c. Excepciones autorizadas por empresa (lo que tú puedes conceder)

El propietario puede dar **más de lo que el plan incluye**, sin cambiar de plan. Ejemplo: Básico con
1 usuario más, o con 200 productos extra.

### Cómo se hace: con el botón **Editar** de esa licencia (sin pantalla nueva)

En el CRM ya existe **Editar** en el menú de acciones. Ahí se abre la ficha de esa persona y se puede
cambiar todo lo que hoy está fijo por el plan:

- **Datos de la empresa**: nombre y demás información editable.
- **Plan** asignado.
- **Límites**: subir o bajar usuarios, productos y almacenes.
- **Funciones**: encender o apagar e-CF, impuestos, mayoreo y unidad de medida.
- **Fechas**: vencimiento y periodo.
- **Notas y motivo** del cambio.

Todo lo que se cambie ahí queda como **excepción de esa empresa** (no altera el plan de las demás) y
queda auditado con actor y fecha.

| Qué se concede | Campo de la excepción | Ejemplo |
| --- | --- | --- |
| Usuarios extra | `extraUsers` | +2 |
| Productos extra | `extraProducts` | +200 |
| Almacenes extra | `extraWarehouses` | +1 |
| Permitir facturación electrónica | `allowEcf` | Básico con e-CF |
| Permitir impuestos | `allowTaxes` | Básico con ITBIS |
| Permitir mayoreo | `allowWholesale` | Básico con listas de precio |
| Permitir unidad de medida | `allowUom` | Básico con UoM |
| Motivo, quién y hasta cuándo | `note`, `grantedBy`, `expiresAt` | «Acuerdo comercial hasta 31/12/2026» |

### Reglas de las excepciones

1. **Se suman, no sustituyen**: límite efectivo = límite del plan **+ extra**. Así, si el cliente
   cambia de plan, la excepción sigue teniendo sentido.
2. **Función efectiva = incluida en el plan *o* autorizada por excepción.** Una excepción puede
   encender e-CF en Básico sin cambiar de plan.
3. **Motivo obligatorio** y auditoría con actor y fecha. Opcionalmente con **caducidad**.
4. **Al caducar o retirarse no se borra nada**: se bloquean altas nuevas y se avisa qué debe reducir.
5. **El cliente lo ve**: en Planes aparece «Ampliación autorizada por FULLTECH» con el detalle, para
   que no vea un límite que no cuadra con su plan.

> Esto es lo que permite atender a un cliente especial sin inventar un plan nuevo ni tocar la base.

## 4. Por qué, cuando están incluidas, vienen apagadas

Esto aplica **solo a los planes que sí las incluyen** (Negocio, Pro y Empresa).

No es una limitación comercial: es el estado seguro.

- **Impuestos**: apagados hasta que el cliente configure su tasa. Si se encendieran solos, una venta
  podría salir con un impuesto que el negocio no aplica.
- **e-CF**: apagada hasta que el cliente tenga certificado y configuración DGII. Encenderla antes no
  haría que emitiera: el sistema rechazaría la emisión por falta de configuración.

En esos planes el cliente **puede encenderlas él mismo** desde Configuración.
En **Básico no son un «apagado»: son un bloqueo**. El servidor debe rechazar el intento y explicar
que el plan no las incluye, con la vía para subir a Negocio.

### Excepciones a la regla (solo dos, y son técnicas)

| Función | Estado al activar | Por qué no puede llegar apagada |
| --- | --- | --- |
| **Inventario** | **encendido** | Es el núcleo del POS: sin control de stock las ventas no descuentan. El cliente puede apagarlo si no lo usa. |
| **Módulo de almacenes** | **encendido** | Apagarlo **no** limita la cantidad: rompe `list`, `create` y `terminales` del módulo. El límite real es `maxWarehouses` (1/1/5/10). |

**Todo lo demás** —unidad de medida, mayoreo, impuestos y facturación electrónica— llega **apagado**
aunque esté incluido en el plan.

> **Importante sobre Básico y Negocio**: que el módulo técnico esté activo **no** significa que
> incluyan multi-almacén. Significa que pueden **gestionar su único almacén**. La función multi-almacén
> (crear un segundo) está **bloqueada** hasta Pro.

### ⚠ Choque con la web publicado en Negocio

La web dice hoy que **Negocio incluye «1 a 2 almacenes»**. Con esta decisión, Negocio se queda en **un
almacén**, así que esa línea pasa a ser falsa. Hay que corregirla a **«1 almacén»** (o a
**«2 almacenes»** con multi-almacén incluido, si al final prefieres eso).

### Al cambiar de plan (regla para no sorprender)

- **Lo que el nuevo plan incluye**: se respeta lo que el cliente ya había encendido. No se apaga.
- **Lo que el nuevo plan no incluye**: se **apaga y se bloquea**, con aviso previo y explicación.
  Ejemplo: bajar de Pro a Básico apaga y bloquea e-CF e impuestos.
- Nunca se borran datos: se apaga la función y se conserva todo lo configurado.

## 5. Qué pasa exactamente al activar

```
Cliente elige plan → orden con precio del catálogo (servidor)
   → sube comprobante → (verificación tuya / automática)
   → ACTIVAR:
        Company.planCode        = 'basico' | 'negocio' | 'pro' | 'empresa'
        Company.maxUsers        = 2 | 5 | 10 | 20
        Company.maxProducts     = 100 | 400 | 1,000 | 5,000
        Company.maxWarehouses   = 1 | 1 | 5 | 10        ← campo nuevo
        Company.multiWarehouseEnabled      = true  (estructural: ver excepciones)
        Company.wholesalePriceListsEnabled = false (el cliente lo enciende) o bloqueado en Básico
        Company.measurementUnitsEnabled    = false (el cliente lo enciende)
        Company.ncfEnabled                 = false (el cliente lo enciende) o bloqueado en Básico
        Company.taxEnabled                 = false (el cliente lo enciende) o bloqueado en Básico
        Company.licenseStatus   = ACTIVE
        Company.licenseExpiresAt = hoy + 1 mes
        licenseNotes            = 'Activación con comprobante pendiente de verificación (orden RD-…)'
   → auditoría: plan aplicado, versión de catálogo, actor, orden
```

### Reglas que hay que respetar al aplicar el paquete

1. **Bajar de plan nunca borra datos.** Si el cliente tiene 8 usuarios y pasa a Básico (2), no se
   borra nadie: se bloquean **nuevas** altas y se le avisa qué debe reducir.
2. **Subir de plan** aplica de inmediato las cuotas nuevas.
3. **Cambiar de plan** a mitad de mes: se aplica al periodo siguiente salvo decisión expresa
   (prorrateo = decisión pendiente D6).
4. **El paquete se aplica siempre desde el servidor**, nunca desde la app.
5. Si el plan cambia en el catálogo, **las empresas ya activadas no cambian solas**: se aplica en su
   próxima renovación y queda registrado con la versión del catálogo.

## 6. Cómo se guarda el plan (decisión técnica propuesta)

Hoy `Company.plan` es un enum de dos valores (`STANDARD`, `ENTERPRISE`) que **no** sirve para cuatro
planes. Propuesta:

- Añadir `Company.planCode String?` con `basico` / `negocio` / `pro` / `empresa`.
- Mantener el enum `CompanyPlan` por compatibilidad, sincronizado (`STANDARD` ↔ basico/negocio,
  `ENTERPRISE` ↔ pro/empresa) hasta retirarlo.
- El catálogo (`LicensePlan`) guarda: `code`, `name`, `version`, `monthlyPrice`, `maxUsers`,
  `maxProducts`, `maxWarehouses`, `multiWarehouse`, `wholesale`, `uom`, `ecf`, `tax`, `active`.
- La orden guarda `planCode` + `catalogVersion`, para que un cambio de precio no altere órdenes ya
  creadas.

## 7. Verificación de que el plan «es válido»

Para poder decir que los planes funcionan de verdad, cada uno necesita estas pruebas:

| Prueba | Básico | Negocio | Pro | Empresa |
| --- | --- | --- | --- | --- |
| Crear usuario 3 / 6 / 11 / 21 → rechazado con `PLAN_LIMIT_REACHED` | ✅ | ✅ | ✅ | ✅ |
| Crear producto 101 / 401 / 1.001 / 5.001 → rechazado | ✅ | ✅ | ✅ | ✅ |
| Crear almacén 2 / 3 / 6 / 11 → rechazado | ✅ | ✅ | ✅ | ✅ |
| Intento de lista de precio mayorista en Básico → rechazado | ✅ | — | — | — |
| Venta por caja/libra en Básico → rechazado | ✅ | — | — | — |
| Impuestos apagados por defecto, activables | ✅ | ✅ | ✅ | ✅ |

Sin estas pruebas, «poner el plan» sería solo cambiar un número en pantalla.

## 8. Decisiones pendientes para cerrar la matriz

> **Actualización 2026-11-16**: el propietario no estaba disponible para responder; las propuestas de
> esta sección se adoptan **por defecto y son revisables**. Ver [`07-plan-implementacion.md`](./07-plan-implementacion.md).

### Ya resueltas con tu mensaje de hoy

| # | Decisión | Resultado |
| --- | --- | --- |
| P-2 | e-CF en Básico | **Bloqueada** (no incluida) |
| P-2b | e-CF en Negocio | **Incluida**, apagada hasta que el cliente la active |
| P-2c | e-CF en Pro y Empresa | Incluida con **más uso**, sin publicar cifra |
| P-4 | Unidad de medida | **Encendida desde Básico** |
| P-5 | Impuestos en Básico | **Bloqueados** (no incluidos) |
| P-5b | Impuestos en Negocio, Pro y Empresa | **Incluidos**, apagados hasta que el cliente los active |
| P-8 | Escalera de precios | **1.000 · 2.500 · 3.500 · 5.000** |
| P-10 | Estado inicial de todo beneficio incluido | **Apagado**, salvo inventario y módulo de almacenes (excepciones técnicas) |

### Siguen abiertas

| # | Pregunta | Mi propuesta |
| --- | --- | --- |
| **P-1** | Almacenes de **Pro** y **Empresa** | Pro 5 · Empresa 10 |
| **P-3** | ¿**Mayoreo** desde Negocio o solo en Pro? | Desde Negocio |
| **P-6** | ¿«Empresa» existe en el sistema de cobro? | Crearla, porque la web ya la vende |
| **P-7** | ¿Módulo de almacenes activo en los 4 con límite 1/1/5/10? | Sí: el interruptor apaga el módulo entero |
| **P-9** | **Cupos internos de e-CF** por plan (nunca se publican) | Negocio 300 · Pro 1.500 · Empresa 5.000 al mes (ver §3b) |

Con **P-8** cerrada no hay contradicciones de precio; con **P-1, P-7 y P-9** los planes quedan aplicables.
