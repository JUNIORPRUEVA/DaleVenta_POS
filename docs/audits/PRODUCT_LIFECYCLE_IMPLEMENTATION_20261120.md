# Ciclo de vida de productos — ejecución autorizada

## Cierre de experiencia del cliente — 21 de noviembre de 2026

El propietario aprobó el diseño de las 39 vistas tras el commit `c4bfd1d5`.
Se conserva el diseño aprobado. El cliente abre Gestionar producto, elige una
acción permitida y confirma; no debe conocer reglas internas ni pedir revisión
a otra persona para las acciones que su permiso permite.

| Necesidad | Recorrido y resultado |
| --- | --- |
| Retirar un producto que ya vendió | Gestionar → Archivar → confirmar. Conserva ventas, existencias e historial. |
| Eliminar uno sin uso ni existencias | Gestionar → Eliminar definitivamente → confirmar. El servidor vuelve a validar. |
| Volver a ofrecer un archivado | Archivados → buscar producto → Restaurar → confirmar. Conserva su identidad e historial. |
| Cambiar de opinión antes de confirmar | Cancelar. No se muestra éxito ni se cierra el detalle original. |
| Respuesta incierta o cambio simultáneo | Comprobar estado antes de volver a decidir; nunca asumir que falló y repetir a ciegas. |

Solo se muestran acciones que permite el estado consultado. Tener ventas oculta
el borrado definitivo y la anulación. La anulación del alta es excepcional,
requiere permiso, habilitación y motivo; no forma parte de retirar un producto
vendido. Sin conexión, estas transiciones esperan verificación; esto no bloquea
por sí mismo la pantalla de ventas ni elimina operaciones offline.

Validación adicional: las 85 pruebas de la galería pasaron, incluidas cuatro
comprobaciones del recorrido completo de eliminar, archivar, restaurar y cancelar.
Son pruebas de widgets con repositorio simulado; complementan las pruebas reales
de API/base de datos y plataformas registradas en el informe de cierre.
La aprobación visual no autoriza despliegue ni habilitación de la anulación.

## Fase 0: entorno y baseline

Trabajo aislado actual: `C:/t/fppl-7e92-20261120`, rama
`agent/product-lifecycle-private-20261120`, base `a4ebdf1e`. Se creó una copia
privada tras cambios externos en la anterior. API 4017 y PostgreSQL exclusivo
56562 (`fullpos_product_lifecycle_private`). Conserva los commits locales
de recuperación `d5986236` y acceso web `a4ebdf1e`.
La copia principal `DaleVentas POS` está en `6b3e38ed` con cambios ajenos;
no se utiliza para editar. Se conserva intacta la auditoría global de referencia.

Comparación productiva exclusivamente de lectura, sin consultar datos de clientes:
API desplegada `d35fc09eb7e9447baa79aa43bed12fb6581505a3`; PWA
`33625e3cc6666867d80e5c1fae8e001dca64526c`. El código compilado de productos
(servicio/controlador), mutación de inventario y cotizaciones coincide SHA-256
exactamente con nuestra base. La advertencia histórica de fuente atrasada queda
resuelta para esos módulos. Se conserva la comparación en
`.uat/product-lifecycle/artifact-comparison.json`. No se tocaron servicios remotos.

Baseline: 47 pruebas de productos aprobadas, dos suites. TypeScript compiló.
Dependencias privadas para esta copia: generar Prisma no alterará el cliente
de los laboratorios anteriores. Ninguna copia productiva de datos se usará en QA.

## Plan y políticas

1. Retirar la ruta de purga y su UI; no mantener una purga HTTP de clientes.
2. Borrado: bloquear producto antes de leer stock y referencias; stock principal
   y cada almacén en cero, consistencia comprobada y ninguna referencia protegida.
   No reutilizar la poda automática como una segunda vía destructiva.
3. Modelo aditivo: anulación conservada con actor, razón, fecha e identidad de
   operación; `archivedAt` también impide el uso por clientes antiguos. Códigos
   archivados y anulados inicialmente reservados. No modificar el índice único.
4. Anulación ADMIN, conectada y confirmada: solo carga inicial verificada,
   sin referencias ni stock modificado; compensación por el motor existente,
   archivo y auditoría en una transacción. Reintentos no repiten compensaciones.
5. Bloqueos/transacciones y validaciones en base de datos protegerán las carreras
   entre estados y nuevas referencias. Devoluciones históricas de archivados
   deben seguir funcionando; una anulación no puede reactivarse por clientes viejos.
6. Flutter: activos/archivados, búsqueda, restaurar mismo ID con cupo y códigos,
   conflicto explícito al crear contra archivado, masiva con previsualización,
   confirmación y resultados por producto. Nunca convertir a anulación masiva.
7. Cambios entre equipos y colas: preservar ventas pendientes y rechazos claros;
   no ampliar anulación a offline. Un servidor no puede leer operaciones todavía
   no transmitidas de un equipo desconectado: validar lo conocido, rechazar uso
   obsoleto sin perder la cola y documentar ese límite; no prometer conocimiento
   global de datos exclusivamente locales.
8. QA aislado: unitarias, PostgreSQL real, concurrencia, fallos/reintentos,
   Windows, Web y Android disponibles. iPhone: pendiente si no hay entorno.
9. Preparar respaldo/restauración, migraciones aditivas, compatibilidad y rollback.
   No desplegar ni modificar inventarios existentes. No liberar códigos sin prueba.

Las políticas del encargo actual autorizan estas fases y prevalecen sobre las
preguntas pendientes del informe histórico. Una contradicción comercial real o
una operación irreversible que afecte datos existentes requiere decisión previa.

**Estado: cierre técnico GO WITH ISSUES del alcance.** 121 pruebas backend,
214 Flutter, ejecuciones reales Windows/Android emulado, PostgreSQL, Web y
backup/restauración aprobados. Galería de 39 vistas en el puerto 4493 pendiente
de aprobación visual. iOS físico no disponible. No autoriza publicación.
Ver `PRODUCT_LIFECYCLE_CLOSING_20261120.md` para evidencia y límites.
