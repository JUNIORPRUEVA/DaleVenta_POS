# FullPOS: cierre local y preparación de publicación — 21 de noviembre de 2026

## Alcance y candidato

Preparar todos los cambios consolidados de FullPOS para revisión y publicación,
conservando el control del propietario sobre merge, migraciones y deploy.
No se retiran funcionalidades para evitar dependencias pendientes.

- Worktree exclusivo: `C:/t/fp-integ-20261121`.
- Rama: `agent/consolidacion-total-20261121`.
- Base remota verificada de nuevo: `33625e3cc6666867d80e5c1fae8e001dca64526c`.
- Checkpoint de código/documentos antes de este informe:
  `0850d9329c7926872d4ed0254c2caa22afcce6d5`.
- Comparación `git diff --quiet 54671906 HEAD -- apps website Dockerfile.public-web
  .github/workflows`: exit 0 antes de este cierre. El código y las referencias
  visuales son los de la validación completa anterior, sin nuevos cambios de UI.

El inventario de procedencia y las variantes conservadas siguen en
`CONSOLIDACION_CAMBIOS_20261121.csv`. Los diez commits del otro chat y los dos
de IA/PDF siguen siendo antecesores. No se sobrescribió ningún worktree original.

## Controles nuevos ejecutados

Evidencias privadas: `C:/Users/pc/.codex/backups/fullpos-consolidacion-20261121`.
Contiene también respaldos sensibles: no subir ese directorio ni sus env a Git.

| Control | Resultado efectivo | Evidencia |
|---|---|---|
| `node scripts/release/sync_api_docker_lock.mjs --check` | PASS, 756 paquetes | salida de terminal |
| `npm run api:build` | PASS | fullpos-release-api-build.log |
| E2E HTTP de límites CRM y actividad | 12 PASS, dos suites | fullpos-release-boundary-http.log |
| E2E HTTP fiscal, documentos y POS anterior | 44 PASS, tres suites | fullpos-release-fiscal-legacy-http.log |
| Contrato firmado de soporte en CRM | 4 PASS | fullpos-release-crm-support-contract.log |
| Docker API desde apps/api/Dockerfile | PASS y arranque healthy | fullpos-release-api-docker.log |
| Docker web desde Dockerfile.public-web | PASS, Astro + Flutter + nginx | fullpos-release-web-docker.log |
| Web combinada contra API y PostgreSQL locales | 10 escenarios PASS | fullpos-release-combined-smoke-retry.log |
| Upgrade PostgreSQL 16: base remota → candidato | PASS, siete migraciones y repetición idempotente | fullpos-upgrade-result.json |
| Mismo upgrade en PostgreSQL 17.11 | PASS | fullpos-upgrade-result-pg17.json |

Los comandos E2E son los del workflow, con `--runTestsByPath` y `--forceExit`.
Los 44 casos fiscales usan sockets HTTP y PostgreSQL reales, pero respuestas
externas sintéticas; no representan aceptación DGII ni emiten documentos reales.
Los 12 casos de límites usan Nest/Supertest con dependencias de negocio inyectadas.

La web combinada comprobó registro, login, rechazo de duplicados, intercambio
único/concurrente de handoff, aislamiento, bienvenida, rutas públicas/POS,
negociación Brotli, assets, renderer PDF/worker y exclusión de tickets en logs.
Esto es evidencia HTTP; no se presenta como una nueva inspección visual humana.
Se adaptó únicamente la lista de nombres de contenedores permitidos en una copia
privada del ejecutor. El original del repositorio no cambia ni se rebajan aserciones.

El primer smoke no podía alcanzar desde Windows el puerto de una red Docker
exclusivamente interna. Se conservó el fallo en fullpos-release-combined-smoke.log.
Se añadió una red frontal local solo al nginx; API y PostgreSQL permanecen en
la red interna y el puerto web se publica únicamente en 127.0.0.1:4046.

Se mantienen como evidencia previa, porque no cambió el código: API 3149 PASS
(599 omisiones), Flutter Linux 2826 PASS (17 omisiones), análisis Flutter sin
incidencias, y las verificaciones PostgreSQL/HTTP específicas del informe inicial.
No sumar estos números como casos únicos ni convertir omisiones en aprobados.
No se certifican impresoras, iOS físico ni aceptación real de servicios externos.

## Ensayo de migraciones sobre datos anteriores

Se extrajo desde Git el esquema y las 90 migraciones de la base remota en una
carpeta privada. Sobre una base nueva se crearon únicamente datos ficticios:
dos empresas con licencias activas, plan anterior sin código de catálogo,
límites distintos, una concesión adicional, un producto con stock y dos rangos
fiscales con contadores consumidos. No se usó una copia de empresas reales.

Tras aplicar las siete migraciones del candidato se compararon todos los campos
anteriores de esas filas: igualdad exacta. Las columnas nuevas de producto tienen
sus defaults previstos. Una segunda ejecución no cambió filas ni añadió migraciones.
Se repitió el procedimiento con PostgreSQL 17.11, la misma versión observada en
producción. Este ensayo acotado no sustituye una restauración verificada del
respaldo productivo antes de autorizar la aplicación real.

## Auditoría productiva de solo lectura

Se utilizó la clave SSH existente sin leer ni mostrar su contenido. Solo se
consultaron servicios y el ledger de Prisma. La consulta de BD se ejecutó dentro
de una transacción `READ ONLY`. No se consultaron datos personales de empresas.

