# Preparación autorizada de permisos productivos

HECHO: el propietario autorizó preparar producción y activar FULLTECH después
de su propio deploy. No autorizó al agente a desplegar. Esta evidencia operativa
vive en la rama de preparación; no debe integrarse como código de la aplicación.

## Cierre después del deploy del propietario

HECHO, 2026-11-14: el propietario confirmó "ya deplegue". Se verificó el nuevo
backend 9e0f717a3e40, iniciado a18:46:21.783Z, saludable y /health HTTP200. Node22.23.4;
los dos permisos preparados están cargados en ejecución. RUN_MIGRATIONS y semillas
continúan desactivados. Se conservaron las imágenes API4e6fb33c/PWA d56a9c97,
el contenedor PWA, la configuración completa persistida y auto-deploy desactivado.

La autorización previa cubría estas acciones después de ese deploy. Se comprobó
de nuevo que el operador es ADMIN y OWNER activo de FULLTECH, su propio RNC,
credencial productiva activa, certificación PRODUCTION_READY, autorizaciones y
contadores. Se generó un plan de solo lectura y un checkpoint raíz0700/archivos0600
verificado antes de escribir. El segundo proceso exige el mismo fingerprint del
plan y rechaza diferencias observadas entre ambas lecturas. Los servicios existentes
mantienen sus bloqueos transaccionales y la prohibición de reutilizar números.

Se utilizaron únicamente los servicios de negocio YA desplegados:

1. EcfService.enableProduction: solo FULLTECH, companyId
   165e3fca-6225-479b-8805-d2205f10536c. Ahora PRODUCTION/productionEnabled=true,
   etapa de habilitación completada y auditoría CONFIG_UPDATED registrada.
2. EcfSequenceService.renew: E31 desde el próximo número3 hasta150, vigencia
   2027-12-31T23:59:59.999Z tomada de su autorización registrada. Nuevo rango
   b5871096-a6fd-47c5-9a5f-0551836a54cc. Rango anterior conservado con next3 e
   inactivo; ledger RENEWED añadido. No se consumió numeración ni se cambió la
   autorización1–150. E32 siguiente3/fin1000 y E34 siguiente2/fin50 permanecen
   exactamente iguales, incluidas sus fechas nulas. No se modificó otra empresa.

La lectura independiente posterior confirma posReady=true, emisión productiva
disponible, tipos POS E31/E32, sin bloqueo y opción de venta Normal conservada
(allowSalesWithoutEcf=true). La huella de todos los demás campos de configuración
fiscal es idéntica. Huellas completas de ventas, sesiones/movimientos de caja,
inventario, configuración comercial, documentos, intentos de envío y autorizaciones
productivas coinciden con la lectura inmediatamente anterior. El cambio autorizado
quedó registrado a18:52:22Z; nunca se creó ni envió una factura real.

Los E31/E34 TEST aceptados continúan SANDBOX, con un envío/recibo cada uno,
proyección fiscal firmada/QR íntegra y crédito118 aplicado una vez/saldo0. Las rutas
del ambiente PRODUCTION excluyen estos TEST. Por eso el antiguo ejecutor
verify-postdeploy-pr43.py falló al intentar imprimir un TEST en el ambiente actual.
Se comprobó la causa real en printDocument y con una nueva verificación independiente:
404 es el resultado esperado por aislamiento de ambientes; los documentos y sus
proyecciones firmadas siguen intactos. No se relajó el filtro para pasar el chequeo.

| Validación ejecutada en este cierre | Resultado |
| --- | --- |
| postdeploy-production-readonly.py por SSH, antes y después | Imagen/salud/permisos/empresa/huellas PASS |
| activate-authorized-fulltech-production.py por SSH sin --apply | Plan de solo lectura PASS |
| mismo ejecutor con --apply | Checkpoint/servicios existentes/auditoría/renovación PASS |
| verify-fulltech-production-active.py por SSH independiente | POS/rangos/Normal/TEST/QR/crédito/aislamiento PASS |
| Comparación antes/después de todas las huellas comerciales y fiscales inmutables | Todas idénticas PASS |
| python -m py_compile de los tres nuevos ejecutores privados | PASS |
| GitHub PR44 y jobs43626251190 consultados nuevamente | Propietario ya hizo merge;4/4 PASS |

Los ejecutores se ejecutaron con Get-Content -Raw del archivo local, canalizado a
ssh con la clave existente, BatchMode=yes, StrictHostKeyChecking=yes y
ConnectTimeout=15, destino root@31.97.99.70, comando python3 -. Solo el ejecutor
de activación recibió --apply. Nunca se mostró ni exportó el contenido de la clave
privada o de credenciales.

Checkpoint de empresa antes de activar:
/etc/easypanel/agent-checkpoints/fullpos-fulltech-activation-2026-11-14T18-52-21-376093Z/.
Recibos y ejecutores privados:
C:/Users/pc/.codex/backups/fullpos-ecf-commercial-closeout-20261114/.

