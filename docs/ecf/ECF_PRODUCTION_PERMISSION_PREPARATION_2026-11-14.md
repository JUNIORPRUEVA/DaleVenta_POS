# Preparación autorizada de permisos productivos

HECHO: el propietario autorizó preparar producción y activar FULLTECH después
de su propio deploy. No autorizó al agente a desplegar. Esta evidencia operativa
vive en la rama de preparación; no debe integrarse como código de la aplicación.

## Resultado aplicado

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

## Paso reservado al propietario

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

Preparación: GO. Activación efectiva de FULLTECH: pendiente del deploy manual
del propietario y la verificación posterior; no está finalizada todavía.
