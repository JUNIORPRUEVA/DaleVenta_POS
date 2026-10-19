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

Integracion completada en 1c2c7a61. Validacion en curso; no publicacion nueva.

## Revision y validacion observada

- Siete conflictos resueltos: ignores, UAT safety, rutas SQLite, POS, ventas,
  runner y script UAT. Conservados aislamiento Mayoreo, grants48h, intentos
  durables y recalculo al digitar cantidad. UAT build usa ruta fisica corta;
  rechaza salida productiva mezclada, sin borrar archivos ni usar subst.
- sqlite3 Dart3.1.7 incluia SQLite3.52.0 retirado oficialmente. Se fija3.3.2,
  SQLite3.53.1 estable, y su dependencia native_toolchain_c0.18.0. Referencias:
  https://www.sqlite.org/releaselog/3_52_0.html
  https://pub.dev/packages/sqlite3/changelog
- Omision detectada al combinar: replay de ventas no reenviaba priceListId,
  priceListManualOverride ni sourceQuotationId. Se conservan en el handler.
- npm ci PASS; npm run api:build PASS; Jest completo76 suites/766 PASS/8 skips.
  Audit npm:23 avisos,3 altos en cadena de desarrollo ts-node-dev/chokidar/braces;
  sin fix disponible. No se aplica actualizacion masiva ajena al alcance.
- flutter analyze --no-pub PASS. Primera suite completa1368 PASS/6 skips.
- Clon local exclusivo: fullpos_offline_mayoreo144_uat, localhost56549;
  API46554. Fuente UAT Mayoreo preservada, sin cambios de datos originales.
  Migraciones20261014113000 y20261014153000 aplicadas por Prisma:PASS.
  Primer intento uso credencial UAT obsoleta de otra copia y fue rechazado;
  se identifico el origen correcto sin cambiar credenciales ni registrar valores.
- Smoke HTTP/PG: grant48h;5 reintentos concurrentes de producto/stock/venta;
  una sola operacion; rechazo de contenido distinto; stock correcto;
  DTO online legacy compatible y venta sin turno rechazada sin reasignacion.
  Mayoreo15x70=1050, replay tras cambiar regla devuelve la misma venta/total.
- Flutter opt-in offline_mayoreo_http_acceptance_test:API local real, SQLite3.53.1,
  grant real, conexion interrumpida, venta local15x70, cierre/reapertura SQLite,
  envio de lista manual original, sincronizacion y reintento sin doble stock:PASS.
  Se corrigio un getter incorrecto del test antes de ejecutarlo correctamente.

## Limites del alcance

La contingencia48h admite operaciones autorizadas y conservadas por dispositivo;
ventas fiscales y pagos no efectivos necesitan conexion. Resolver nuevos precios
mayoristas requiere API; el carrito mayorista ya calculado puede conservar su
snapshot y sincronizarse. Un cambio posterior incompatible queda para revision,
no autoriza inventar precios ni reasignar pendientes a otro turno/empresa.
No se certifica hardware ni apagones fisicos mediante pruebas de proceso.

NO-GO para publicar hasta completar los gates restantes y registrar resultados.
