# Preparación y reversión — sin ejecución productiva

Este documento no autoriza publicación, migraciones ni modificaciones de productos
existentes. La aceptación usa loopback y PostgreSQL sintético independiente.

## Antes de una publicación expresamente autorizada

1. Fijar un commit único y revisar diferencias. Confirmar fuente/artefacto desplegado
   y repetir pruebas. No integrar cambios de otra sesión sin revisión.
2. Obtener backup verificable y ensayar restauración en otra base. Incluir documentos,
   movimientos y huellas; no utilizar podas para preparar datos.
3. Inspeccionar inconsistencias con consultas de lectura. No convertir automáticamente
   los casos históricos en borrados/anulaciones.
4. Revisar las cuatro migraciones nuevas como una unidad y en orden:
   `20261121010000_product_lifecycle`, `20261121011000_product_lifecycle_events`,
   `20261121012000_product_lifecycle_historical_returns`,
   `20261121013000_product_lifecycle_return_column_mapping`.
   Son aditivas. Las últimas dos conservan la corrección reproducida de devoluciones
   y los nombres físicos SQL. No habilitar tráfico durante una cadena incompleta.
5. API primero con `PRODUCT_LIFECYCLE_ANNULMENT_ENABLED=false`; comprobar archivo,
   restauración, límites, devolución histórica y empresas. Cliente después.
   Habilitar anulación requiere decisión expresa.
6. Vigilar rechazos por versión/integridad y pendientes. Nunca borrar incidencias
   para mejorar métricas.

## Reversión conservadora

- Deshabilitar `PRODUCT_LIFECYCLE_ANNULMENT_ENABLED` detiene nuevas anulaciones.
- Conservar columnas, eventos, compensaciones, checks y triggers. No ejecutar
  migraciones inversas destructivas ni reponer stock manualmente.
- Verificar un rollback de código en un clon. Los triggers siguen impidiendo
  reactivar identidades anuladas; clientes antiguos pueden mostrar error genérico.
- Una recuperación de infraestructura restaura la base coherente completa,
  nunca Product separado de sus documentos y movimientos.
- Revertir código no deshace una anulación confirmada. Una corrección comercial
  posterior necesita su propio proceso auditado.

## Límites de autorización y plataforma

Producción no fue modificada. No se promete riesgo cero por compilar o aprobar
pruebas. iPhone/iOS no puede ejecutarse en este equipo Windows y debe registrarse
como plataforma no validada físicamente, sin inventar evidencia.
