# Verificación previa: administración y continuidad de ventas

Fecha: 2026-11-20. Worktree: `C:/src/fullpos-recovery-ui-20261120`.
Esta revisión comenzó antes de cambiar el flujo. A continuación se incorporó
la indicación expresa del propietario de simplificar las soluciones y reservar
el Centro al administrador. No se modificaron producción ni reglas financieras.

## Ajuste implementado tras la indicación del propietario

- Se retiró «Solicitar revisión» de las acciones visibles. «Comprobar» guarda
  el expediente interno idempotente y consulta el registro original en una sola
  acción; nunca reenvía ventas ni movimientos de caja.
- En caja se puede comprobar o «Marcar como no realizada» desde el detalle.
  La decisión requiere motivo y las comprobaciones del backend. Si existe un
  registro relacionado, el backend impide descartarlo como no realizado.
- Los cobros inciertos muestran directamente «Verificar ahora», «Hacer una
  venta nueva» y «Marcar como no realizada». Las herramientas de diagnóstico y
  la declaración de dinero recibido permanecen bajo «Más opciones».
- La pantalla exige sesión con rol ADMIN antes de cargar sus datos. Al cajero
  se le muestra «Acceso de administrador». Se eligió esta modalidad autorizada
  por el propietario; no se añadió un PIN paralelo ni se cambiaron claves.
- Lectura, detalle y comprobación de expedientes también exigen ADMIN en
  controlador y servicio backend. La creación de evidencia por el propietario
  autenticado conserva su contrato, útil para los clientes existentes.
- La fila local se agrupa con el expediente que representa cuando este está
  disponible. La evidencia local permanece; ante fallo de consulta vuelve a
  estar visible. Una revisión abierta no muestra el estado vacío de éxito.

### Pruebas del ajuste

- Flutter: **55 PASS** en recuperación, repositorio, errores y menú de
  sincronización; `.uat/recovery-admin-verified-tests.log`.
- Tras mostrar las soluciones como botones directos: **30 PASS** en toda
  `test/features/offline` y `recovery_review_repository_test.dart`;
  `.uat/recovery-admin-buttons-final.log`. Incluye acceso denegado al cajero,
  idempotencia del expediente, ausencia de POST financiero y conservación de
  payload/fecha. Estos conjuntos se solapan; no se suman como pruebas únicas.
- Continuidad y persistencia: **44 PASS**;
  `.uat/recovery-continuity-review.log`.
- Windows: `flutter run -d windows` compiló la última interfaz y dejó la app UAT
  ejecutándose con el perfil aislado; `.uat/recovery-admin-windows.log`.
  El verificador SQLite/PostgreSQL volvió a dar PASS: 2 ventas, 3 movimientos,
  46 incidencias y un expediente pendiente, sin cambios financieros. Esta
  apertura no se presenta como una nueva aceptación completa de la API.
- Servicio backend: **19 PASS**, incluida denegación de lectura/detalle/verify
  al cajero; `.uat/recovery-admin-backend-tests.log`.
- Análisis Flutter sin incidencias:
  `.uat/recovery-admin-analyze-confirmed.log`.
- Typecheck del backend con `tsconfig.build.json --noEmit`: PASS.
  `.uat/recovery-admin-typecheck-confirmed.log`. Un intento anterior con el
  tsconfig general incluyó tests sin sus tipos Jest y falló; se corrigió el
  comando para usar la configuración real de compilación, sin alterar tests
  ajenos ni instalar dependencias.
- Galería Flutter servida en `http://127.0.0.1:4487`, renderizada en Chrome con
  los botones directos. No conecta a la API. La automatización de navegador
  quedó en carga y se detuvo su propio proceso; no se registra como PASS ni
  como diez recorridos funcionales ejecutados. El selector ofrece los diez
  escenarios para revisión visual del propietario.

### Pendientes que este ajuste no resuelve

