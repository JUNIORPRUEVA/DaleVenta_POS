# Estudio del informe original (07-nov-2026)

**Fuente**: [`fuentes/Informe_Integral_FullPOS_Planes_Pagos_Licencias_2026-11-07.pdf`](./fuentes)
(12 páginas, SHA256 `FEF469E4…6343`). Texto extraído en
[`fuentes/informe-original-texto-extraido.txt`](./fuentes/informe-original-texto-extraido.txt).

Este documento **no sustituye** al PDF: lo resume para poder trabajar y deja marcado qué parte es
decisión de negocio y qué parte es cambio técnico. Al final de cada bloque se cita la sección del
informe para poder volver al original.

---

## Conclusión ejecutiva §0

- El modelo comercial es viable con **un solo centro de administración**, **una sola cuenta bancaria**
  y **un expediente de pago compartido** entre FullPOS y WhatsApp.
- La **activación definitiva automática solo debe ocurrir tras acreditación bancaria verificable**.
- La IA puede leer y clasificar comprobantes, pero **no certificar que se recibió dinero**.
- Decisión de experiencia del propietario: **no cambiar registro ni login mientras la licencia esté
  vigente**. Tras un vencimiento ordinario: **mantener la sesión** y conducir al cliente únicamente a
  **Planes y Soporte**; no permitir ventas ni modificaciones operativas.
- **Bloqueo administrativo ≠ vencimiento**: deben estar diferenciados.

## 1. Viabilidad por pregunta §1

| Pregunta | Conclusión del informe |
| --- | --- |
| ¿Una sola página de Planes y pagos? | Sí. FullPOS es interfaz y pasarela; la administración comercial central sigue en `FULLTECHPOS_BAKEND_LICENCIA`. |
| ¿Recibir vouchers desde POS y WhatsApp? | Sí, si ambos canales escriben sobre **la misma orden**, con identificación segura de empresa y control de duplicados. |
| ¿La IA valida el contenido del voucher? | Extrae datos, revisa coherencia y detecta riesgo. **No prueba acreditación.** |
| ¿Activación automática con transferencia? | Sí, **cuando exista fuente independiente y fiable del abono** y concilie inequívocamente con la orden. |
| ¿Activación solo con una imagen «que parece real»? | Técnicamente posible, **no es prueba de pago**. No recomendado como activación definitiva. |
| ¿El administrador puede conceder tiempo de pago? | Sí, como **autorización provisional explícita** con fecha límite, alcance y auditoría. **No** es pago verificado. |
| ¿El usuario vencido podrá entrar? | Es viable, pero **el código auditado hoy bloquea login y JWT**. Hay que cambiar la autorización **sin alterar el flujo normal vigente**. |

### Tres esquemas de activación §1

| Esquema | Ventaja | Dictamen |
| --- | --- | --- |
| Voucher aceptado por IA → activar | Rápido, sin operador | **No recomendable**: fraude, duplicados, transferencias no acreditadas |
| Voucher + aprobación humana | Operable desde el día uno | **Adecuado para el MVP** mientras no haya conciliación fiable |
| Voucher + abono bancario acreditado y conciliado | Automatización real y trazable | **Objetivo recomendado**; exige acceso autorizado a movimientos |

> Estrategia del informe: **automatizar ya** recepción, extracción, clasificación y comunicación;
> automatizar la **licencia definitiva** solo después de conciliar el abono. Si se quiere dar acceso
> anticipado, registrarlo como **crédito o gracia provisional** asumida por el negocio.

## 2. Sistemas y responsabilidades §2

| Sistema | Responsabilidad |
| --- | --- |
| `FULLTECHPOS_BAKEND_LICENCIA` | Administración comercial independiente (Node/Express/PostgreSQL): licencias, clientes, catálogos históricos, órdenes de pago, PayPal, puente a FullPOS. **Autoridad comercial a preservar.** |
| FullPOS Cloud API | NestJS/PostgreSQL. `Company`, `LicenseStatus` TRIAL/ACTIVE/BLOCKED/EXPIRED, trial de 7 días, cuotas de usuarios/productos, endpoints de administración. **Autoridad de enforcement.** |
| FullPOS Flutter | Windows, Android, iPhone, Web. Consume `GET /license`. La pantalla «Licencias» debe evolucionar a **«Planes»** sin motor comercial paralelo. |
| Sitio Astro | Expone planes y registro; **su catálogo diverge hoy** de las migraciones del administrador. |
| APPYRA_AI | Proyecto de IA distinto. Puede extraer/clasificar si se decide, pero **no** debe duplicar suscripciones ni licencias. |
| WhatsApp | Canal de captura, **no** segunda base comercial: identifica empresa y asocia cada envío a una orden existente. |

