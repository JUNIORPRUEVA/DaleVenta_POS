# Consolidación: cierre local de bloqueos — 2026-11-21

Continuación de `CONSOLIDACION_AMBOS_CHATS_20261121.md`. Este documento distingue
los candidatos locales de los repositorios remotos y de producción. No autoriza
publicación, merge protegido, migraciones, rotación de claves ni despliegue.

## Alcance y conservación

Diseño móvil pausado. Se trabaja exclusivamente en candidatos de integración;
los worktrees originales y las bases protegidas permanecen sin cambios.
El inventario anterior conserva 1189 entradas pendientes de los originales;
no se sustituyen variantes divergentes mediante elecciones masivas ours/theirs.
Las evidencias privadas están en
`C:/Users/pc/.codex/backups/fullpos-consolidacion-20261121`.
Ese directorio contiene material sensible y nunca debe subirse al repositorio.

## CRM: causas y correcciones mínimas

Candidato: `C:/t/crm-integ-20261121`, rama
`agent/consolidacion-soporte-planes-20261121`, checkpoint anterior `4e8d4a2`.
Correcciones guardadas localmente en `c86af6a`; worktree limpio tras el commit.

- Calling: la importación del script con cabecera shebang fallaba en Vitest/Vite.
  Se retira esa cabecera del archivo no ejecutable; la entrada documentada
  mediante `node` se conserva y se verifica ejecutando `--help` sin red.
- Laura: una fecha fija del 17 de noviembre ya dejaba los mensajes fuera de la
  ventana de respuesta. El fixture usa la fecha de ejecución. Un caso negativo
  adicional verifica que un mensaje de hace 25 horas no produce respuesta libre.
  No se cambian las reglas de WhatsApp ni el runtime del agente.
- Paneles simulados: se cerraba JSDOM antes de finalizar peticiones y lecturas
  de respuesta. Un helper de pruebas espera la actividad de esa ventana y falla
  explícitamente ante una petición pendiente. Los rechazos siguen propagándose.
  El envío de plantilla espera además la confirmación visible de cierre.
- APIs de navegador: JSDOM recibe `pretendToBeVisual` para rAF y un mock explícito
  de `scrollIntoView` en el fixture del asistente. No se modifica la interfaz real.
- Notificaciones: el fixture de 1210 inserciones SQLite cede periódicamente el
  event loop, igual que el fixture voluminoso vecino. Se conservan cantidades,
  comprobaciones de aislamiento y persistencia; no se reintentan solicitudes.

Resultados previos conservados, sin presentarlos como aprobados:

- `crm-backend-final-serial.log`: 200 suites, 2581 PASS y 3 omisiones; sin errores.
- `crm-backend-final-default.log`: mismos casos aprobados, pero dos rechazos
  sin manejar al destruir ventanas; ejecución fallida.
- `crm-backend-clean-final.log`: 4 fallos de notificaciones al competir fixtures
  síncronos con sockets HTTP; ejecución fallida. Los dos rechazos anteriores
  dejaron de reproducirse.
- `crm-dom-teardown-focused.log`: 61 PASS en cuatro suites.
- `crm-notifications-fixture-fixed.log`: 12 PASS en dos suites.

La repetición de `npm test` registrada en `crm-backend-final-verified.log`
terminó con 197 suites PASS, 4 fallidas, 2578 casos PASS, 6 fallidos y 3 omitidos.
No reaparecieron los dos rechazos de desmontaje ni los fallos de notificaciones.
Fallaron offline-24h, panel-campana-uat, panel-sales-uat y pos: cuatro tiempos
agotados y dos aserciones. El origen de todos esos fallos no se atribuye a los
cambios actuales sin una reproducción comparativa específica.
`npm test -- --maxWorkers=2`, sin cambiar configuración, timeouts ni aserciones,
terminó con 200 suites PASS, una fallida, 2583 casos PASS, uno fallido y 3 omitidos.
Evidencia: `crm-backend-final-bounded.log`. El fallo restante está en
`customer-lifecycle-overrides.test.js:91`: esperaba INTERESTED y obtuvo PROSPECT.
La reproducción específica en la base anterior `15af69a` produjo el mismo fallo
(12 PASS, uno fallido; `crm-lifecycle-baseline-scoped.log`). La reproducción
específica en el candidato aprobó sus 13 casos (`crm-lifecycle-current-scoped.log`).
Es un comportamiento intermitente ya reproducido en baseline; no se modifica su
regla comercial ni se debilita su aserción dentro de esta consolidación.
La repetición focalizada de las otras cuatro suites fallidas aprobó 94 casos
(`crm-parallel-failures-scoped.log`, `npx vitest run tests/offline-24h.test.js
tests/panel-campana-uat.test.js tests/panel-sales-uat.test.js tests/pos.test.js
--maxWorkers=2`). Ese resultado no sustituye la ejecución completa fallida.
Los flujos usan HTTP y SQLite locales reales; IA y entrega WhatsApp simuladas.
No prueban entrega a Meta, calidad del modelo externo ni comportamiento productivo.

