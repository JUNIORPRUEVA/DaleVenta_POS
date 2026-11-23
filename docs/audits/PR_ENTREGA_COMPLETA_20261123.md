## Resultado

Consolida el trabajo pendiente de FullPOS en una sola rama: contrato de soporte
interno, controles administrativos desde CRM, acceso local seguro nativo y
corrección del RNC antes de postular, junto con textos fiscales para el cliente.
Conserva como ancestros las entregas anteriores de planes, IA, productos,
recuperación, diseño móvil y preparación/publicación iOS ya unidas en PR53–55.

CRM se revisa separadamente: https://github.com/JUNIORPRUEVA/appyra-crm/pull/1.
No se incluye el código del CRM dentro del repositorio FullPOS.

## Comportamiento

- Contacto general separado del correo fiscal y del correo de acceso.
- Asignar plan conserva vencimiento/clave/estado; añadir días es una acción
  administrativa independiente. Sin pagos ficticios ni activación fiscal implícita.
- Comandos ADMIN con motivo, versión, auditoría transaccional, control de uso e
  idempotencia. Cambio de correo del propietario revoca sesiones y tickets;
  identidades compartidas entre empresas requieren revisión separada.
- Antes de abrir el asistente, el cliente puede volver a revisar/corregir sus
  datos fiscales. No se permite cambiar incidentalmente un expediente registrado.
- Los mensajes fiscales para clientes omiten el proveedor, conservando códigos
  históricos. Sólo anuncian aceptación DGII con evidencia correlacionada compatible.
- Se recupera completo el acceso local seguro de `db93ce18`, sin presentarlo como
  listo para publicación general. PWA continúa fuera del acceso local nativo.

## Validación

- Backend compilado; 24 pruebas PostgreSQL y 6 HTTP e2e PASS.
- Regresión de licencias: 162 PASS/53 omisiones condicionales.
- Análisis Flutter conjunto: sin incidencias.
- Regresión conjunta de auth/offline/routing/e-CF y build web QA: resultados
  finales pendientes de registrar en este borrador; no se cuentan como aprobados.
- CRM: backend 2598 PASS/3 omitidas, Flutter 380 PASS/5 omitidas; aceptación
  nativa Windows y Android local. Puente: 117 PASS. No son pruebas productivas.

## Bloqueos: NO-GO para merge/deploy general

1. La migración `20261123010000_company_contact_email` debe aplicarse con
   autorización y respaldo ANTES del backend nuevo. No se ejecutó en producción.
2. El informe original offline documenta fallo de persistencia tras reinicio e
   instalación del ejecutor Android; causa pendiente. Keychain/iPhone nativo
   tampoco comprobado. Su recuperación aquí evita perder trabajo, no resuelve
   esos pendientes ni autoriza lanzar la funcionalidad a todos los clientes.
3. Revisar controles remotos y completar validaciones de este candidato.
4. El puente conserva copia/historia saneada con push bloqueado. Distribución de
   imagen privada, scopes, soporte firmado y almacenamiento real son pasos separados.

No hay merge automático, deploy, reinicio, cambios de variables productivas,
datos reales, numeraciones ni credenciales. El PR debe mantenerse como borrador.

Inventario y procedencia: `docs/audits/ENTREGA_COMPLETA_FULLPOS_PR_20261123.md`.
Preparación backend: `docs/audits/CRM_CONTROL_PUBLICACION_20261123.md`.