El repositorio legado «WED Y LICENCIA_FULLTECH» apareció como independiente: **no asumir que es el
desplegado** ni integrarlo sin identificar los servicios vigentes.

## 3. Catálogo comercial: contradicciones §3

| Plan | Migración 052 (histórico) | Astro (publicado) | Pendiente |
| --- | --- | --- | --- |
| Básico | RD$1,000/mes | RD$1,000/mes | Condiciones y límites vigentes |
| Negocio | RD$1,500/mes | **RD$2,000/mes** | Precio contractual |
| Pro | RD$2,500/mes | **RD$3,000/mes** | Precio contractual |
| Empresa | **No existe** en el CHECK de esa tabla | RD$4,500/mes | Crear o retirar tras decisión |

- La migración incluye un **mínimo histórico de tres meses**; la oferta reciente del sitio pretende
  **contratación mensual**. Es decisión comercial, no un defecto a corregir solo.
- En FullPOS el enum técnico es `STANDARD`/`ENTERPRISE` y se propagan `maxUsers`/`maxProducts`.
  **Almacenes y e-CF no tienen los límites anunciados implementados**, según la auditoría.
- **Nadie verificó** los valores actuales de la base productiva. Los seeds históricos **no** son
  automáticamente el contrato vigente.

## 4. Auditoría de bases de datos §4

53 migraciones y ~78 tablas en el proyecto administrativo. La base local de licencias **no pudo
auditarse** (el `.env` apunta a producción y no había copia aislada).

| Hallazgo | Implicación |
| --- | --- |
| Catálogos coexistentes: `product_plans`, `saas_planes`, `daleventas_commercial_plans`, `Company.plan` | Riesgo de doble verdad; definir autoridad por dominio |
| `company_subscriptions`, `subscription_payments`, `license_payment_orders`, `paypal_orders` ya existen | **Reutilizar** tras mapear dependencias, no crear tablas nuevas a ciegas |
| `demo_trials` con esquemas potencialmente divergentes | Comparar esquemas en UAT nuevo y migrado |
| Dos migraciones con prefijo `044` | Comprobar orden efectivo e idempotencia |
| `admin_sessions` se crea al iniciar, fuera de migraciones | Control de esquema y despliegue a revisar |
| Se replican datos de negocio POS en la BD administrativa | Minimización de datos y permisos de lectura |
| Órdenes con divisas no alineadas (DOP y default USD) | Error de monto/cobro |

## 5. Hallazgo crítico: vencimiento y autenticación §5

`assertCompanyCanUseApp` se comprueba en **login, refresh, handoff y validación JWT**. Una licencia
`EXPIRED` puede **bloquear la autenticación**. **No existe** el flujo deseado «vence, permanece
dentro y paga».

### Requisito definitivo del propietario §5

1. **Licencia vigente**: no modificar registro, login, navegación ni uso normal del POS salvo lo
   indispensable por compatibilidad/seguridad.
2. **Vencimiento ordinario**: no expulsar, no invalidar credenciales, no borrar información. Mantener
   o recuperar la sesión; experiencia restringida a **Planes + Soporte**, con consulta de estado,
   subida de voucher y confirmación.
3. **No permitir** al vencer: ventas nuevas, compras, movimientos de inventario, cambios de caja,
   usuarios, configuraciones, ni acceso por API fuera de la lista blanca. Exportaciones/datos aparte,
   según política y marco legal.
4. **Bloqueo administrativo** distinguible de expiración y de «pago pendiente»: el cliente conserva
   vías mínimas y seguras para conocer estado, regularizar y contactar soporte (salvo fraude).

### Corrección al diseño anterior §5

Un `READ_ONLY = permitir todos los GET del negocio` **es más amplio** que la experiencia definida.
Al vencer: **Planes + Soporte + endpoints mínimos** de identidad/sesión/estado. El resto, expreso.

### Riesgos técnicos a resolver §5

- Separar **identidad autenticada** de **licencia autorizada**, con guard **fail-closed** en servidor,
  y probar los endpoints de los 54 controladores (incluidos GET con efectos secundarios y rutas
  públicas).
- Flutter **no** debe interpretar `LICENSE_EXPIRED` como fallo de contraseña ni cerrar sesión por un
  403. La rehabilitación ocurre al **refrescar el estado de licencia**.
