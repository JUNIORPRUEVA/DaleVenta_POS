# Cierre del flujo comercial E31, devolución y E34

## Alcance y evidencia

HECHO: revisión sobre production-main/38142fce (PR43 integrado), con una rama
aislada agent/ecf-commercial-closeout-20261114. La aplicación desplegada conserva
API4e6fb33c y PWA d56a9c97. Esta continuación cambia pruebas y documentación;
no cambia el código ejecutable, esquema, dependencias ni imágenes de la aplicación.

La prueba HTTP existente cubría venta/emisión E31 y preparación manual E34.
Las devoluciones financieras tenían pruebas PostgreSQL separadas. Se agregaron
tres recorridos HTTP completos por las rutas que consume el software:

1. Crear venta E31 y su borrador fiscal atómico, despachar al proveedor local,
   devolver desde POST /sales/:id/return, despachar la E34 y leer su impresión.
2. Mismo recorrido con respuesta del proveedor perdida: recuperación idéntica,
   una sola devolución económica y un solo número E34.
3. Falta de rango E34: la devolución económica queda identificada como pendiente
   fiscal; registrar el rango sintético y recuperar solo la nota no repite dinero
   ni movimientos de inventario.

Cada recorrido comprueba efectivo neto0, ITBIS devuelto18, stock39->40 una vez,
una reserva APPLIED118 y una asignación E34. Repetir la devolución, su recuperación
fiscal o el despacho no duplica resultados. Otra empresa obtiene404 y no cambia
el estado financiero. La impresión contiene referencia original, impuestos y QR.

Todos estos resultados usan empresas ficticias, una base PostgreSQL nueva y un
servidor HTTP en127.0.0.1. No equivalen a nuevas aceptaciones reales de DGII.
Las aceptaciones TEST reales E310000000003/E340000000002 y sus PDF descargados
ya se verificaron en la fase anterior; no se reenviaron.

## Validación local

| Comando ejecutado | Resultado |
| --- | --- |
| npm ci --no-audit --no-fund | PASS |
| npm run api:build | PASS |
| npx prisma migrate deploy; npx prisma validate, únicamente base local nueva |83 migraciones y validación PASS |
| npm --workspace apps/api test |240 suites/2882 pruebas PASS;52 suites/547 pruebas opt-in omitidas |
| test con ECF_POSTGRES_UAT=true, cinco suites PostgreSQL de checkout, devolución, readiness, secuencias y separación de ambientes |5 suites/48 pruebas PASS |
| test:e2e con las tres suites HTTP de CI |3 suites/43 pruebas PASS; repetición final tras ajustar fixtures también PASS |
| npx tsc --noEmit -p [privado]/tsconfig.changed-test.json | PASS tras corregir dos fixtures existentes |

El chequeo estricto adicional del archivo de pruebas detectó dos fixtures de
production-main que omitían encf, requerido por su tipo. Se completan con cadena
vacía explícita: se conserva la asignación por el servidor. No se modifica el
contrato productivo ni se debilita el chequeo. Las pruebas de rango ausente
provocan intencionalmente ECF_SEQUENCE_EXHAUSTED y verifican la recuperación.
La advertencia existente de ts-jest/isolatedModules y el uso de --forceExit de
estas suites no se modifican en este cierre.

## FULLTECH: valores existentes confirmados por el propietario

El propietario aclaró que él registró los datos y pidió usar los valores de la
base de FULLTECH. Se conservan; no se sustituyen por el rango genérico del correo.

| Tipo | Autorización registrada | Siguiente operativo | Vencimiento autorización | Vencimiento operativo |
| --- | --- | --- | --- | --- |
| E31 |1–150 |3 |31/12/2027 |null |
| E32 |1–1000 |3 |null |null |
| E34 |1–50 |2 |null |null |

La única discrepancia interna de vigencia conocida es E31: su autorización ya
contiene2027-12-31T23:59:59.999Z, pero su rango operativo no. No se inventa una
fecha para E32/E34; se conserva su declaración existente. No se reinician ni
rebobinan los contadores, incluidos los conservados del historial de pruebas.

Consulta live solo lectura, filtrada por companyId FULLTECH:

- Certificación PRODUCTION_READY; configuración actual SANDBOX/productionEnabled=false.
- Credenciales propias ACTIVE por TEST y PRODUCTION, cada una con su clave del
  ambiente, sin exportar/decryptar material secreto.
- Cero resultados TEST sin resolver; cuatro ensayos antiguos revisados conservan
  sus estados. Las dos aceptaciones nuevas permanecen separadas de esos ensayos.
- Los dos resúmenes persistidos de webhook HMAC/COMPLETE no contienen numeración.
  Esto no prueba que el cuerpo original histórico no incluyera otros datos.
- DOSA_PRODUCTION_EMISSION_ENABLED=false y DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED=false;
  RUN_MIGRATIONS=false y RUN_SEED=false.

## Propuesta concreta para la activación posterior

RECOMENDACIÓN: realizar el cambio en una ventana controlada, sin ventas fiscales
durante la configuración. Esta sección describe operaciones PENDIENTES; no las
autoriza ni afirma que se ejecutaron.

1. Guardar checkpoint de configuración/autorizaciones/rangos y sus contadores.
2. Bajo autorización explícita del propietario para preparación productiva,
   preparar solo las dos banderas de producción/resultado confirmado del backend.
   El propietario conserva Implementar. Mantener migraciones/seed apagados,
   las imágenes aprobadas y todas las credenciales/configuración restantes.
3. Tras el despliegue manual y salud verificada, activar solamente FULLTECH por
   POST /ecf/production/enable con su expectedCompanyId. Revalidar credencial propia,
   certificación y ausencia de resultados inciertos. No emitir una factura.
4. En el flujo existente de numeración PRODUCTION, renovar E31 desde3 hasta150,
   con validUntil2027-12-31T23:59:59.999Z, que coincide con su autorización ya
   declarada. Conservar la fila anterior como historial y dejar nextNumber=3.
   No ampliar autorización ni modificar E32/E34. Verificar ausencia de ventas
   concurrentes; si el contador avanzó, detener y recalcular desde el valor actual.
5. Leer de nuevo los contadores, readiness y comprobantes TEST existentes;
   comprobar las ventas normales y su ITBIS. No convertir una venta normal,
   reenviar un aceptado ni crear una factura real como smoke test.

Propuesta de cuerpo para la renovación E31, sin ejecutar:

```json
{
  "documentType": "E31",
  "expectedEnvironment": "PRODUCTION",
  "startNumber": 3,
  "endNumber": 150,
  "validUntil": "2027-12-31T23:59:59.999Z"
}
```

La renovación es la operación existente EcfSequenceService.renew: desactiva el
rango anterior y crea el siguiente sin cruzar el frente consumido. La declaración
de autorización original permanece1–150. No se requiere una migración de esquema.
La activación de otras empresas sigue siendo independiente y exige sus propias
credenciales/certificación/rangos y decisión de su administrador.

## Estado

Validación comercial local: PASS. Para merge se exigen controles GitHub verdes
en el HEAD final del nuevo PR; su resultado se reporta con el enlace al run.
Producción fiscal: NO-GO hasta autorización de la operación productiva descrita
y verificación final de sus resultados. No se ha desplegado, reiniciado,
activado producción, alterado numeración ni registrado negocio real en esta fase.
La fase de diseño todavía no se inició.

Herramientas y recibo privado, sin secretos:
C:/Users/pc/.codex/backups/fullpos-ecf-commercial-closeout-20261114/.
