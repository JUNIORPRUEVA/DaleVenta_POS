# PR #54 — inventario de ramas y corrección de regresión visual

## Alcance y base

Revisión del 22 de noviembre de 2026. Base productiva de Git:
`61d5d5aa`; candidato auditado: `b21ad57c`. Se consultó el remoto con
`git fetch origin`. No se inspeccionó ni modificó producción.

Objetivos: enumerar todas las referencias locales/remotas y worktrees de FullPOS,
identificar trabajo excluido sin sobrescribirlo y resolver el fallo real de CI.
Plan aplicado: inventario de solo lectura, comparación de historia y parches,
reproducción local del fallo, inspección visual, corrección mínima de pruebas y
referencias móviles, regresión y revisión del diff. No integrar automáticamente
variantes históricas ni el acceso offline con validación pendiente.

## Todas las referencias, no solo las ramas móviles

El inventario contiene 237 referencias distintas:

| Clasificación | Referencias |
|---|---:|
| Historia alcanzable desde el candidato | 198 |
| No son antecesoras, pero sus parches son equivalentes según git cherry | 6 |
| Historia divergente que debe revisarse mediante el ledger | 31 |
| Rama con retirada de módulos excluida del alcance | 1 |
| Nuevo acceso offline sin integrar | 1 |

El detalle individual, con nombre, revisión y cantidades de parches, está en
`INVENTARIO_REFERENCIAS_PR54_20261122.csv`.

Se ejecutó `git cherry HEAD <referencia>` sobre las 39 referencias no antecesoras.
Hay 53 commits no merge distintos sin equivalencia exacta de parche: 26 afectan
documentación/configuración histórica y 27 tocan código o pruebas. El inventario
individual está en `COMMITS_DIVERGENTES_PR54_20261122.csv`. Equivalencia de parche,
ancestry y existencia de un archivo son evidencias distintas; ninguna prueba por
sí sola equivalencia funcional completa de versiones divergentes.

Entre los commits no equivalentes hay cierres de imágenes antiguas, diagnósticos
temporales fiscales, pruebas históricas, prototipos de registro y cambios de
retirada de módulos. No deben convertirse en una fusión masiva. Por ejemplo,
`13e039b1` y `e2f9231e` retiran opciones del menú, algo excluido expresamente del
trabajo de conexión de IA; `6d3013ee` añade diagnóstico temporal de webhooks.
La política de no reintentar fallos permanentes de Guardian sí está en el código
actual (`GUARDIAN_AI_NON_RETRYABLE_CODES`), aunque el antiguo commit `26ba76f9`
no es un parche idéntico al estado actual.

El barrido de fechas desde el 19 de noviembre encontró solamente `db93ce18`
fuera del candidato. Las fechas no detectan cambios sin commit: por eso también
se hizo el barrido de archivos descrito a continuación.

### Stash y checkout antiguo

También se revisó el único stash: `stash@{0}`, `ea7fe7c3`, mensaje
`wip-salidas-tecnicas`. Su árbol tracked no difiere de la base; su tercer padre
conserva 18 archivos no rastreados del módulo `salidas-tecnicas`, incluida la
migración `20260308000200_salidas_tecnicas`. Ninguna de esas 18 rutas existe en
el candidato. Es trabajo histórico identificado fuera del PR, no una función
validada de la entrega móvil. No se aplicó ni eliminó el stash ni se incorporó
su migración. Debe tratarse como alcance independiente si se decide recuperarlo.

La rama local llamada `production-main` del checkout original sigue en
`6b3e38ed`; el remoto `origin/production-main` está en `61d5d5aa`. El candidato
sí contiene el remoto completo (`HEAD..origin/production-main` tiene 0 commits).
No utilizar el checkout original antiguo para construir esta entrega ni resetear
sus archivos pendientes. Los 11 tags se enumeraron; no se editaron etiquetas.

## Worktrees y archivos sin commit

111 worktrees registrados, 59 con pendientes; todos pudieron consultarse.
Se compararon 1.258 entradas de fuentes, pruebas y configuración:

- 768 coinciden con el candidato y 26 con la base productiva.
- 464 son variantes, con 435 combinaciones distintas de ruta y contenido.
- 123 variantes coinciden con el snapshot del ledger anterior y 46 con el
  respaldo ampliado del PR #53. Las otras 295 existen como blobs en Git.
- De las 464, 313 tienen su blob en la historia alcanzable del candidato y 151
  están preservadas fuera de esa historia en los snapshots anteriores.
- Ninguno de los 1.258 archivos cambió entre la lectura inicial y la segunda
  comprobación SHA256. No se limpió, reseteó ni modificó ningún worktree ajeno.

Los números incluyen copias entre worktrees. No son 464 funciones faltantes.
Se conserva la disposición documentada en
`REVISION_INVENTARIO_PR53_20261121.md` y `CONSOLIDACION_AMBOS_CHATS_20261121.md`.
Esta auditoría no vuelve a demostrar funcionalmente cada variante histórica.
Las que carecen de equivalencia funcional demostrada permanecen identificadas y
preservadas; no se declaran integradas ni se descartan.