- Revisar caja ya abierta, operaciones offline válidas capturadas antes del vencimiento y
  sincronizaciones posteriores. **Nunca descartar la cola offline por un 403.**

## 6. Pantalla «Planes» §6

Una sola pantalla, compacta y adaptable: cabecera con empresa y estado; plan actual y fecha; recursos
usados; comparador; detalle de cuota; selección; pago; subida; seguimiento; renovación; soporte.
Todo en un destino con **pasos internos**, sin ventanas inconexas.

| Paso | Exigencia |
| --- | --- |
| 1. Elegir | Planes disponibles, límites **efectivamente aplicados**, precio vigente, impuestos/total, periodo, sin duplicidades |
| 2. Orden | Orden única e **inmutable**: `companyId`, plan/versión, moneda **DOP**, total, vencimiento de orden, referencia |
| 3. Transferencia | **Una** cuenta oficial (banco, titular, tipo, número) desde configuración segura; instrucciones para pagar desde otro banco; conservar comprobante |
| 4. Voucher | JPG/PNG/PDF desde Windows/Web/Android/iOS; validación de formato y tamaño; progreso y confirmación de recepción |
| 5. Evaluación | La IA extrae monto, fecha, referencia, banco emisor/receptor con **incertidumbre explícita** |
| 6. Resolución | Acreditado → activación definitiva; sin confirmación → pendiente/revisión; anomalía → aclaración/soporte |
| 7. Seguimiento | Estado de pago y licencia claro; avisos al cliente, WhatsApp y registro administrativo **compartidos** |

> Texto recomendado: «Sube tu comprobante para que revisemos tu transferencia. Si podemos confirmar
> el ingreso, activaremos tu plan automáticamente. En caso contrario, te avisaremos para completar la
> verificación».
> **No** prometer «activación instantánea garantizada» si se depende de ACH o revisión manual.

## 7. Voucher, IA y prueba de pago §7

| Señal | Uso correcto | **No** concluye |
| --- | --- | --- |
| Monto y moneda | Comparar orden vs importe visible | Que el abono llegó |
| Cuenta destino | Detectar cuenta/banco incorrecto | Que el titular recibió fondos |
| Fecha y hora | Ventana temporal y demoras | Que la transferencia terminó |
| Referencia | Ayuda a conciliar si el banco la transmite | Que la referencia sea única en el banco |
| Hash de archivo | Detecta reenvío exacto de imagen | Que dos capturas distintas no sean el mismo pago |
| Score de IA | Priorizar revisión manual | Autenticidad inequívoca |
| Movimiento acreditado | Prueba independiente de ingreso | Ausencia absoluta de disputas futuras |

**Gracia comercial**: solo decisión del administrador (fecha límite, motivo, actor, alcance, política
de revocación, notificación, auditoría). **Nunca** marcar la orden `PAID`/`VERIFIED` por esa concesión,
ni habilitar automáticamente por imagen de voucher.

## 8. Una cuenta bancaria y conciliación en RD §8

Una sola cuenta receptora es viable; los clientes podrán pagar desde bancos distintos. **No
incorporar datos bancarios al código hasta validarlos fuera de él.**

**ACH no es necesariamente inmediato.** ProUsuario distingue ACH y pagos al instante LBTR; el Banco
Central describe la liquidación LBTR aceptada como irrevocable en el sistema, **lo que no vuelve
auténtica una captura**. Horarios y reglas dependen de cada entidad.

| Alternativa de conciliación | Ventaja | Limitación |
| --- | --- | --- |
| Admin revisa banca empresarial | Sin API; trazabilidad humana | Tiempo operativo y error humano |
| Importación manual de extracto (CSV/Excel) | Reduce tecleo; conciliación reproducible | Validar formato/origen; evitar archivos alterados |
| Archivo bancario empresarial automatizado | Conciliación periódica | Disponibilidad y contrato con el banco |
| API bancaria autorizada / notificación de abono | **Objetivo de activación automática** | **No confirmada** para la cuenta del usuario |
| Tarjeta / pasarela | Confirmación programática, mejor UX | Comisiones, contracargos, contrato; **no disponible ahora** |

## 9. Arquitectura del pago compartido §9

El administrador conserva orden, recibos, pago, periodo, gratificaciones de crédito y decisión
comercial; **FullPOS es intermediario autenticado** y aplica el estado técnico; WhatsApp es **otra
interfaz del mismo expediente**.

```
Cliente POS/WhatsApp → companyId verificado → misma PaymentOrder → voucher + metadatos
   → IA (solo prevalidación) → conciliación o revisión autorizada → estado VERIFIED
   → aprobación/aplicación idempotente → puente administrativo existente
   → FullPOS LicenseService → refresco de UI
```

