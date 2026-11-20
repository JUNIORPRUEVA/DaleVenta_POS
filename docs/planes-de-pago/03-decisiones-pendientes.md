# Decisiones pendientes del propietario

Ninguna la puede tomar el agente: afectan a dinero, contrato, ley o disponibilidad bancaria.
Formato: **P** = pregunta, **por qué bloquea**, **opciones**, **impacto si no se responde**.

> **Actualización 2026-11-16**: el catálogo **ya está publicado** en
> `https://fullposcloud.fulltechrd.com/precios`. D1 y D2 quedan **resueltos por publicación** y se
> detallan en [`04-catalogo-oficial-planes.md`](./04-catalogo-oficial-planes.md). Lo que sigue abierto
> son los números concretos que la web **no** publica (almacenes de Pro/Empresa y capacidad de e-CF).

---

## D1. Catálogo y precios vigentes — CERRADO (2026-11-16)

**Escalera definitiva decidida por el propietario:**

| Plan | Precio | Productos | Usuarios | Almacenes | e-CF | Impuestos |
| --- | --- | --- | --- | --- | --- | --- |
| Básico | **RD$1,000**/mes | 100 | 2 | 1 | ❌ bloqueada | ❌ bloqueados |
| Negocio | **RD$2,500**/mes | 400 | 5 | 1 | ⚪ incluida | ⚪ incluidos |
| Pro | **RD$3,500**/mes | 1,000 | 10 | 5* | ⚪ más uso | ⚪ incluidos |
| Empresa | **RD$5,000**/mes | 5,000 | 20 | 10* | ⚪ mayor uso | ⚪ incluidos |

\* almacenes de Pro/Empresa son propuesta (P-1).

**Multi-almacén**: solo Pro y Empresa. Básico y Negocio se quedan en **1 almacén** (decisión del
2026-11-16). La web dice hoy «1 a 2 almacenes» en Negocio: hay que corregirla.

**Regla de estado inicial**: todo beneficio incluido llega **apagado**; el cliente lo enciende si lo
necesita. Únicas excepciones: inventario y módulo de almacenes (razones técnicas).

**Pendiente operativo**: la web publica todavía 2.000 · 3.000 · 4.500 y «facturación electrónica
opcional» en Básico. Debe actualizarse **el mismo día** que el catálogo.

## D2. ¿Mensual o mínimo 3 meses? — RESUELTO

**Decisión vigente**: **mensual**. La web dice «al mes» en los cuatro planes y no menciona mínimo.
La app Flutter aún muestra totales de 3 meses: hay que quitarlos.

## D3. Almacenes: números que la web no publica — ABIERTO (C-1)

**P:** Pro dice «multi-almacén» y Empresa «mayor capacidad operativa», sin cifra.
**Bloquea:** el servidor no puede aplicar un límite que no existe, y el comparador no puede mostrar
un número inventado.
**Propuesta:** Pro **5**, Empresa **10**. Alternativa: dejar sin límite y que el texto siga siendo
comercial.

## D3b. Capacidad de facturación electrónica — RESUELTO (2026-11-16)

**Decisión**: hay un **cupo por plan**, pero **no se publica el número**. La app solo dice
«facturación electrónica incluida» (Negocio), «más uso» (Pro) y «ampliada» (Empresa).
Básico **no** la incluye.

Los números concretos viven en el catálogo del servidor y son propuesta (P-9): Negocio 300 ·
Pro 1.500 · Empresa 5.000 comprobantes al mes. **No se muestran** en la interfaz.

## D4. Cuenta bancaria única

**P:** Banco, titular legal, tipo de cuenta, número y moneda.
**Bloquea:** el paso 3 de la pantalla y las instrucciones de pago.
**Regla del informe:** no incorporar datos bancarios al código hasta validarlos fuera de él.

## D5. Método de consulta de abonos — BLOQUEANTE de activación automática

**P:** ¿Cuál de estas vías existe realmente para FULLTECH SRL?

| Vía | Qué permite | Estado |
| --- | --- | --- |
| Revisión manual en banca empresarial | Conciliar a mano | Disponible siempre |
| Importación de extracto CSV/Excel | Conciliación reproducible | Por confirmar formato |
| Archivo bancario automatizado | Conciliación periódica | Por confirmar con el banco |
| API bancaria / notificación de abono | **Activación automática real** | **No confirmada** |

**Bloquea:** F5. Sin fuente independiente del abono, la activación sigue siendo humana (MVP).

## D6. Política de gracia y crédito

**P:** ¿Quién puede conceder tiempo, cuánto máximo, con qué límites y con qué revocación?
**Bloquea:** `LicenseGracePeriod` y la UI que lo muestra distinto de «pagado».
**Regla del informe:** la gracia nunca marca la orden como `PAID`/`VERIFIED`.

## D7. Cierre de caja y ventas offline al vencer — BLOQUEANTE de F1

**P:** Si la licencia vence con **caja abierta** o con **ventas offline capturadas antes** del
vencimiento:
- ¿Se permite cerrar la caja?
- ¿Se sincronizan esas ventas o se bloquean?
- ¿Desde qué fecha se considera autorizada cada operación?

**Bloquea:** introducir el guard de vencimiento sin esta regla puede perder ventas reales.
**Recomendación del informe:** no descartar la cola offline por un 403; definir orden de eventos.

## D8. Permisos del administrador

**P:** ¿Quién puede: registrar comprobante, conciliar, conceder gracia, aprobar pago, activar,
pausar licencia? ¿Un aprobador financiero distinto del soporte?
**Bloquea:** F7 y el diseño de auditoría.

## D9. WhatsApp

**P:** ¿Qué proveedor está realmente contratado (Cloud API, Evolution, otro)? ¿Número de empresa y
de administración? ¿Hay consentimiento y opt-out?
**Bloquea:** F6. Verificado: en `apps/api/src` no hay módulo de WhatsApp.

## D10. Fiscalidad de la suscripción

**P:** ¿Cómo se factura la licencia (e-CF, ITBIS, tipo de comprobante)? ¿Software + soporte en un
solo ítem o separados?
**Bloquea:** emitir comprobantes desde la plataforma. Requiere criterio contable/DGII.

## D11. Qué pasa con el autoservicio actual — NUEVO, detectado en código

**P:** Hoy cualquier administrador de una empresa puede llamar a `POST /license/activate` y
`PATCH /license/limits` con su propio token y **concederse** usuarios, productos y fecha de
vencimiento. ¿Se retira esa capacidad?
**Opciones:** (a) retirar y dejar solo el puente administrativo; (b) mantener con lista blanca de
empresas internas; (c) mantener pero solo para pruebas.
**Bloquea:** F1. Si no se cierra, la pantalla de Planes convive con una puerta trasera.

---

## Resumen de bloqueos por fase

| Fase | Decisiones necesarias |
| --- | --- |
| F0 | Recrear rama desde `origin/production-main` · D3 (almacenes Pro/Empresa) · D3b (e-CF) |
| F1 | D7 (caja/offline), D11 (autoservicio) |
| F2 | Ninguna: el catálogo está publicado (D1/D2 cerradas) |
| F3 | D3, D3b, D4 |
| F5 | D5, D6 |
| F6 | D9 |
| F7 | D8, D10 |
