# Integracion de Mayoreo para produccion

## Objetivo y base conservada

Solicitud: integrar Mayoreo en production-main y desplegar con las funciones
actuales del producto, evitando distribuir una copia antigua de la UAT.

- HEAD local de production-main y Mayoreo: 6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1.
- Origin/production-main observado: bdb0d10e08e197adb68b302410c0a131fa83b2bc.
- El HEAD local contiene siete commits adicionales respecto del remoto.
- Snapshot del codigo actual de production-main, incluidas sus ocho mejoras
  locales de codigo/pruebas y version 141: 3fddb8062aa38cc2db29a27abb49c8ff07dca392.
- Snapshot Mayoreo validado: 6793e16ee1dec0fcd3c53cd7dee039b27d0168ec.
- Integracion aislada: C:/src/fullpos-mayoreo-prod,
  rama agent/mayoreo-production-20261018.
- La fusion conserva la navegacion, ajustes, formularios y updater actuales.
  Los worktrees originales y sus indices no se modifican.
- Las imagenes regeneradas por tests y el informe binario de Inno no forman
  parte del checkpoint de codigo.

## Release candidato

Version prevista 1.0.6+142. La consulta publica de actualizaciones de produccion
ofrece 1.0.6+141. Los artefactos se construyen localmente desde un commit limpio;
no se compila Flutter ni Docker en el servidor productivo.

## Servicios actuales y rollback

Solo corresponden a este producto daleventapos_backend y daleventapos_pwa.

- API actual: easylpanel/daleventapos/backend:updater-137-20261012T0145Z.
  Image ID: sha256:5f6a8f6c1f18aa9ffadad5e6b8c0dae4126998377f9a42ad5079a77462a2cdb4.
- PWA actual: easypanel/daleventapos/pwa:rel-bdb0d10e-20261011T0048Z.
  Image ID: sha256:8d7b8c3084b9f66a0938e31d88be2e81322e51441f3265fb04059511abc003c5.

## Gates antes de publicar

1. Revisar el diff combinado y preservar las mejoras de la base.
2. Analizar, compilar y ejecutar la regresion del codigo combinado.
3. Validar la integracion contra datos sinteticos UAT.
4. Crear artefactos inmutables con commit, version y SHA-256.
5. Revisar la migracion aditiva 20261013180000_wholesale_price_lists y el
   historial real. Mayoreo queda false por defecto en las empresas existentes.
6. Tener respaldo verificado y rollback de imagenes antes de migrar/desplegar.
7. Resolver las autorizaciones especificas de migracion y firma Windows.
8. Publicar production-main y desplegar solo los artefactos verificados;
   comprobar salud, version y carga de PWA sin crear ventas en produccion.

## Evidencia de preparacion

- Integracion funcional: dd8d2729e78183f4a66046b7fc4023e8b8736311.
- SDK web fijado a Flutter 3.41.6: 2f99ff9492c834ae7ab543b6b6d9da6909be5c9c.
- npm ci: completo; 15 avisos de vulnerabilidad de dependencias existentes
  (3 moderate, 10 high, 2 critical). No se ejecuta npm audit fix ni se cambia
  el arbol de dependencias dentro de este despliegue.
- API build: PASS. Prisma validate con entorno UAT local: PASS.
- API Jest: 75 suites y 743 pruebas PASS; 1 suite/8 pruebas omitidas.
- Flutter analyze: PASS, sin incidencias. Flutter tests: 1282 PASS, 1 omitida.
- HTTP UAT integrado: PASS, cantidades limite, override manual persistido,
  snapshots historicos, desactivacion con reglas existentes y aislamiento.
- E2E autenticado Mayoreo: PASS; se repitio con detectOpenHandles/forceExit
  tras el aviso de salida tardia de Jest, tambien PASS.
- Historial productivo: 169 migraciones aplicadas; solo queda pendiente
  20261013180000_wholesale_price_lists.
- Respaldo previo en servidor:
  /root/fullpos-deploy-backups/mayoreo-142-20261018/database-before-mayoreo.dump.
  Tamano 6317605 bytes; catalogo pg_restore --list validado.
  SHA256 c59b94be8c8450f04de811eb604d54b4c38688eec076aec3f3d9753cbd7c38e0.
  Las especificaciones privadas de ambos servicios se guardan en esa misma
  carpeta con permisos 0600; no se copian ni muestran credenciales.
- La descarga de la imagen SDK web se cancelo por lentitud. La compilacion
  web usa Flutter 3.41.6 local. El empaquetado sustituye todos los archivos
  estaticos y copia la configuracion actual sobre el runtime nginx 1.31.6.
  Los dos modulos brotli y entrypoint del runtime local se compararon por
  SHA256 con produccion y coinciden. No se reutiliza JavaScript antiguo.

Estado: pruebas combinadas PASS; artefactos, publicacion y despliegue pendientes.

## Artefactos verificados

- Windows oficial compilado desde worktree limpio
  C:/src/fullpos-mayoreo-release142, commit 2f99ff9492c834ae7ab543b6b6d9da6909be5c9c.
  FullPOS-Setup-1.0.6-142.exe: 40202765 bytes, NotSigned.
  SHA256 D90FA86EEE81DB6AC6A317BC2957AF00FC1278F513D003CC635707646FD6C723.
- UAT Windows del codigo integrado compilada y abierta con almacenamiento
  aislado existente. Prueba GUI: digitar 3 aplica 250/unidad y total 750;
  digitar 15 aplica 100/unidad y total 1500, sin pulsar mas/menos.
  Navegacion reciente conservada; no se cobra otra venta desde la GUI.
- PWA compilada localmente: version.json 1.0.6/142; carga visual de landing
  y entrega Brotli comprobadas en http://127.0.0.1:4182.
- Runtime API empaquetado arranca contra UAT local, health 200 y ruta
  price-lists sin autenticar 401.
- Paquete Docker transferido por partes y recompuesto/verificado en servidor:
  244455270 bytes, SHA256
  385E3D7A32C86DE1711945B1CE5CAF6BF61CDB30B82514D30D23479BF16BFE06.
- API: fullpos/daleventapos-backend:mayoreo-142-dd8d2729,
  config digest c05827ead2925b676d1d5e43142a7298ec28efd2c4b431d3405a0e2700106beb.
- PWA: fullpos/daleventapos-pwa:mayoreo-142,
  config digest 36ae4780e0e2d1cb0283c9ca57e8529cb0ffbf9f4b6dbaa6d594059f0ce92335.
  Ambos digests coinciden con manifest.json del archivo local exportado.
- Receta temporal de empaquetado web: C:/src/fullpos-pwa142-context/Dockerfile,
  SHA256 979CB1CA2241DE0A8B9A023A498A7E2D2CCF66CAF67EC2A33F7AA7A4E1FAE40E.
  Preparacion/cache-busting/Brotli: prepare-web.cjs, SHA256
  013FEA43C224E02614B8307B339AA8A480E0E4EBDA34C08C7F12BC0CA67A320C.
- La revision automatica bloqueo la eliminacion de build/windows. Se conservo
  esa carpeta y se compilo Windows produccion desde el nuevo worktree limpio.
- Instalador sin firma y migracion productiva: autorizaciones especificas
  solicitadas al propietario antes de publicar/aplicar.