### Estados separados (nunca un solo campo) §9

| Objeto | Estados de ejemplo |
| --- | --- |
| Orden de cobro | `CREATED`, `AWAITING_TRANSFER`, `EVIDENCE_RECEIVED`, `REVIEW`, `SETTLED`, `CANCELLED`, `EXPIRED` |
| Comprobante | `RECEIVED`, `EXTRACTED`, `LOW_CONFIDENCE`, `DUPLICATE`, `FLAGGED`, `REVIEWED` |
| Dinero | `UNCONFIRMED`, `CREDITED`, `MATCHED`, `PARTIAL`, `OVERPAID`, `RETURNED`, `DISPUTED` |
| Suscripción | `TRIAL`, `ACTIVE`, `PAST_DUE`, `GRACE`, `CANCELLED`, `PAUSED` |
| Licencia técnica | `TRIAL`, `ACTIVE`, `EXPIRED`, `BLOCKED` (reutilizar enums existentes) |
| Integración | `PENDING_SYNC`, `APPLIED`, `RETRYING`, `FAILED_REQUIRES_ATTENTION` |

> El informe avisa: **no crear todos esos enums/tablas** sin examinar antes migraciones,
> dependencias y el módulo comercial ya implementado.

### Reglas de consistencia §9

- **Idempotencia** por orden, evento y aprobación: una acreditación no puede pagar dos órdenes ni
  extender dos veces una licencia.
- **Versionado y registro de destino**: «pago acreditado, activación pendiente» si el puente falla;
  reintentar y reconciliar **sin duplicar meses**.
- **No confiar en el `companyId` del cliente**: derivarlo de la sesión. En WhatsApp, vincular teléfono
  a empresa **solo tras prueba de control/autorización**.
- Acceso mínimo para administradores, comprobantes privados, datos bancarios cifrados, validación
  anti-malware y logs auditables sin secretos.

## 10. WhatsApp unificado y administrador §10

- Misma orden, importe, referencia, comprobante y estado en ambas interfaces. El cliente puede empezar
  en Flutter y continuar en WhatsApp **sin generar una segunda solicitud**.
- El administrador recibe aviso con referencia, importe, estado y **acceso seguro** al voucher; evitar
  datos financieros completos sin necesidad.
- Puede: ver voucher/extracción/historial/empresa/licencias/advertencias; marcar «pendiente de
  confirmación»; pedir información; registrar verificación bancaria; rechazar con motivo; registrar
  promesa de pago y **conceder acceso temporal separado del estado de pago**; pausar/reactivar por
  impago (reversible, con vía de regularización); conciliar y reactivar **aunque la licencia esté
  bloqueada para operar**.
- Políticas Meta: plantillas aprobadas fuera de la ventana de 24 h, vía clara para escalar a persona,
  consentimiento, opt-out, tarifas y proveedor real (Cloud API/Evolution) **antes** de automatizar.
  No sustituir la conciliación por una opinión de la IA.

## 11. Casos límite §11

| Escenario | Resultado requerido |
| --- | --- |
| Voucher subido antes del abono | Recibido/pendiente; **no** activación definitiva |
| ACH en fin de semana / fuera de ventana | Estado y tiempos variables; seguimiento sin repetir pago |
| Voucher válido sin movimiento bancario | Revisión/espera; no afirmar «pagado» |
| Documento editado o ilegible | Pedir mejor evidencia y revisión humana; **sin acusaciones automáticas** |
| Archivo duplicado / referencia ya usada | Vincular al expediente existente; no cobrar ni activar dos veces |
| Dos capturas del mismo pago | Conciliar por **movimiento bancario único**, no por hash |
| Abono sin referencia o pago de tercero | Matching asistido por monto/fecha/contexto + revisión |
| Monto inferior / superior | Pago parcial o excedente con política explícita; no marcar pagado ni extender sin autorización |
| Dos transferencias a la misma orden | Sumatoria controlada y trazabilidad individual si la política lo permite |
| Una transferencia reclamada por dos empresas | Bloqueo de doble asignación; resolver identidad del pagador |
| Pago después de vencer la orden | Reasignación autorizada; conservar evidencia |
| Upgrade a mitad de ciclo | Prorrateo o nuevo periodo según reglas **por aprobar** |
| Downgrade con consumo mayor que el límite | No borrar datos; bloquear altas sujetas a cuota y fijar fecha efectiva |
| Licencia vence con caja abierta | Regla de cierre/conciliación definida **antes** del guard |
| Ventas offline capturadas antes de vencer | No descartar; definir fecha de autorización y orden de eventos |
| WhatsApp y POS envían el mismo voucher | Una orden, varias evidencias/canales, deduplicación de mensajes |
| Banco/IA/WhatsApp caídos | Operación degradada: pendiente, reintento, revisión, soporte |
| Admin concede plazo | Gracia registrada con fecha límite, **sin simular pago** |
| Falsificación detectada tras la gracia | Auditar, notificar, pausar según política; no borrar datos |
| Abono confirmado y puente falla | «Acreditado / pendiente activación», outbox o reintento idempotente |
| Cliente con varias empresas | Seleccionar empresa verificada; una suscripción/orden por `companyId` |
| Cambio de número de WhatsApp | Reverificar, revocar vínculo antiguo, conservar expediente |

