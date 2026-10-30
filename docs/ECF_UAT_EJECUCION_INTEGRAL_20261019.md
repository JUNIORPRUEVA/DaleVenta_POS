# FullPOS Cloud — ejecución UAT e-CF / Alanube / DGII

**Fecha:** 2026-10-19  
**Rama:** `feature/ecf-alanube`  
**Commit base:** `6b3e38ed`  
**Resultado consolidado:** **NO-GO para UAT funcional e integración**. Las pruebas automatizadas enumeradas abajo pasaron; la ejecución funcional se detuvo por el control de aislamiento de producción.

## Alcance y preservación

La solicitud autorizó conservar el trabajo local existente y continuar sin limpiar, restaurar, sobrescribir ni eliminarlo. El inventario Git antes de las validaciones tenía 133 entradas: 35 rutas rastreadas modificadas y 98 rutas nuevas/no rastreadas. El inventario y esas cantidades se mantuvieron iguales después de las validaciones. No se ejecutaron `reset`, `clean`, `checkout`, `stash`, commit, push, merge, deploy, seed ni migraciones. No se modificó código. Este informe es el único archivo agregado por esta ejecución.

La política `AGENTS.md` permite continuar fases múltiples cuando el usuario lo pide expresamente. La política también exige detener las operaciones con riesgo de producción y preservar el trabajo existente.

## Entorno observado

| Componente | Evidencia | Estado |
|---|---|---|
| PostgreSQL desechable | Listener en `127.0.0.1:56551`; el API tenía conexiones establecidas solo a ese puerto en la instantánea consultada | PASS puntual; no prueba aislamiento durante toda una sesión |
| API UAT | Listener en `127.0.0.1:4004`; `GET /` devolvió HTTP 200 | PASS puntual |
| Web | Servidores locales en 8082 y 8083; `GET /` devolvió HTTP 200 | PASS de disponibilidad, sin prueba de flujo UI |
| Web, `main.dart.js` | SHA-256 coincide con el kit: `38C95F334F76D08E813BEB23241EB32146FBF85F2DC1366528EF7D4BE2532A34`; bundle contiene `127.0.0.1:4004` | PASS de identidad del artefacto registrado; ejecución bloqueada |
| Windows UAT | El manifiesto declara rama `feature/ecf-alanube`, commit `6b3e38ed`, `appEnv=uat` y `uatProfile=true`. SHA-256 de `fullpos_cloud.exe` y `app.so` coincide con `docs/ECF_UAT_MANUAL_KIT.md` | PASS de identidad con el kit; el ejecutable no se abrió |
| Build vs. árbol local | El manifiesto identifica el commit base; no registra el diff local. Por ello no se comprobó que los artefactos incluyan las 133 rutas locales pendientes | BLOCKED |

No se imprimieron valores de `.env`, contraseñas ni tokens. Los valores de API del manifiesto se omitieron.

## Bloqueo de aislamiento y concurrencia

Se observaron procesos locales UAT ya activos: launchers `visual-uat.ps1 -Action start-api`, NestJS en 4004, PostgreSQL en 56551, servidores Web 8082/8083/8084 y un monitor de red. No había un proceso Jest activo al revalidar. Estos servicios no prueban que el árbol Git estuviera siendo editado; sí hacían inseguro iniciar una segunda migración o una sesión que escribiera en la misma base UAT. No se detuvieron procesos ajenos.

La consulta local de sockets encontró dos conexiones TCP establecidas a `31.97.99.70:443` propiedad de PID 3584. La ruta del proceso era `C:\Program Files\DaleVentas POS\app\fullpos_cloud.exe`, una instalación comercial. No se inició ni se utilizó ese proceso. El monitor de red activo apuntaba a `C:\b\ecf-uat-dist\FullPOS-UAT-20261019-154848\fullpos_cloud.exe`, no a la ruta comercial observada. El ejecutable UAT no estaba corriendo.

El kit requiere que no haya conexiones al host productivo antes de abrir un artefacto. Como se observó una conexión ya existente desde la instalación comercial y la instrucción prohíbe modificar instalaciones comerciales, no se cerró ese proceso ni se inició el Windows UAT o el flujo Web. No se accedió al host productivo ni se inició conexión a Alanube o DGII. La inspección visual de la pestaña Chrome existente tampoco fue posible: el control informó que la pestaña ya pertenecía a otra sesión de navegador.

**Conclusión de seguridad:** no se pudo demostrar aislamiento completo durante toda la UAT. Los sockets locales del API hacia 56551 son una observación puntual, no una garantía continua. No se continuó con operaciones funcionales.

## Evidencia de validaciones