La comparación detallada cubre `apps/api/src`, Flutter `lib`, pruebas e integración,
scripts, fuentes web, pubspec y Codemagic. El inventario general recoge los demás
pendientes. No se leyeron valores privados de entorno para incorporarlos al código.
Los manifests privados quedan en
`C:/Users/pc/.codex/backups/fullpos-mobile-inventory-20261122/`.

## Lo que sí está conservado y lo que falta

`git merge-base --is-ancestor` confirmó que el candidato conserva los 17 commits
principales comprobados de los dos chats, incluyendo planes (`47ce2790`),
integración IA/planes (`083425fc`), turno anterior (`aa79fa75`), recuperación y
productos, IA/PDF (`759bf50c`, `2388fe94`) y ajustes móviles/CI
(`9c38754b`, `96c37238`). La presencia histórica no implica que toda línea antigua
deba seguir activa frente a cambios posteriores.

**Falta integrar el nuevo acceso offline.** Está conservado en `db93ce18`, rama
`agent/acceso-local-seguro-20261122`, worktree limpio. Incluye 20 archivos con
almacenamiento del permiso local, integración de autenticación, diálogo de salida,
pantalla de login, dependencia y pruebas. No está en el PR #54 ni en su AAB.

Según la evidencia previa `OFFLINE_LOGIN_SEGURO_20261122.md` de esa rama:

- Windows aprobó la persistencia entre procesos con almacén nativo y datos ficticios.
- Android tuvo una prueba nativa aprobada, pero el caso posterior al reinicio del
  AVD falló con `LOCAL_LOGIN_UNAVAILABLE`; no se determinó su causa y se suspendió.
- iPhone no tiene validación nativa de ese acceso.

La evidencia offline se leyó, no se reejecutó en esta tarea. Hace falta resolver
Android, validar iOS y probar su integración con el candidato antes de prometer
una entrega completa de acceso sin conexión. No se reintroducen permisos o
credenciales de una empresa en otra para forzar una prueba.

APPYRA IA, APPYRA CRM y el puente son repositorios independientes: sus worktrees
integradores estaban limpios, respectivamente en `c666108`, `c86af6a` y `dd80d7f`.
Eso no acredita sus despliegues remotos ni los convierte en parte del PR FullPOS.

## Causa del fallo de GitHub

Run `450505778400`, job `137295187391`, candidato `b21ad57c`:
2.839 pruebas aprobadas, 5 fallidas y 17 omitidas. El análisis y los otros cuatro
controles del PR pasaron. Las cinco fallidas son comparaciones exactas de PNG a
390 px, reproducidas también en Windows y Linux:

- Categorías: `categories_390`, 0,28 % en CI.
- Formulario de categoría: `category_editor_390`, 0,20 %.
- Catálogo: `catalog_390`, 0,21 %.
- Barra de tickets: `sales_ticket_bar_390`, 0,06 %.
- Cotizaciones: `quote_history_390`, 3,61 %.

El PNG nuevo de opciones reemplazó los tres puntos anteriores y las cotizaciones
ya no llevan el adorno de documento a la izquierda. Las referencias estaban
desactualizadas; además los cuatro fixtures no precargaban `more.png`, pudiendo
capturar el botón sin terminar de decodificar su imagen.

Corrección: precargar ese recurso en los cuatro fixtures y actualizar únicamente
las cinco referencias de teléfono en Windows y sus cinco equivalentes Linux.
Se inspeccionaron imágenes reales y diferencias. No se cambió código productivo,
no se actualizaron referencias de escritorio, no se omitieron pruebas y no se
amplió la tolerancia de píxeles.

Validación del checkpoint: `flutter analyze --no-pub` sin incidencias (38,5 s);
las cuatro suites completas afectadas pasan en Windows (44 pruebas). En Linux
se actualizaron las referencias con los seis casos móviles y se inició la batería
completa sin `--update-goldens`. La primera copia reducida de la fuente produjo
fallos de entorno por no incluir archivos del backend/web consultados por otras
pruebas; se sustituyó por un archive completo de Git con la corrección de tests.
El caso de guardia de onboarding pasó además al suministrar la fuente API faltante.
No se presentan esos fallos de preparación como defectos productivos ni se ocultan.

Los logs privados de reproducción y regresión se conservan en
`C:/Users/pc/Documents/FullPOS-Mobile-Release-20261122/pr54-linux-regression/`.
El resultado de la ejecución completa y el control remoto del nuevo commit deben
revisarse antes de considerar el merge; este checkpoint no declara esos controles
como aprobados de antemano.

## Estado de la entrega completa

NO-GO para afirmar que todos los trabajos, incluido el nuevo acceso offline,
están integrados y listos para móviles. Los residuos identificados permanecen
conservados. No se hizo merge, deploy, cambio fiscal, migración ni escritura
productiva durante esta auditoría y corrección de pruebas.
