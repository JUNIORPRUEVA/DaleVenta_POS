# Catálogo oficial de planes (publicado en la web)

**Fuente de verdad**: sitio desplegado `https://fullposcloud.fulltechrd.com/precios`
(consultado 2026-11-16) y su código en
`origin/production-main:website/src/config/site.ts` (commit `4e20dc4e`
«franja de facturacion electronica y pago por transferencia», 2026-11-15).

Los planes **no se inventan aquí**: se copian de lo publicado. Lo que no está publicado se marca
como hueco, no se rellena.

> **⚙ Precios y módulos ya actualizados en el sitio (2026-11-16)**: la web publica la escalera
> **1.000 · 2.500 · 3.500 · 5.000** y el reparto de módulos de
> [`05-definicion-tecnica-de-planes.md`](./05-definicion-tecnica-de-planes.md) §3: Básico **sin** e-CF,
> sin impuestos y sin mayoreo; multi-almacén **desde Pro**; almacenes 1 / 1 / 5 / 10. Cambios en
> `website/src/config/site.ts`, `pages/precios.astro`, `pages/index.astro`, `pages/funciones.astro`
> y `styles/global.css`.
>
> **Pendiente de alinear (dos verdades abiertas)**:
> 1. El catálogo de APPYRA (`daleventas_commercial_plans`) conserva los precios anteriores, y su
>    restricción `ck_daleventas_commercial_plan_code` **sólo admite `BASIC`, `BUSINESS`, `PRO`**: el
>    plan Empresa no se puede guardar sin migración.
> 2. La app (`apps/fulltech_app/.../landing_screen.dart`) sigue mostrando la lista vieja.

---

## 1. Los cuatro planes publicados

| | **Básico** | **Negocio** *(más elegido)* | **Pro** | **Empresa** |
| --- | --- | --- | --- | --- |
| **Precio** | RD$1,000 **al mes** | RD$2,500 **al mes** | RD$3,500 **al mes** | RD$5,000 **al mes** |
| **Resumen publicado** | «Para empezar a vender sin complicarte» | «El equilibrio entre precio y capacidad» | «Para operaciones con más movimiento» | «Capacidad máxima y acompañamiento» |
| Productos | **100** | **400** | **1,000** | **5,000** |
| Usuarios | **1** | **3** | **4** | **7** |
| Almacenes | **1** | **1** | **Hasta 5** | **Hasta 10** |
| Multi-almacén | **No** | **No** | **Sí** | **Sí** |
| Impuestos (ITBIS) | **No** | **Sí** | **Sí** | **Sí** |
| Mayoreo y listas de precio | **No** | **Sí** | **Sí** | **Sí** |
| Facturación electrónica | **No incluye** | **Incluida** | **Más uso** | **Ampliada** |
| Soporte | Estándar | Prioritario | Más rápido | Extendido y arranque |
| Prueba | 7 días gratis | 7 días gratis | 7 días gratis | 7 días gratis |

### Beneficios comunes a los cuatro planes (`planIncludes`)

1. Prueba de 7 días gratis
2. Windows, Android, iPhone y web
3. Los mismos datos en todos los dispositivos
4. Datos separados por empresa
5. Actualizaciones incluidas
6. Soporte por WhatsApp

### Condiciones publicadas

- **Medio de pago único: transferencia bancaria.** La web lo dice en portada, precios, soporte,
  descargas, registro y pie: «El único medio de pago del plan es la transferencia bancaria».
- **7 días de prueba** y después se elige plan.
- **e-CF**: la postulación se hace con el asistente guiado incluido; **la aprobación la decide la
  DGII**, el certificado digital **no** está incluido y el acompañamiento gestionado es un servicio
  aparte.
- Contacto publicado: WhatsApp **829-436-3936** (`wa.me/18294363936`).

## 2. Qué es aplicable hoy y qué no

### 2.1 Regla publicada: los módulos ya no son iguales en los cuatro planes

La web **decía** «Todos los planes incluyen los mismos módulos en todos tus dispositivos». Desde el
2026-11-16 esa frase se retiró: las páginas de portada y precios dicen que cambian «la capacidad, los
módulos incluidos y el nivel de soporte», cada tarjeta lista sus módulos y las que no los tienen
muestran un bloque **«No incluye»**. En `/funciones` cada módulo indica desde qué plan está incluido
(«Desde Negocio», «Desde Pro»).

Esto importa porque el código ya tiene banderas por empresa (`multiWarehouseEnabled`,
`measurementUnitsEnabled`, `inventoryEnabled`, `ncfEnabled`, `wholesalePriceListsEnabled`) que hoy se
activan a mano y **no** están ligadas a ningún plan.

Cada beneficio publicado, contra el código real de `apps/api`:

| Beneficio publicado | Dónde se aplica hoy | Estado |
| --- | --- | --- |
| 100 / 400 / 1,000 / 5,000 productos | `Company.maxProducts` + `assertCanCreateProduct` | **Aplicable ya** |
| 2 / 5 / 10 / 20 usuarios | `Company.maxUsers` + `assertCanCreateUser` | **Aplicable ya** |
| Multi-almacén / multi unidad de medida | Banderas `multiWarehouseEnabled` y `measurementUnitsEnabled` (se activan a mano) | **Aplicable ya**, pero desligado del plan |
| Inventario | `inventoryEnabled` | **Aplicable ya** |
| 1 almacén (Básico y Negocio) | `Company` **no** tiene `maxWarehouses`; `getAdminCompanyUsage` devuelve `warehouses: enforced:false` | **Falta implementar** |
| «Hasta 5» (Pro) / «Hasta 10» (Empresa) | Igual | **Falta implementar** el límite ya publicado |
| e-CF: no incluye / incluida / más uso / ampliada | Solo existe el booleano `Company.ncfEnabled` | **Falta definir**; «más uso» no tiene medición ni cupo aplicado |
| Mayoreo y listas de precio (bloqueado en Básico) | `wholesalePriceListsEnabled` | **Aplicable ya**, pero hoy no se bloquea por plan |
| Postulación e-CF gratis con asistente | Proceso, no límite | **Informativo** (no se valida en código) |
| Soporte estándar / prioritario / más rápido / extendido | No hay nada en código | **Informativo** (nivel de servicio) |
| 7 días de prueba | `trialEndsAt = now + 7 días` | **Aplicable ya** |
| Windows/Android/iPhone/web · mismos datos · datos separados · actualizaciones | Ya es así | **Aplicable ya** |
| Pago por transferencia | No existe flujo de comprobante aún | **Falta implementar** (es el objetivo) |

## 3. Huecos que impiden decir «los planes son válidos»

| ID | Hueco | Por qué importa | Qué hace falta |
| --- | --- | --- | --- |
| **C-1** | Pro y Empresa **no publican número de almacenes** | No se puede aplicar un límite que no existe | Decidir cifra (propuesta abajo) o cambiar el texto publicado |
| **C-2** | e-CF por niveles **sin definición técnica** | «Mayor capacidad de facturación» no significa nada operativo | Decidir: booleano simple o cuota mensual de comprobantes |
| **C-3** | La **app contradice la web** | El cliente ve dos precios distintos | Alinear app con web (ver §4) |
| **C-4** | La app anuncia **cajas/terminales** y la web **no** | Se promete algo que no está publicado ni aplicado | Quitar de la app |
| **C-5** | En la app el precio es **3 × mensual** | Contradice «al mes» publicado | Quitar el total trimestral |

### Propuesta para C-1 (a confirmar por el propietario)

| Plan | Almacenes (propuesto) | Base |
| --- | --- | --- |
| Básico | 1 | Publicado |
| Negocio | 2 | Publicado («1 a 2») |
| Pro | **5** | Propuesta; la web solo dice «multi-almacén» |
| Empresa | **10** | Propuesta; la web solo dice «mayor capacidad» |

Si no se confirma, la alternativa es **no aplicar límite** en Pro/Empresa y dejarlo como texto
comercial, pero entonces el comparador no puede mostrar un número.

### Propuesta para C-2 (a confirmar)

| Plan | e-CF propuesto | Cuota mensual de comprobantes |
| --- | --- | --- |
| Básico | Opcional (se activa si el cliente lo pide) | Sin cuota / a definir |
| Negocio | Incluida | Sin cuota |
| Pro | Incluida | Cuota mayor (a definir) |
| Empresa | Incluida | Cuota ampliada (a definir) |

Mientras no haya cifra, lo honesto es aplicar **solo el interruptor** (`ncfEnabled`) y mostrar el
nivel como **informativo**, nunca como cuota.

## 4. La app contradice lo publicado — hay que corregirla

`apps/fulltech_app/lib/features/auth/presentation/landing_screen.dart`, constante `_plans`:

| Campo | App (hoy) | Web publicada | Acción |
| --- | --- | --- | --- |
| Negocio · mensual | RD$1,500 | **RD$2,000** | Corregir |
| Pro · mensual | RD$2,500 | **RD$3,000** | Corregir |
| Totales | 3 × mensual (3,000 / 4,500 / 7,500) | No existen; se paga **al mes** | Eliminar |
| Negocio · usuarios | 3 | **5** | Corregir |
| Pro · usuarios | 5 | **10** | Corregir |
| Almacenes | 1 / 2 / 3 | 1 / 1–2 / multi | Corregir |
| Cajas / terminales | 1 / 2 / 3 | **No se publica** | Eliminar |
| Empresa | No existe | **RD$4,500 · 5,000 productos · 20 usuarios** | Añadir |

## 5. Comparación de las tres fuentes (para que no vuelva a haber dudas)

| Plan | Web publicada (oficial) | App Flutter (hoy) | Migración administración |
| --- | --- | --- | --- |
| Básico | 1,000/mes | 1,000/mes (total 3,000) | 1,000 |
| Negocio | **2,000**/mes | **1,500**/mes (total 4,500) | **1,500** |
| Pro | **3,000**/mes | **2,500**/mes (total 7,500) | **2,500** |
| Empresa | **4,500**/mes | **no existe** | **no existe** |

> Conclusión: **la web es la única que coincide con lo que el propietario quiere cobrar hoy.**
> La app y la base administrativa están desactualizadas y deben alinearse a la web.

## 6. Lo que este catálogo implica para el flujo de pago

1. El plan elegido fija **precio, cuota de usuarios y cuota de productos** desde el servidor.
2. El periodo es **mensual** (la web dice «al mes»), no trimestral.
3. Se paga **por transferencia**: el cliente sube comprobante y, según la decisión del propietario,
   se activa de inmediato quedando **pendiente de verificación**.
4. El propietario puede **suspender** después (ya existe `blockCompany`: `BLOCKED`, corta sesiones,
   reversible).
5. Los niveles de soporte y la postulación e-CF son **texto comercial**: no se aplican en código.

## 7. Pendiente de confirmar por el propietario

- **C-1**: número de almacenes de Pro y Empresa (propuesta 5 y 10).
- **C-2**: qué significa exactamente «mayor capacidad de facturación» / «ampliada».
- Si se mantiene «Empresa» en la app aunque no exista hoy en la base administrativa.