GitHub confirma PR44 integrado por el propietario como
cbc3eceb205e4af6e914818485a23bcbdc448055,14/11/2026 a18:38:59Z. Su HEAD5937fa85
conserva4/4 controles aprobados en43626251190; cambia solo pruebas/documentación.
No necesita nueva imagen. En esta tarea no cambió código, no se ejecutó merge,
deploy, reinicio, migración, seed ni envío al proveedor por parte del agente.

Estado: GO para activación técnica de FULLTECH. Ya no está pendiente otro deploy
para cargar los permisos. Falta observar una venta real legítima del propietario
para afirmar aceptación comercial productiva DOSA/DGII; no se sustituyó por una
venta ficticia. La revisión de diseño corresponde a la siguiente fase.

## Preparación anterior al deploy (evidencia histórica)

Se utilizó la operación oficial updateAppEnv de EasyPanel2.37.0 para guardar
únicamente los dos permisos productivos del backend daleventapos/backend:
DOSA_PRODUCTION_EMISSION_ENABLED y DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED.
La implementación instalada de esa operación solo guarda configuración y su
auditoría; no invoca despliegue ni reinicio.

Antes de guardar se comparó el fingerprint de todo el backend/PWA con la propuesta
revisada, se comprobó el contrato y se creó un checkpoint privado raíz0700 con
archivos0600, verificados contra su contenido original sin exportarlo. Una nueva
lectura en otro proceso confirma:

- Ambos permisos están guardados habilitados en el panel.
- Todas las demás líneas de entorno y todos los demás campos persistidos del
  backend se conservan exactamente, incluido el campo opcional dotEnvPath nulo.
- Configuración completa PWA, imágenes y credenciales permanecen intactas.
- Auto-deploy desactivado, migraciones automáticas y semillas apagadas.
- Los mismos contenedores siguen ejecutándose sin cambiar su hora de arranque;
  API saludable, sin cargar todavía los permisos recién guardados.
- FULLTECH continúa SANDBOX/productionEnabled=false; ninguna factura fue emitida
  ni se modificaron numeración, autorizaciones o datos comerciales.

La primera comprobación estricta de planificación se detuvo antes de escribir
por la proyección de dotEnvPath:null de la API. Se leyó el código instalado:
null y ausencia mantienen desactivada la escritura de un archivo dotenv. Tras
esa comprobación se ejecutó el plan; la lectura independiente final verificó
además que el almacenamiento conservó exactamente el null original.

## Trazabilidad

| Comprobación real | Resultado |
| --- | --- |
| inspect-env-contract-readonly.py por SSH | Contrato y handler oficial sin deploy PASS |
| prepare-authorized-production-permissions.py sin --apply por SSH | Plan/fingerprints/imagen/protecciones PASS |
| mismo script con --apply, tras autorización del propietario | Guardado oficial/checkpoint/readback PASS |
| verify-production-permissions-prepared.py por SSH, proceso independiente | Todos los demás campos/entorno/PWA preservados PASS |
| readiness-readonly.py por SSH | FULLTECH aún TEST, sin resultados inciertos, contadores preservados PASS |

Checkpoint privado del servidor:
/etc/easypanel/agent-checkpoints/fullpos-ecf-production-2026-11-14T18-42-44-879Z/.
Contiene configuración sensible; solo se informa su ubicación, nunca su contenido.
Recibos seguros y ejecutores locales:
C:/Users/pc/.codex/backups/fullpos-ecf-commercial-closeout-20261114/.

PR44 de regresiones comerciales está listo para revisión/merge del propietario:
https://github.com/JUNIORPRUEVA/DaleVenta_POS/pull/44.
HEAD5937fa85bccf6e8b3aebff491ffb5164c5c6829d,4/4 controles aprobados:
https://github.com/JUNIORPRUEVA/DaleVenta_POS/actions/runs/43626251190.
Solo modifica pruebas y documentación; no requiere imágenes nuevas de aplicación.

## Paso entonces reservado al propietario (ya completado)

Pulsar Implementar únicamente en daleventapos/backend. Conservar imagen API
4e6fb33c; no desplegar PWA para este cambio de permisos. El agente no ha pulsado
Deploy, reiniciado servicios, ejecutado migraciones ni emitido documentos.

Después de su confirmación se verifica API sana con permisos cargados y se
continúa la autorización YA otorgada: activar solo FULLTECH mediante su flujo
existente y completar la vigencia operativa E31 según su autorización registrada
31/12/2027. Siguiente número observado3, fin150; nunca rebobinar ni ampliar.
Conservar E32 siguiente3/fin1000 y E34 siguiente2/fin50, sin inventar fechas.
Reconsultar esos valores antes de escribir, conservar historial y registrar la
operación. No usar una factura real como prueba de humo.

El estado pendiente descrito en esta sección histórica quedó superado por el
deploy del propietario y el cierre verificado al inicio de este documento.