Archivos de CRM en este seguimiento (todos bajo `backend/`):

```text
scripts/check-whatsapp-calling.mjs
tests/whatsapp-calling.test.js
tests/laura-whatsapp-end-to-end.test.js
tests/assistant-ia.test.js
tests/notifications-user-persistence.test.js
tests/panel-centro-ia-chats-uat.test.js
tests/panel-conv-list-uat.test.js
tests/panel-plantilla-contacto-uat.test.js
tests/browser-network-idle.test.js
tests/helpers/browser-network-idle.mjs
```

`node --check` aprobó el script Calling, el helper y el fixture del asistente.
`git diff --check` no encontró errores. Este seguimiento no modifica Prisma,
reglas fiscales, planes, datos comerciales ni pantallas del cliente.

## Puente: saneamiento ensayado sin tocar el original

Original preservado: `C:/t/bridge-integ-20261121`, HEAD `dd80d7f`.
Se creó un bundle privado de historia original y se verificó con
`git bundle verify`. Una restauración independiente recuperó los 451 commits
y el HEAD completo `dd80d7f7f635fbc2924c3a1f4d1b1f401ec56ec4`.

En una copia mirror nueva, independiente y privada se utilizó
git-filter-repo 2.47.0 para retirar exclusivamente:

- `backend/keys/license_sign_private.pem`.
- `lic22_appyra_20260907T1142.tar`.

Procedimiento basado en la [documentación oficial de git-filter-repo](https://github.com/newren/git-filter-repo/blob/v2.47.0/Documentation/git-filter-repo.txt).
No se empleó force-push. Se archivaron tres referencias de árboles del editor
solo en la copia privada; siguen conservadas en el original y en su respaldo.

Una primera verificación esperaba igualdad del número de commits y falló.
La comprobación posterior verificó cada uno de los 451 commits originales:
árbol sin las dos rutas, modos y blobs, autor/committer, codificación, mensaje
y padres traducidos. Se obtienen 242 identidades distintas: 209 duplicados
históricos quedan idénticos al retirar los archivos. Ningún commit mapea a cero.
El árbol de código del HEAD actual es exactamente igual al original.

Checkout saneado: `C:/t/bridge-saneado-20261121`, HEAD `d47759a`.
Es un repositorio independiente: no fusionarlo con la historia contaminada.
Su origen es el mirror local y el push apunta a `disabled://local-rehearsal`.

Validaciones efectivas:

```text
npm ci                          PASS
npm run check:secrets:history    PASS, copia saneada
npm test                        95 PASS
git fsck --full                 PASS
```

La comprobación privada de correspondencia indica que la clave histórica
coincide con la clave pública rastreada actualmente. No se comprobó qué clave
usa producción; no se leyó ni cambió su configuración. Nunca se imprime el PEM.
El saneamiento local no elimina material del remoto ni invalida sus copias.
El original conserva intencionadamente su historia y continúa bloqueado para
publicar esa historia sin un procedimiento separado.

## Condiciones restantes y decisión

1. Resolver el fallo intermitente de clasificación de clientes de CRM y los
   fallos de la pasada normal antes de declarar toda la batería aprobada.
   La repetición acotada también falló; no existe un PASS completo final.
2. El propietario debe aprobar una estrategia coordinada de publicación del
   puente saneado; nunca mezclar de nuevo la historia con material sensible.
3. Antes de decidir rotación de claves, auditar de forma autorizada y solo
   lectura su uso efectivo, y preparar compatibilidad para clientes existentes.
4. Los nuevos candidatos combinados todavía no tienen controles remotos de
   GitHub Actions. No equivalen a los PR anteriores aprobados.
5. Siguen vigentes las siete migraciones pendientes respecto de la base remota
   y las limitaciones de hardware/iOS/servicios externos del informe inicial.

**NO-GO para merge protegido, publicación remota y producción.** No se realizó
push, deploy, reinicio, migración compartida, modificación de empresas ni cambio
de permisos fiscales. El cierre local no constituye autorización de release.

## Conservación y remotos revalidados

`python verify-preservation.py`: 21 worktrees originales, 1189 pendientes y
12 fuentes ignoradas, cero diferencias. La consulta `git ls-remote` del cierre
confirmó FullPOS 33625e3c, IA 09c451e, CRM 0315c4c y puente afa4230.
El escaneo de literales de alta confianza de los diffs rastreados no encontró
claves privadas ni patrones de tokens en los cuatro candidatos. Es un control
acotado; no sustituye el análisis completo de historia del puente.