La protección de treinta minutos para carritos iguales y la entrega automática
de incidencias locales de otros usuarios al administrador necesitan una fase
funcional específica. No se cambió la identidad de los tickets ni se reasignó
la propiedad de las operaciones al administrador. Los expedientes ya publicados
de su empresa sí se pueden consultar. No debe afirmarse que todas las ventas
idénticas son continuas ni que el administrador ve automáticamente datos de
otros dispositivos desconectados.

La nueva restricción backend pasó pruebas de servicio y compilación; aún falta
repetir su aceptación HTTP con la API local ejecutando esta última versión.
No se ha desplegado. **GO para revisión visual local; NO-GO de publicación o de
la afirmación «ninguna venta nueva puede bloquearse».**

## Qué significa cada acción actual

| Acción | Efecto real |
| --- | --- |
| Solicitar revisión | Publica un expediente administrativo interno de una operación local rechazada. Conserva el original. No contacta al desarrollador, no reenvía el movimiento y no confirma dinero. |
| Comprobar registro | Busca el registro financiero original por empresa, identidad, propietario, turno e importe. Solo confirma si coincide. Si no se encuentra o discrepa, conserva el caso. |
| Continuar revisión | Registra una nota del administrador y deja el caso pendiente. |
| No se realizó | Decisión administrativa auditada, exige motivo y ausencia de registro relacionado. No anula ventas ni pagos existentes. |
| Sí recibimos el dinero | Declaración humana que genera una obligación de conciliación. No equivale a una venta o pago confirmado por el servidor. |
| Reporte para soporte | Muestra/copía un texto de diagnóstico; no lo envía automáticamente. |

El expediente es útil para preservar evidencia y para que un administrador
vea casos de otros usuarios de su empresa. Exigir al administrador
«solicitarse una revisión» es una fricción de la interfaz, no una necesidad
financiera. Mostrar la fila local y el expediente enlazado sin agruparlos
también crea una duplicación visual; no demuestra duplicación de dinero.

## Hallazgos anteriores al ajuste (historial)

1. **El Centro todavía no es exclusivo del administrador.** El acceso desde
   `core/offline/sync_status_menu_button.dart` y la pantalla no exigen ADMIN.
   `recovery-review.controller.ts` exige ADMIN en `decision`, pero no en
   `list`, `detail`, `submit` y `verify`. `ownerWhere` limita los otros roles
   a sus propios casos; ADMIN ve los de su empresa. No hay acceso cruzado
   entre empresas en este flujo revisado, pero no cumple «solo el admin ve».
   La autorización manual del cliente también admite permisos delegados o PIN
   administrativo según `admin_authorization.dart`; no equivale a iniciar
   sesión como ADMIN.
2. **La lista local está filtrada por usuario original.** Iniciar sesión como
   administrador no le da automáticamente todas las filas locales de los
   cajeros. Los expedientes ya publicados sí son consultables por el ADMIN de
   la misma empresa. Ocultar la pantalla al cajero sin establecer una entrega
   automática durable dejaría algunos casos fuera de la vista del encargado.
3. **Una incidencia no detiene toda la cola.** `processPending` excluye
   bloqueadas antes del límite y conserva dependencias. Un cierre espera sus
   operaciones anteriores; operaciones independientes siguen procesándose.
4. **Hay una interrupción posible para dos ventas iguales.**
   `OfflineStore.sameCartBlockWindow` vale **30 minutos**. La reserva bloquea
   otro `clientRequestId` si hay un intento incierto reciente con la misma
   huella: empresa, turno, medio de pago, cliente, lista, total y artículos.
   Esa huella no distingue de forma fiable un reintento de dos clientes que
   compran exactamente lo mismo. El administrador puede autorizar una venta
   nueva con un permiso local de un uso; exige intervención y contradice el
   objetivo de no interrumpir ventas legítimas iguales.
5. **Ventas distintas sí continúan.** Prueba adicional con SQLite temporal y
   repositorio real: primer POST con timeout, segundo carrito diferente con
   otro identificador recibe confirmación, dos POST totales y el intento
   original conserva exactamente payload y fecha.