- Backend y PWA: 1/1 réplicas; fuente efectiva GHCR por digest.
- PostgreSQL: 17.11.
- Migraciones exitosas registradas: 230; ninguna ejecución sin resolver.
- Las siete pendientes son exactamente las del candidato.
- Ninguna diferencia de contenido SQL entre los archivos conocidos y el ledger.
  Hay 43 checksums de variante LF/CRLF ya documentados; no se modifican.
- Se conservan 140 registros anteriores al baseline, fuera del árbol actual.
  Son historia previa, no una instrucción para borrarlos ni rebaselinarlos.
- Las migraciones automáticas siguen desactivadas.
- Soporte interno nuevo: no están configurados ni el destino ni el secreto.

Imágenes vigentes observadas, para volver a verificarlas antes de publicar:

```text
API ghcr.io/juniorprueva/fullpos-cloud-api@sha256:0054cdaad984c026e5b6cabe1729706faa34a6dc3e066cb471284f15ea68d7f4
WEB ghcr.io/juniorprueva/fullpos-cloud-web@sha256:2fed4d80571e69c63717b619ad834f7cee9ec4d98cc6265992b39d8573fe2db0
```

La receta de código canónica es Dockerfile.public-web; la fuente desplegada
actualmente es una imagen GHCR, no un build directo de GitHub en EasyPanel.
No basta pulsar Implementar: primero debe prepararse el digest nuevo verificado.

## Dependencias: qué bloquea cada cosa

1. **FullPOS, API y web:** sus controles locales descritos aprobaron. La historia
   sensible del repositorio del puente no entra en estas imágenes ni en FullPOS.
   Los fallos generales de CRM no significan un fallo de ventas fiscales FullPOS.
2. **Soporte dentro del chat:** el código se conserva. Requiere publicar el
   endpoint compatible de CRM y configurar APPYRA_CRM_SUPPORT_URL y
   FULLPOS_SUPPORT_SHARED_SECRET en ambos extremos, mediante almacenamiento de
   secretos y autorización separada. Sin ello falla con un aviso explícito;
   no afirma que una avería fue registrada. No se considera terminado en producción.
3. **IA, biblioteca y recursos:** requieren el candidato compatible de APPYRA IA
   y su configuración propia. Publicar FullPOS no despliega ese repositorio.
4. **Administración CRM/puente:** los candidatos siguen separados y preservados.
   Su GO completo y el tratamiento de su historia sensible se revisan aparte;
   nunca se fusiona la copia saneada con la historia que conserva el PEM.

## Orden exacto antes de los botones de EasyPanel

1. Publicar exclusivamente la rama candidata de FullPOS y abrir PR hacia
   production-main. Revisar diff y esperar todos los gates del HEAD exacto.
   Todavía no se ha hecho push ni se ha creado ese PR en este cierre.
2. El propietario realiza el merge. Comprobar de nuevo los gates sobre el commit
   de merge; los verdes de otra rama o de un PR anterior no certifican este release.
3. Preparar respaldo privado de BD y verificar su restauración. Renovar auditoría
   de esquema/ledger: deben seguir pendientes exactamente los siete SQL revisados,
   sin intentos fallidos ni diferencias de contenido. Detenerse si cambia la lista.
4. Con autorización productiva expresa, aplicar manualmente esas migraciones
   mediante un ejecutor controlado; mantener RUN_MIGRATIONS=false en el servicio.
   No ejecutar seed, backfill, migrate reset, db push ni reescribir checksums.
5. Construir y publicar imágenes inmutables del commit de merge. Web desde raíz
   y Dockerfile.public-web; API desde apps/api. Conservar argumentos públicos
   reales del asistente, entorno, secretos, mounts y fuentes actuales. Registrar
   revisión OCI y digest de ambas; no usar las imágenes QA de esta tarea.
6. Preparar en EasyPanel exclusivamente las referencias de imagen verificadas,
   con autorización separada. El propietario pulsa Implementar en backend.
   Comprobar salud, revisión efectiva, login, empresa, planes/licencia y lectura
   fiscal. No crear ventas, pagos ni e-CF reales como smoke de producción.
7. Solo después de aprobar backend, el propietario implementa la PWA. Comprobar
   web pública nueva, acceso/salida, rutas, recursos y revisión esperada.
8. Activar y validar las dependencias de IA/soporte mediante su entrega coordinada
   antes de anunciar que esas funciones nuevas están operativas para clientes.

Rollback: conservar las dos imágenes previas y el esquema aditivo. No borrar las
columnas nuevas ni restaurar una BD antigua sobre ventas posteriores. La imagen
anterior de API no conoce los nuevos contratos de recuperación/productos: evaluar
compatibilidad y escrituras nuevas antes de decidir volver atrás; preferir una
corrección compatible si ya existen operaciones nuevas. Un digest anterior es
un punto de referencia, no una autorización ni garantía automática de rollback.

## Estado

**Controles locales FullPOS descritos: PASS.**

**NO-GO para pulsar Implementar ahora.** Pendientes: publicación/PR y gates del
merge, respaldo restaurado, autorización y aplicación de las siete migraciones,
imágenes productivas del commit correcto y configuración coordinada de las
dependencias nuevas. No se hizo push, merge, deploy, reinicio, migración ni cambio
de configuración/datos de producción durante este cierre.
