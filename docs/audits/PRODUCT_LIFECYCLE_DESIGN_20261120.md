# Diseño funcional y técnico del ciclo de vida

| Acción | Requisito | Resultado |
| --- | --- | --- |
| Eliminar | Activo, principal y cada almacén en cero, consistentes, sin referencias | Borrado físico y huella administrativa persistente |
| Archivar | Empresa y permiso correctos, sin referencias locales pendientes | Conserva ID, código, stock, documentos y Kardex |
| Restaurar | Archivado no anulado, código y cupo comprobados | Mismo ID, stock e historial |
| Anular alta | ADMIN, online, función habilitada, versión actual, única carga inicial intacta | Compensación, archivo y auditoría atómicos |

Los códigos de archivados y anulados permanecen reservados. Crear contra un
archivado genera conflicto con su ID: restauración explícita o cancelación.
Nunca se restaura silenciosamente ni se anulan altas en selección múltiple.

ADMIN significa el rol efectivo validado por el backend. El mapeo existente
convierte miembros MANAGER (incluido ASISTENTE heredado) a ADMIN; no se cambió
esa política global. Un VENDEDOR con edición puede consultar pero no anular;
un CAJERO sin permiso es rechazado. Restringir además por rol de membresía
necesitaría una decisión comercial explícita antes de activar la función.

## Contratos

- `GET /products/:id/lifecycle`: elegibilidad, versión, existencias, referencias y eventos.
- `POST /products/:id/annul`: UUID `operationId`, entero `expectedVersion`, motivo de 10–500 caracteres.
- `PATCH /products/:id/archive` y `/reactivate`: contratos existentes conservados.
- `GET /products?archivedOnly=true&page=1&limit=50&search=...`: filtro antes de paginar.
- `DELETE /products/:id`: un archivado devuelve conflicto, no éxito de borrado.

Las transiciones toman `FOR UPDATE`; las referencias nuevas, `FOR KEY SHARE`.
La referencia se confirma antes y bloquea la anulación, o espera y rechaza la
identidad retirada. Se repiten las comprobaciones decisivas en la transacción.
La compensación usa `InventoryMutationService`, `ADJUSTMENT_OUT` y origen
`PRODUCT_ANNULMENT`. No reescribe ni elimina el `INITIAL_STOCK` original. Mismo
comando: una compensación y un evento. Otra versión obliga a comprobar de nuevo.

`ProductLifecycleEvent` conserva actor, empresa, producto, acción, fecha e
identidad. No tiene FK al producto eliminado: su huella impide que un replay
offline de creación resucite la identidad. La poda de duplicados ya no borra.
Referencias protegidas: movimientos, transferencias, ventas, cotizaciones,
órdenes/recepciones de compras, reglas de precios y referencias de sitio. Las
garantías por nombre no son FK a Product; se conservan sin migrar ni borrar.

## Offline y compatibilidad

Anular no añade una cola offline. Cambiar estados exige comprobar las operaciones
locales de la misma empresa, incluidas las que requieren intervención. No se
eliminan ni reintentan ventas para completar una acción de catálogo. El servidor
no conoce una cola todavía desconectada en otro equipo: sus referencias antiguas
se rechazan al reconectar y deben conservarse para resolución.

Los triggers impiden restaurar o reponer una identidad anulada desde código
antiguo. Las ventas nuevas excluyen archivados; las devoluciones históricas
de archivados requieren enlace exacto a su ítem, venta original y empresa.
No se modifican reglas fiscales ni límites de licencia.

`product.changed` transmite únicamente IDs/acción a la sala de la empresa tras
confirmarse la mutación. Los clientes consultan datos autorizados; no circulan
costos por socket. La reconexión reconcilia catálogo y sus superposiciones
confirmadas para no ocultar restauraciones realizadas en otro dispositivo.

## Interfaz

Gestionar producto ofrece solo acciones elegibles y confirmación explícita.
Archivados tiene búsqueda/paginación y abre el mismo detalle. La selección
múltiple comprueba cada producto, resume aptos/omitidos y entrega resultados
individuales; una denegación no aborta productos independientes. No hay anulación
masiva. Controles azules rectangulares y contenido acotado. Se retiraron las
rutas y botones de purga debug de productos y documentos relacionados.