| ID | Escenario / esperado | Resultado observado | Estado |
|---|---|---|---|
| ENV-01 | Rama y estado inicial identificados; conservar cambios | `feature/ecf-alanube`; 133 entradas antes y después de las pruebas; sin operaciones destructivas | PASS |
| SEC-01 | No editar concurrentemente el árbol | No se observó un proceso editor/build escribiendo fuente; sí servicios UAT activos que comparten la base/almacenamiento | PASS para no iniciar servicios duplicados; bloqueo para pruebas con escritura |
| SEC-02 | Ninguna conexión productiva durante UAT | Se observó una conexión preexistente del ejecutable comercial a `31.97.99.70:443`; el ejecutable UAT no estaba activo | FAIL de precondición / UAT detenida |
| API-01 | API UAT local disponible | Listener `127.0.0.1:4004`; `GET /` respondió 200 | PASS puntual |
| DB-01 | DB desechable local disponible | Listener `127.0.0.1:56551`; conexiones observadas desde el API a ese puerto | PASS puntual; sin migración |
| ART-01 | Artefactos Windows/Web identificados por hashes | Hashes Web, exe y `app.so` coinciden con el kit; manifiesto declara perfil UAT | PASS de identidad con kit; build de cambios locales no probado |
| API-02 | Suite unitaria backend | 121 suites aprobadas; 1,266 pruebas aprobadas; 23 suites y 312 pruebas omitidas | PASS. La expresión del filtro coincidió con todas las suites unitarias. Sin suites de integración PostgreSQL |
| FL-01 | Pruebas Flutter e-CF | `flutter test test/features/ecf`: 141 pruebas aprobadas | PASS |
| FL-02 | Guardas/configuración UAT | `flutter test test/core/config`: 37 pruebas aprobadas, incluidas URL local, redirección productiva y aislamiento de almacenamiento | PASS unitario; no sustituye observación de red de una app ejecutándose |
| FL-03 | Análisis Flutter | `flutter analyze`: `No issues found!` | PASS |
| DB-02 | Validar esquema Prisma sin conectarse a DB | `npx prisma validate` con URL ficticia local de validación: esquema válido | PASS |
| WEB-01 | Inspección visual Web y responsive | No hubo navegación ni captura; pestaña existente no accesible en esta sesión | BLOCKED |
| WIN-01 | Abrir e interactuar con Windows UAT | No se abrió. La única app observada era la instalación comercial y tenía conexión productiva existente | BLOCKED |
| DGII-01 | Solicitud, autoguardado, documentos, consentimiento, envío, correcciones, versiones e historial | Sin interacción autenticada ni escrituras en la base compartida | BLOCKED |
| FT-01 | Panel Fulltech, permisos y aislamiento entre empresas | Sin interacción funcional | BLOCKED |
| ECF-01 | Simulación E31/E32/E34 en API con transporte simulado | Hay pruebas unitarias cubiertas por las suites; no se ejecutó escenario funcional PostgreSQL/API | PARTIAL |
| POS-01 | Regresión funcional POS tradicional | Incluida solo en la cobertura unitaria general cuando corresponde; no se ejecutó flujo funcional de ventas/caja/inventario | PARTIAL |
| MOB-01 | Android e iOS | No se verificó disponibilidad ni se construyeron | BLOCKED |

No se reprodujo un defecto de producto y no se hicieron correcciones.

## Decisiones

| Área | Decisión | Motivo |
|---|---|---|
| Desarrollo interno | NO-GO | Análisis y pruebas unitarias pasan; faltan build reproducible del árbol local y validación funcional/visual |
| Backend UAT | NO-GO | Servicio responde localmente; no se ejecutaron migración ni integración PostgreSQL en esta ronda |
| Windows UAT | NO-GO | No se abrió el artefacto; aislamiento de producción sin demostrar |
| Web UAT | NO-GO | Solo disponibilidad HTTP y hash; sin inspección de UI, login, responsive ni descargas |
| Android UAT | BLOCKED | No auditado/compilado |
| iOS UAT | BLOCKED | No auditado/compilado |
| Expediente DGII interno | NO-GO | Escenarios UI/API funcionales pendientes |
| Panel Fulltech | NO-GO | Escenarios funcionales y permisos pendientes |
| Simulación e-CF | PARTIAL / NO-GO funcional | Pruebas unitarias aprobadas; escenario integrado pendiente |
| Regresión POS | PARTIAL / NO-GO funcional | Suites unitarias aprobadas; regresión funcional pendiente |
| Integración de rama | NO-GO | No se autorizaron ni ejecutaron commit/merge; cambios locales permanecen sin confirmar |
| Despliegue productivo | NO-GO | No autorizado ni ejecutado |
| Alanube real | NO-GO | Llamadas reales prohibidas y no ejecutadas |
| Certificación DGII real | NO-GO | Envíos reales prohibidos y no ejecutados; UAT no equivale a certificación |

## Pendientes para reanudar

1. Resolver el socket productivo existente desde la instalación comercial mediante el responsable autorizado; esta ejecución no debe cerrar ni reconfigurar esa instalación.
2. Confirmar que la comprobación de sockets productivos queda vacía antes de abrir cualquier artefacto UAT.
3. En una ventana sin otro uso de la base, ejecutar la migración autorizada contra la DB desechable 56551, sembrar solo datos sintéticos y probar API/Windows/Web con monitoreo de red continuo.
4. Confirmar que los artefactos fueron construidos desde el árbol local actual y ejecutar la matriz funcional y responsive del kit.
5. Auditar/compilar Android e iOS en entornos compatibles.

**No se concede aprobación oficial fiscal, integración ni producción.**
