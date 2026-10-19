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

Estado inicial: integracion creada; validacion y despliegue pendientes.
