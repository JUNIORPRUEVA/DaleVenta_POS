# Tutorial de bienvenida e-CF

## Alcance

La bienvenida existente conserva su diseño y su acción de abrir el video.
`GET /ecf/dgii/preparation` mantiene sus permisos, su empresa autenticada y el
mismo contrato `videoUrl` / `simulation`. No se modifica emisión, certificación,
numeración, licencias, datos de clientes ni el esquema de datos.

La URL HTTPS explícita `ECF_HABILITATION_VIDEO_URL` conserva prioridad y
compatibilidad. Cuando no existe, `ECF_HABILITATION_VIDEO_OBJECT_KEY` permite
firmar el tutorial global de R2 al solicitar los metadatos. Solo acepta un MP4
directamente bajo `uploads/tutorials/ecf/`; no admite rutas de empresas,
certificados, documentos privados ni rutas proporcionadas por el cliente.
El enlace dura 24 horas y se firma de nuevo en cada consulta de metadatos.
Una página mantenida abierta más de ese plazo debe volver a abrirse para obtener
otro enlace. El reproductor actual abre el video mediante el navegador externo;
este cambio no incorpora reproducción incrustada dentro de Flutter.

Si falla la firma, la guía y la postulación siguen disponibles. No se registra
el error original del SDK ni una URL firmada. La privacidad y las credenciales
del bucket permanecen intactas.

## Archivo publicado con autorización del propietario

- Formato: MP4 H.264/AAC, 1920 × 1080, 30 fps, 251,4 segundos.
- Preparación web: remultiplexado sin recodificar, con `faststart`.
- Tamaño: 90 852 499 bytes.
- SHA-256: `d98ef6045946c4ac4392ef40766aaff6b2941f2dcc6cfca4fd739ebebd1af973`.
- Objeto: `uploads/tutorials/ecf/fullpos-bienvenida-d98ef6045946c4ac.mp4`.
- Guardado mediante creación condicional; no se reemplazaron objetos existentes.
- Se verificaron hash y tamaño en R2 y lectura real parcial: HTTP 206,
  `video/mp4`, 4096 bytes y cabecera MP4 válida, usando el R2Service desplegado.
- La ruta heredada `/uploads/...` devolvió 404 durante la prueba. No se configuró
  esa URL rota ni se alteró esa ruta como parte del trabajo.

EasyPanel tiene preparada únicamente `ECF_HABILITATION_VIDEO_OBJECT_KEY` con
la clave anterior. Se verificó que no cambiaron imagen, otras variables,
configuración, especificación del servicio ni contenedor en ejecución.
`RUN_MIGRATIONS` permanece desactivado. El respaldo previo de configuración está
protegido en `/etc/easypanel/tutorial-backups/backend-before-ecf-welcome-20261128.json`
dentro del almacenamiento persistente de EasyPanel; contiene datos sensibles y
no debe copiarse al repositorio ni mostrarse.

## Validación local

- `npm ci --workspace apps/api --include-workspace-root --no-audit --no-fund`:
  dependencias privadas de este worktree instaladas.
- `npm run api:build`: PASS (generación del cliente local y TypeScript).
- `npm --workspace apps/api test -- --runTestsByPath src/ecf/dgii/ecf-preparation-metadata.service.spec.ts src/ecf/dgii/ecf-preparation-metadata.policy.spec.ts src/storage/r2.private-bucket.spec.ts`:
  PASS, 3 suites, 19 pruebas.
- `git diff --check`: PASS.

El intento inicial con las dependencias prestadas del directorio antiguo falló
por un cliente Prisma desactualizado y paquetes ausentes. No se modificaron esas
dependencias: la instalación aislada y la regeneración local resolvieron la
compilación. Una ejecución de pruebas iniciada antes de terminar esa generación
falló por un enum ausente; la ejecución posterior completa indicada arriba pasó.
No se ejecutaron migraciones ni pruebas con datos productivos.

## Publicación pendiente

1. Autorizar y publicar el PR de estos archivos; mantener los cambios de impresión
   separados. Revisar CI y hacer merge manual.
2. Construir y verificar la imagen del backend desde el merge aprobado; preparar
   su digest conforme al procedimiento de publicación del proyecto.
3. El propietario implementa únicamente el backend en EasyPanel. La PWA y las
   apps existentes ya consumen `videoUrl`; no requieren una nueva compilación.
4. Verificar salud del backend y abrir la bienvenida con una cuenta autorizada
   de una empresa en postulación. Comprobar que aparece el botón del video y que
   reproduce el inicio, la unión y el tramo final. No iniciar una postulación real
   ni emitir documentos para esta comprobación.

Estado: video subido y preparación local validada. NO-GO para declarar la
función visible en producción hasta publicar el backend y completar esa última
comprobación. El propietario autorizó preparar commit, push y PR; el merge y el
despliegue no forman parte de esa autorización y siguen pendientes.
