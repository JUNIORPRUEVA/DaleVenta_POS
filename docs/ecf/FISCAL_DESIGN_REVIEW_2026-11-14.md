# Revisión visual fiscal — inventario y galería local

Estado: revisión conjunta en curso. Sin despliegue ni operaciones externas.

Refinamiento posterior: seguimiento4–6 con ancho contenido y descripción neutra;
cierre15 con una única superficie y numeración integrada; bandeja16–18 con
controles6px, contraste seleccionado, filas finas y error de conexión compacto.
Capturas: `compact-fiscal-design-2026-11-14/`.
El propietario confirmó que «pantalla20» significaba19 Configuración fiscal.
Se optimizó con paneles en dos columnas en escritorio y una en móvil, botones
rectangulares de6px, interruptor compacto, metadatos completos de numeración y
ocultación de tipos sin contenido. Confirmaciones y permisos se conservan.
La prueba a1280×760 comprueba acceso visible a la acción E34 sin desplazar;
la lista mantiene desplazamiento para móviles, texto ampliado o más registros.

## Aclaración sobre las pruebas por empresa

El proceso oficial de emisor con proveedor certificado distingue solicitud,
pruebas de simulación y certificación. La aprobación inicial no equivale a
certificación final; las pruebas forman parte de esta última, no de un trámite
adicional después de quedar certificado. El cliente usa el asistente existente;
este rediseño no añade otro set manual en FullPOS. No se verificó externamente
en esta tarea la automatización del proveedor ni el tiempo que tarda.

Fuente consultada: [procedimiento DGII, apartados2.2.2,2.2.3,2.3 y2.5](https://dgii.gov.do/cicloContribuyente/facturacion/comprobantesFiscalesElectronicosE-CF/Documentacin%20sobre%20eCF/Documentaciones%20Proceso%20de%20Certificaci%C3%B3n%20FE/Proceso-Certificacion-EmisorElectronico-Proveedor-Servicios-FECertificado.pdf).

Preview: http://127.0.0.1:4804/ → «4–19. Otras pantallas».
Selector superior y flechas permiten revisar varias vistas consecutivamente.
Los números identifican **escenarios de revisión**, no pasos obligatorios nuevos.
Se montan widgets reales con repositorios de prueba y HTTP bloqueado.
Fechas, RNC, numeración y comprobantes son sintéticos; no son autorizaciones.

## Lote disponible

| Vistas | Contenido | Implementación real |
| --- | --- | --- |
| 1–3 | Empresa, bienvenida y preparación | AccountCompanySettingsScreen, EcfWelcomeStep, EcfPreparationStep |
| 4–7 | Seguimiento: solicitud, pruebas, certificación y conexión fallida | EcfDosaTrackingStep, EcfDosaActivationStatus |
| 8–9 | Firma pendiente y autorización registrada | EcfAuthorizationStep |
| 10 | Habilitar producción, incluido diálogo de confirmación | EcfProductionActivationAction |
| 11–13 | Numeración sin registrar, registrada y vencida | EcfSequenceRangeSection |
| 14–15 | Cierre listo y cierre sin numeración | EcfCompletedView |
| 16–18 | Bandeja con E31/E34, vacía y con error; detalle al pulsar una fila | EcfDocumentsPage |
| 19 | Configuración y entrada al diálogo Nota de crédito | EcfConfigPage, EcfCreditNoteAction |

La firma se simula en memoria. Guardar rangos, habilitar producción, despachar
o emitir no está implementado contra servicios reales: el adaptador bloquea
HTTP. «Ir a ventas» explica que es una demostración. No hay datos productivos.
El selector reinicia el estado local para comparar escenarios sin mezclarlos.

## Inventario pendiente de incluir/revisar en lotes posteriores

No se consideran revisadas todas las pantallas por haber agregado esta galería.

- Diálogos de detalle, nota de crédito y confirmación productiva: accesibles,
  pendientes de revisión visual específica conjunta y de sus estados adicionales.
- Recuperación administrativa: `ecf_certification_recovery_page.dart` y
  `ecf_resolve_attempt_dialog.dart`.
- Revisión del equipo de plataforma y sus expedientes:
  `ecf_platform_review_page.dart`.
- Vista administrativa de habilitación (`Routes.ecfAdmin`) y sus paneles de
  evidencia, requisitos, asistencia y certificado; el flujo alternativo de
  `ecf_tracking_step.dart` no es el seguimiento DOSA mostrado en este lote.
- Componentes auxiliares existentes: `ecf_certificate_card.dart`,
  `ecf_postulation_xml_card.dart`, `ecf_dgii_application_wizard.dart`,
  `ecf_support_grant_card.dart` y `ecf_line_classification_dialog.dart`.
- `ecf_fiscal_data_page.dart` y `ecf_activation_page.dart`: revisar sus callers
  antes de presentarlos como pantallas activas. Las rutas ecfFiscalData y ecfDgii
  redirigen a la habilitación actual; no son pasos adicionales del cliente.
- POS/selector, historial/devolución E34, ticket y PDF fiscal: revisión posterior
  fuera del asistente de certificación; conservar el funcionamiento existente.
- Portal externo de certificación: no se clona, abre ni modifica desde esta demo.

Fuentes: `core/routing/app_router.dart`, `features/ecf/ui/` y sus callers.
Este inventario distingue pantallas activas, variantes y componentes; no afirma
que cada archivo Dart sea una pantalla independiente.