## 12. Seguridad, privacidad y obligaciones en RD §12

- Autenticación admin basada en `x-session-id` y permisos granulares **sin aplicar**, según el
  reporte → **no** abrir interfaz pública de pagos sin cerrar rutas y permisos.
- Puente HTTP con `x-license-admin-secret` **estático** → autenticación de servicio, integridad del
  cuerpo, timestamp/nonce, idempotencia y logging seguro, de forma **compatible y gradual**.
- Restringir uploads (tipo real/MIME, firma mágica, tamaño, virus, PDFs peligrosos), normalizar
  imagen, almacenar **fuera del webroot** y aplicar retención.
- **Separar permisos**: registrar comprobante, conciliar, conceder gracia, aprobar pago, activar,
  pausar licencia — con actor, motivo y fecha.
- **Ley 172-13** de protección de datos: los vouchers contienen nombres, cuentas y referencias.
  Documentar finalidad, acceso, conservación, encargados y eliminación; validar con asesoría local.
- **DGII / e-CF**: no asumir tratamiento idéntico para paquetes mixtos de software, soporte y
  servicios. Obtener criterio contable/fiscal **antes** de fijar impuestos y emisión.

## 13. Matriz de decisiones de negocio §13

Recogida como formulario accionable en [`03-decisiones-pendientes.md`](./03-decisiones-pendientes.md).

## 14. Qué falta verificar antes de editar §14

1. Identificar **inequívocamente** el servicio administrativo desplegado y su versión.
2. Crear por procedimiento separado un **UAT de licencias** sin credenciales ni datos productivos.
3. Inventario de tablas y dependencias efectivas; **no borrar nada**.
4. Verificar el catálogo vigente con acceso autorizado; los seeds **no** son precios contractuales.
5. Confirmar la cuenta bancaria única e investigar con la entidad si ofrece abonos por API, archivo de
   movimientos, notificación firmada o extracto automatizado.
6. Auditar los **54 controladores** para que la restricción al vencer sea realmente «Planes/Soporte»,
   sin bypass por GET mutantes o rutas públicas.
7. Ensayar en UAT: alta, vencimiento, solicitud, comprobante, conciliación manual, activación, gracia,
   bloqueo, reactivación y offline.
8. Comprobar proveedor de WhatsApp y su capacidad real de recibir archivos y enviar plantillas.
9. Validar política de acceso/exportación, retención de voucher y condiciones de suspensión con
   revisión legal.

## 15. Veredicto §15

- Preservar los **tres** componentes existentes: motor de licencia FullPOS, administración comercial
  `FULLTECHPOS_BAKEND_LICENCIA` y alta/trial del cliente.
- Automatización **por fases**: carga, revisión IA, órdenes y notificaciones desde el primer
  lanzamiento; **activación automática definitiva solo tras conciliación bancaria corroborada**.
- El administrador puede conceder tiempo de uso por excepción **sin falsificar el estado de pago**.
- El PDF es **diagnóstico y especificación de criterios**, no autorización de ediciones.

## 16. Fuentes externas citadas §16

`[E1]` ProUsuario ACH/LBTR · `[E2]` Banco Central LBTR · `[E3]` BC pagos instantáneos ·
`[E4]` Grupo Popular API Portal · `[E5]` WhatsApp Business policy · `[E6]` Ley 172-13 ·
`[E7]` DGII e-CF · `[E8]` DGII consulta ITBIS software · `[E9]` SIPARD 2025.

> Aviso del informe: horarios, disponibilidad de pagos, condiciones de API bancaria y régimen fiscal
> cambian. **Ninguna fuente prueba** una integración bancaria concreta ni que el banco haya otorgado
> credenciales a FULLTECH SRL.
