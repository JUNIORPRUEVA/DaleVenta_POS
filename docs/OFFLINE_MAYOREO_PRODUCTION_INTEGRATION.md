# Integracion Offline 48h + Mayoreo

## Alcance y autorizacion

El propietario solicita integrar todos los cambios offline de 48 horas, conservar
Mayoreo y las mejoras productivas recientes, actualizar production-main,
desplegar API/PWA y crear/publicar un nuevo instalador. Ejecucion continua con
gates internos; no incluye seeds, ventas de prueba ni reparaciones en produccion.
La decision anterior de conservar Windows 142 correspondia al release Mayoreo;
el nuevo pedido autoriza preparar y publicar un instalador combinado posterior.

## Base verificada

- Produccion/main: 2f33df45e732322df794bb58e245d741798e40e1.
- Snapshot offline: 8c19bbac5693376919057fe1aad9348a2493d934, padre 6b3e38ed.
- Fuente preservada: C:/src/fullpos-offline-safe-48h, feature/offline-safe-48h.
- Integracion: C:/src/fullpos-offline-prod, agent/offline-mayoreo-integration-20261018.
- Snapshot aislado sin tocar indice/archivos originales; excluye uploads UAT,
  archivos de entorno y tres imagenes ajenas a la funcionalidad.

## Plan y criterios de aceptacion

1. Revisar el delta y resolver los siete conflictos preservando ambas funciones.
2. Verificar autorizacion 48h por empresa/usuario/dispositivo, vencimiento,
   recuperacion durable, idempotencia, inventario/caja y precios de Mayoreo.
3. Ejecutar analisis, API build, suites completas y smokes en UAT aislada.
4. Revisar migraciones aditivas y ensayarlas; comprobar compatibilidad del cliente
   publicado y limites reales del actualizador. No atribuir pruebas historicas
   de otras builds al candidato combinado.
5. Generar artefactos API/PWA/Windows fuera del servidor, desde commit conocido;
   registrar version, hashes, configuracion, evidencia funcional y visual.
6. Revision final, respaldo, autorizaciones especificas aplicables y rollback.
   Integrar production-main, desplegar artefactos inmutables y verificar salud,
   versiones y descarga. Conservar Windows 142 y las imagenes anteriores.

## Estado actual

AUDIT/PLAN completados. Integracion y validacion pendientes. NO-GO para publicar
hasta ejecutar todos los gates aplicables. Los informes de la rama offline son
evidencia historica, no una certificacion del candidato combinado.
