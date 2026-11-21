# Cierre de ingeniería y límites de publicación

## Revisión profunda posterior a aprobación visual — 21 de noviembre de 2026

Se revisó la versión `5545d07c` y se reprodujeron fallos adicionales del cliente
antes de corregirlos. No se cambian los botones aprobados ni las reglas
financieras, fiscales, de inventario, licencias o seguridad del backend.

| Fallo reproducido | Corrección y comprobación |
| --- | --- |
| Archivo con identidad distinta cerraba una eliminación pendiente | Se exige el ID solicitado y estado archivado antes de tocar caché o incidencia. |
| Cambio de empresa durante archivo cerraba la incidencia anterior | Contexto de usuario/empresa capturado, solicitudes y caché fijadas con OperationScope, comprobación al regresar y antes de resolver. También se comprueba cambio de usuario dentro de la misma empresa. |
| Un `ok` genérico bastaba para confirmar anulación | Se exige identidad del producto y operación, motivo original, fechas válidas, estado anulado/archivado y stock cero. |
| Restauración aceptaba otro producto o uno todavía archivado | Se comprueba identidad y estado activo antes de mostrar éxito. |
| Dos avisos antes del primer dibujo dejaban un aviso huérfano | Se retira y libera la entrada anterior incluso antes de que esté montada; cierre repetido y salida de pantalla probados. |

Las lecturas de elegibilidad comprueban ID, empresa, versión y estado. Archivados
rechaza filas extranjeras o malformadas. Una discrepancia no borra la operación
local ni se presenta como éxito. La caché de archivo queda fijada a su empresa.

Pruebas nuevas reproducidas antes de los arreglos: cuatro regresiones de
repositorio fallaron, y falló el reemplazo inmediato de avisos. Después de las
correcciones pasan 17 regresiones de repositorio y dos de avisos; la repetición
con las 85 vistas/pruebas de galería sumó 104 aprobadas.

Evidencia local de esta revisión:

- `deep-backend.log`: 121 pruebas y 11 suites aprobadas; `deep-build.log`: API compilada.
- `deep-flutter-verified.log`: 278 aprobadas y dos omisiones históricas condicionadas por entorno. Los dos casos nuevos de avisos pasan en `deep-final-regressions.log`.
- `deep-acceptance.log`, `deep-adversarial.log`, `deep-commerce.log` y `deep-final-http.log`: 25 escenarios HTTP/PostgreSQL aprobados. Los cuatro últimos comprueban ambos órdenes de carrera referencia/borrado, la misma identidad de anulación contra dos productos y las cinco rutas con empresa extranjera/sin autenticación.
- `deep-roles.log` y `deep-realtime.log`: permisos reales y entrega de eventos a dos clientes autorizados, sin entrega al extranjero.
- `deep-windows-verified.log` y `deep-android-launch.log`: widgets, repositorio, SQLite y HTTP reales, desconexión/reapertura, operación rechazada conservada y siguiente operación válida procesada una sola vez.
- `deep-native-data.log`: verificación independiente de datos persistidos de Windows y Android, movimiento original y compensación, un evento de anulación y archivo con stock conservado.
- `deep-backup.log`: backup restaurado en otra base sintética, datos idénticos y escrituras antiguas de reactivación/reposición rechazadas por PostgreSQL.
- `deep-auth-scope.log`: seis comprobaciones adicionales de autenticación y cambio de ámbito aprobadas. Son independientes de las 278 anteriores y de los dos casos nuevos de avisos.
- `deep-analyze-final.log`: análisis focalizado sin incidencias; `deep-web-build.log` y `deep-web-browser.log`: compilación Web y 78 capturas de las 39 vistas, sin llamadas a API.
- Cierre final tras corregir los supuestos del ensayo: `deep-windows-current.log` y `deep-android-current.log` aprobados con los ejecutores que exigen evidencia nueva. `deep-native-data-final.log` vuelve a contrastar ambos resultados con PostgreSQL: runId Windows `02954331-d145-4305-a941-401f551179c0`, Android `1f2adab9-f136-408a-bb6f-abe443708aca`. Ambos conservan el movimiento original, una compensación y un evento; la reconexión aplica una sola vez la operación válida y conserva el pendiente rechazado. La repetición verifica además el producto anulado que persistió desde la ejecución anterior.

Se mantienen los fallos intermedios en los logs. Una invocación de pruebas incluía
un directorio inexistente; se corrigió la selección. El ensayo inicial de Windows
usaba el puerto 4017 en la configuración global del perfil UAT, que solo admite
4004: se corrigieron los argumentos del ensayo, sin ampliar la lista permitida
ni detener el servicio ajeno de 4004. El repositorio del ensayo llama a la API
privada explícita de 4017; Android usa la redirección local 4004 → 4017.

La repetición nativa también corrigió supuestos del ensayo: se busca por nombre
en Archivados en lugar de asumir que una fila está visible, y se selecciona el
ListTile en vez del mismo texto dentro del buscador. Los ejecutores preservan
datos previos, rechazan salidas fallidas y exigen un runId nuevo en el resultado;
el verificador SQL registra ese runId y su fecha. Así una evidencia antigua no
puede utilizarse como si perteneciera a la ejecución actual.
El manifiesto de código también se corrigió para enumerar diferencias contra
HEAD: preparar archivos con git add no cambia el conjunto revisado. Se comparan
11 hashes de código/pruebas y se excluyen las capturas de fallos; verificación
aprobada antes y después de preparar el commit.

Las dos omisiones corresponden a `catalog_offline_uat_integrity_test.dart`:
validación de DTO histórico de cotización sobre copia desechable y ensayo de
reapertura/replay del entorno Phase 11. Exigen `FULLPOS_PHASE11_UAT=true` y sus
fixtures/credenciales propios. No se habilitó ese entorno ajeno; la reapertura y
reconexión de este alcance sí se ejecutaron con SQLite/HTTP reales en las dos
plataformas nativas. No se cuentan omisiones como pruebas aprobadas.

Límite conservado: una cola desconectada de otro equipo no es visible al
servidor. Si referencia un producto retirado al reconectar, el rechazo y su
evidencia deben conservarse para recuperación; no se debe repetir el cobro a
ciegas. Se verifica que ese rechazo individual no atasque operaciones válidas
independientes. Esta revisión no certifica cambios simultáneos de otras ramas.

El alcance local verificado mantiene **GO WITH ISSUES**: aprobación visual ya
concedida, iPhone físico no disponible y revisión global ajena de licencias
documentada más abajo. Integración y despliegue siguen separados; no hubo push,
despliegue, modificación productiva ni eliminación de incidencias para resolver
los fallos. Las pruebas reducen riesgos concretos; no certifican riesgo cero.

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
