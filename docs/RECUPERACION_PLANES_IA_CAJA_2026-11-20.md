# Recuperación de cambios pendientes — Planes, IA y caja

Base: production-main d35fc09e, PR51 ya desplegado por el propietario.
Rama aislada: agent/recover-plans-ia-cash-20261120.

## Auditoría de procedencia

Se inventariaron 219 referencias Git y se revisaron las 19 referencias cuyo nombre
corresponde a chat, IA/cuenta, planes, licencias o aviso de turno. Se buscaron también
commits recientes por las rutas de IA, planes, licencias, caja y POS y cambios sin
commit en todos los worktrees existentes. El inventario privado registra los hashes
y los siete archivos recuperados, sin credenciales ni backups de empresas.

| Trabajo | Origen | Situación y decisión |
| --- | --- | --- |
| Sistema de planes | 21f61aeb, 7f1abb04, 47ce2790 | Ya integrado mediante PR50; conservar |
| Contexto de cuenta/licencia IA | 1bb48ae0 | Ya integrado; conservar |
| Diseño del chat | 19d3a57c, bf03b30e, b2fb1b54 | Árbol de core/ai_assistant idéntico al último commit; conservar |
| Panel de Plan actual y prueba de menú | Diff sin commit en fullpos-planes-de-pago-impl | Recuperado sobre la base actual, sin reemplazar el POS completo |
| Precios/módulos de web pública | Cinco archivos sin commit en el mismo worktree | Recuperados; prueba de correspondencia con el catálogo existente |
| Aviso de turno anterior | aa79fa75 | Recuperado mediante merge que conserva su commit original |
| Eliminación de módulos del menú | 13e039b1 | Fuera del alcance y excluida como en la integración anterior |
| Copia APPYRA en finalesdaleventas-appyra | Worktree antiguo, archivos sucios | No sobrescribir código nuevo con esa copia; carece de mejoras posteriores |
| Baseline automático de otra sesión | ebfdda35 | Incluye archivos ajenos; no fusionar un checkpoint completo |

La omisión anterior fue de alcance: probar la imagen/commit seleccionado no
detectó que el panel lateral y el sitio de precios seguían sin commit. Esos
archivos no se perdieron. Se capturó su checkpoint y se aplicó únicamente su diff.

## Comportamiento recuperado

- Cuenta y empresa presenta «Plan actual», uso y estado obtenidos del backend,
  catálogo y navegación hacia transferencia/mejora de plan. El indicador de pago
  depende de una orden pendiente del servidor.
- Un bloqueo no se describe como impago sin evidencia. Las licencias antiguas
  conservan sus cupos/código y no muestran un tope comercial de almacenes inferido
  del valor de compatibilidad por defecto.
- La web anuncia RD$1,000 / RD$2,500 / RD$3,500 / RD$5,000 y módulos por plan,
  de acuerdo con el catálogo ya existente. No se ejecuta ningún seed ni se cambia
  el catálogo productivo.
- El turno de otro día se identifica en el chip y menú; CASH_SESSION_STALE
  explica cerrar y abrir turno. Se usa cashStateStaleShiftProvider existente;
  no se cambia la fecha comercial, el umbral, permisos o movimientos de caja.

## Fronteras de seguridad

Sin cambios en apps/api, Prisma, credenciales, facturación e-CF, contadores,
licencias o datos de empresas. No emitir documentos ni crear pagos para verificar
esta integración. No incluir archivos .env, docs/backups, artefactos ni generados
ajenos. El propietario conserva la decisión de merge y el botón de implementación.

## Validación

| Comprobación local | Resultado |
| --- | --- |
| flutter analyze --no-pub, árbol final | PASS, sin incidencias |
| Regresión Planes/IA/caja/e-CF/cotizaciones y controles | 859 PASS |
| Revalidación final Planes y panel tras conservar fuente del tema | 64 PASS |
| Panel por separado: navegación, 1280/390, licencia antigua y bloqueo | 10 PASS |
| flutter build web --release --no-pub --no-wasm-dry-run | PASS, 54.9 s |
| npm test, website | 14 PASS, incluida correspondencia de precios/cupos con el seed leído como texto |
| npm run check, website | 0 errores, 0 warnings; un hint preexistente returnValue |
| npm run build, website | PASS, 14 rutas |
| git diff --check | PASS |

Las capturas usan los widgets reales con empresa/catálogo ficticios; se inspeccionó
el panel a1280 y390. Se corrigió que el botón rectangular descartara la familia
tipográfica del tema, sin alterar tamaños/colores o acciones comerciales. Estas
capturas no son una prueba de emisión ni de pago real en producción.

Incidencias de los verificadores corregidas: ruta de pruebas inexistente en el
primer comando amplio; captures de imagen necesitaban runAsync; las animaciones
del menú con indicador continuo requerían bombeos acotados. Una ejecución iniciada
antes de terminar los cambios se descartó; la regresión final se repitió con PASS.
No se relajaron comprobaciones ni se actualizaron goldens para ocultar fallos.

Se mantuvieron los worktrees originales y se excluyeron de esta rama los generados
por pub get. El diff de apps/api y features/ecf contra production-main está vacío;
core/ai_assistant sigue idéntico al diseño incluido. La publicación de un nuevo
cliente no requiere volver a desplegar backend ni migraciones.

## Entrega y publicación

Se conserva el commit original de caja aa79fa75 mediante un merge y se realiza
un commit separado para los archivos recuperados y sus pruebas. Preparar el PR
contra production-main, verificar CI en su HEAD y no hacer merge automáticamente.
Solo después del merge del propietario se prepara la imagen combinada PWA desde
el resultado exacto, con los mismos argumentos públicos autorizados y sin construir
en el servidor. El propietario conserva Implementar; no redeplegar backend por
esta corrección de interfaz.

La observación del propietario de que IA parece antigua en privado no se considera
resuelta por esta recuperación del panel. Los commits de diseño están acreditados;
queda identificar si el usuario abre GlobalAiChatSheet o el asistente específico
de cotizaciones antes de proponer otra modificación visual de IA.
