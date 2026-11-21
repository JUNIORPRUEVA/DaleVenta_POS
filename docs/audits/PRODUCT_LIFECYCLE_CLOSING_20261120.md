# Cierre de ingeniería y límites de publicación

## Cambios comprobados

- Borrado físico protegido por existencias de cada almacén y referencias.
- Anulación con compensación, versión, identidad, actor, motivo y transacción.
- Archivo/restauración sin pérdida de ID, código, stock o Kardex; cupo del plan.
- Códigos reservados y conflicto explícito de creación contra archivados.
- Purga HTTP retirada y poda automática sin borrado de otras identidades.
- Huella persistente del borrado y bloqueo compartido con replay de creación:
  la carrera entre ambos no puede resucitar el producto.
- Cola local conservada cuando una eliminación se resuelve archivando. CAS
  evita sobrescribir evidencia concurrente y rechaza otro propietario.
- Una respuesta incierta oculta acciones hasta comprobar de nuevo; una recarga
  fallida no presenta datos anteriores como si fueran actuales.
- Un fallo de actualización visual después de guardar no se presenta como fallo
  de la mutación. Se avisa «Cambio guardado. Actualiza el catálogo».
- Devoluciones históricas de archivados conservadas, ventas nuevas rechazadas.
- Telemetría de alta de almacén posterior al commit para evitar auto bloqueo.
- Notificaciones por empresa con datos mínimos; reconexión y catálogo reconciliado.

## Pruebas y evidencia

Las salidas reproducibles están en `.uat/product-lifecycle`. Se ejecutaron:

- `final-backend.log`: 121 pruebas, 11 suites, aprobadas.
- `final-flutter.log`: 214 aprobadas y dos casos históricos condicionados por
  entorno omitidos. Incluye las 39 vistas y pruebas de error/resultado incierto.
- `closing-tests.log`: ocho regresiones de repositorio aprobadas, incluidas
  conservación de la incidencia, propietario y cambio concurrente.
- HTTP/PostgreSQL: nueve escenarios de aceptación, ocho adversariales, cuatro
  de comercio, permisos reales y dos clientes de socket con un tercero extranjero.
- `windows-native-closure.log` y `android-launch-closure.log`: ejecución final del
  widget y repositorio reales, API local, SQLite, desconexión simulada/reapertura,
  incidencia permanente conservada y siguiente operación válida sin duplicación.
- `native-data.json`: ambas plataformas con una compensación, un evento,
  un movimiento válido de reconexión y stock 3 conservado en el archivo que
  resuelve una eliminación pendiente. La incidencia permanece almacenada.
- `backup-restore.json`: backup restaurado en otra base sintética; producto,
  movimientos y eventos idénticos; escritores antiguos no reactivan ni reponen
  una identidad anulada. Ningún dato productivo fue utilizado.

Los fallos intermedios no se ocultan: hubo un mock incompleto, expectativas de
roles que no reflejaban el mapeo heredado, una credencial de prueba caducada,
confirmaciones con desbordamiento y una ruta relativa de salida de shaders.
Se corrigieron sin cambiar licencias, relajar autenticación ni eliminar datos.
En el cierre inicial, los dos goldens de escritorio cambiaron por el icono de
gestión. La revisión visual posterior del 21 de noviembre incorpora los iconos
entregados por el propietario, alturas alineadas, cuadros rectangulares y avisos
inferiores. Sus pruebas y evidencia actualizadas se detallan en
`PRODUCT_LIFECYCLE_PREVIEW_20261120.md`.

## Auditorías de alcance general

Los generadores de modelos y endpoints se ejecutaron y actualizaron sus reportes.
El analizador heurístico de consultas termina en modo aviso: marca cinco errores
en servicios de integración de licencias que no fueron editados aquí. Sus rutas
usan secreto administrativo y el replay comprueba empresa/hash; esto no equivale
a certificar todos los avisos globales. Se conservan los reportes, sin silenciarlos.

## Pendientes legítimos y autorización

El propietario aprobó visualmente las 39 vistas el 21 de noviembre de 2026.
La revisión visual está cerrada. iOS físico no se
ejecutó porque solo hay Windows; no se inventa esa evidencia. No hay despliegue,
migración, reinicio ni modificación de productos existentes en producción.
La anulación está apagada por defecto y los códigos anulados siguen reservados.
ADMIN mantiene el significado efectivo actual, incluido MANAGER heredado.

La preparación de publicación y reversión está en
`PRODUCT_LIFECYCLE_PRODUCTION_PLAN_20261120.md`. Un resultado técnico favorable
no autoriza publicar. Antes de publicar debe verificarse que la versión elegida
incorpore una sola revisión coherente y repetir el cierre sobre ese commit.

## Dictamen

**GO WITH ISSUES para el alcance desarrollado en Windows, Android emulado y Web.**
No quedan fallos reproducidos de este alcance sin corregir en las pruebas
ejecutadas. Permanecen iOS físico no disponible y la revisión
global de avisos de licencias fuera del alcance. No es una certificación de
riesgo cero ni una aprobación de producción.

Se compararon 66 hashes de código y pruebas al terminar la revisión, sin cambios.
Copias seleccionadas de evidencia en `product-lifecycle-evidence/`; los logs,
capturas completas y backup sintético permanecen en `.uat/product-lifecycle`.