6. **La continuidad tiene condiciones reales.** La venta Normal offline en
   aplicación instalada necesita almacenamiento durable y autorización local
   válida. Los comprobantes electrónicos requieren conexión. Identidad
   inválida, almacenamiento no durable o turno inválido no se pueden convertir
   en ventas confirmadas por ocultar un aviso. No se cambian reglas fiscales,
   licencias, inventario ni seguridad para evitar mensajes.

## Simplificación recomendada antes de implementación

- Cajero: estado discreto «Guardado en este equipo» / «Pendiente de envío» y
  continuidad de ventas nuevas válidas. Sin expedientes ni decisiones técnicas.
- Administrador: una bandeja «Por comprobar» y un archivo «Finalizados».
  Una fila por operación, con importe, tipo, fecha y estado. Detalles al abrir.
- Una acción principal «Comprobar». El envío idempotente del expediente y su
  consulta deben ser internos; no pedir «solicitar revisión» al administrador.
- Decisiones humanas solo dentro del detalle, con motivo y auditoría. Nunca
  usar «Listo» o «Confirmado» para resultados inciertos.
- Entrega al ADMIN: persistir/publicar automáticamente el expediente desde la
  cuenta propietaria, con backoff y control de empresa. Restringir lectura y
  decisiones en API y UI. Conservar el trabajo pendiente durante logout o
  cambio de empresa; no reasignarlo al usuario que abra la pantalla.
- Continuidad: ligar el bloqueo de duplicados a una identidad persistida del
  ticket/cobro. Un ticket explícitamente nuevo debe poder vender productos
  idénticos con otra identidad; reintentar el ticket original conserva la
  identidad y no vuelve a cobrar. No basta con eliminar la huella actual.

El ajuste superior implementa las soluciones visibles y el acceso exclusivo.
La entrega automática al administrador y la identidad persistida del ticket
siguen pendientes; la protección de ventas idénticas permanece vigente.

## Vista previa Flutter

`apps/fulltech_app/test/preview/recovery_design_preview.dart` monta los widgets
reales actuales con preferencias en memoria, repositorios ficticios y un
adaptador HTTP que rechaza todas las conexiones. Su entrada solo admite Web;
no abre ni borra perfiles SQLite de Windows/Android. No forma parte del arranque
de producción.

Selector con diez escenarios: vacío, pendientes offline, cobro incierto,
registro encontrado, caja rechazada, expediente interno, dinero declarado,
servidor sin respuesta, archivo y acceso actual del cajero. Se puede seleccionar
390 px, 1280 px o ancho adaptable. Los botones abren los diálogos reales; sus
resultados son simulados y no prueban el backend. La etiqueta «Interfaz actual»
evita presentar las recomendaciones como funcionalidad ya construida.

Para iniciar desde `apps/fulltech_app`:

```powershell
flutter run --no-pub -d web-server --web-hostname 127.0.0.1 --web-port 4487 --target test/preview/recovery_design_preview.dart
```

## Evidencia de esta revisión

- `flutter test --no-pub test/core/offline/sale_attempt_audit_sqlite_test.dart test/core/offline/recovery_queue_regression_test.dart test/modules/ventas/sale_attempt_durability_test.dart`: **44 PASS**.
  `.uat/recovery-continuity-review.log`. Incluye el bloqueo real reproducido
  por carrito igual y continuidad de un carrito distinto; no es una aceptación
  con API real en esta fase.
- `npm --workspace apps/api test -- --runInBand src/recovery/recovery-review.service.spec.ts`:
  **19 PASS**. `.uat/recovery-permissions-review.log`. Incluye el alcance del
  cajero y rechazo de decisiones no administrativas. Se confirma el
  comportamiento existente; no una política exclusiva nueva.

**Criterio:** NO-GO para afirmar «solo ADMIN» o «ninguna venta legítima se
interrumpe por una incidencia». GO para revisar localmente la interfaz actual
y acordar la simplificación indicada. Sin despliegue, publicación ni cambios
en datos financieros reales.
