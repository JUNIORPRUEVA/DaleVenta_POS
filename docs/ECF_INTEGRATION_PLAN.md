# Plan de integración de la rama e-CF — NO EJECUTADO

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-18**.

> **Nada de este plan se ha ejecutado.** No hay `commit`, `push`, `merge`, `deploy`
> ni migración. Es el procedimiento propuesto para cuando exista autorización.

## 1. Principio rector

**Desplegar el backend NO obliga a nadie a actualizar la aplicación.** Son
operaciones distintas y con compuertas distintas:

| Operación | Riesgo | Compuerta |
| --- | --- | --- |
| Backend compatible | Medio | Compatibilidad legacy verificada |
| Publicar instalador Windows | Medio | Build firmado + manifiesto |
| Actualización automática | Alto | Firma + rollout escalonado |
| Activar e-CF por empresa | Alto | Habilitación DGII por empresa |
| Emisión fiscal real | Crítico | Autorización + contrato + esquema |

## 2. Requisitos previos (bloqueantes)

| # | Requisito | Estado |
| --- | --- | --- |
| P1 | `FINANCIAL_LEGACY_COMPAT` confirmado en el entorno desplegado | **NO VERIFICADO** |
| P2 | Suite completa de backend en verde | Última medición: 65 suites / 747 (2026-10-16) |
| P3 | Suite completa de Flutter en verde | Última medición: 1414 + 15 nuevas de UAT |
| P4 | Plan de commits revisado y aprobado | `ECF_COMMIT_PLAN.md` |
| P5 | Respaldo verificado antes de migrar | Pendiente |
| P6 | Ventana de mantenimiento acordada | Pendiente |

## 3. Matriz de compatibilidad exigible

Cada combinación debe probarse **antes** de integrar:

| Backend | Cliente | Qué debe ocurrir |
| --- | --- | --- |
| Actual | Windows < 1.0.6+130 | Vende (depende de `FINANCIAL_LEGACY_COMPAT`) |
| Candidato | Windows < 1.0.6+130 | Vende — cubierto por 10 pruebas |
| Actual | Windows ≥ 1.0.6+130 | Vende |
| Candidato | Windows ≥ 1.0.6+130 | Vende — cubierto |
| Candidato | Web comercial | Vende; sin cambios de contrato |
| Candidato | Android / iOS | Venden; contratos sin cambios |

**No se asume compatibilidad: cada fila requiere ejecución.**

## 4. Procedimiento propuesto

1. Congelar cambios y revisar el diff completo (`git diff --check`).
2. Ejecutar P2 y P3 completos sobre el candidato.
3. Ensayar `prisma migrate deploy` sobre una **copia desechable** con volumen
   realista (mide bloqueos de los `CREATE INDEX`).
4. Verificar `FINANCIAL_LEGACY_COMPAT` (solo lectura) en el entorno destino.
5. Desplegar backend con **e-CF desactivado por defecto** en todas las empresas.
6. Validar en producción: venta normal, venta fiscal tradicional, caja, cierre.
7. Publicar instalador Windows **solo** si P5 está aprobado; el actualizador
   queda opcional hasta autorización explícita.
8. Activar e-CF por empresa únicamente con habilitación DGII verificada.

## 5. Rollback por componente

| Componente | Rollback |
| --- | --- |
| Backend | Volver a la imagen anterior; las migraciones son aditivas y reversibles con `DROP COLUMN` (sin pérdida de datos del POS) |
| Windows | Reinstalar la versión anterior desde el instalador previo; el actualizador no degrada solo |
| e-CF por empresa | Desactivar el interruptor de la empresa (no borra datos) |
| Secuencia e-NCF | **No reversible**: un número asignado no se reutiliza |

## 6. Verificación de `FINANCIAL_LEGACY_COMPAT` (solicitud concreta)

Cuando exista autorización de lectura, pedir al operador del entorno:

1. El valor efectivo de `FINANCIAL_LEGACY_COMPAT` **en el proceso del backend**
   (no en un `.env` ni en una plantilla).
2. La versión/imagen desplegada del backend.
3. Si existe algún negocio activo con app anterior a `1.0.6+130`.

Formato de respuesta esperado: tres líneas, sin credenciales. Mientras no se
reciba: `FINANCIAL_LEGACY_COMPAT=UNVERIFIED` y **NO-GO de despliegue**.

## 7. Qué queda fuera de esta integración

- Emisión real (`PRODUCTION_EMISSION_IMPLEMENTED = false`).
- Certificación DGII.
- Cualquier llamada a Alanube.
- Activación de e-CF en empresas existentes sin habilitación.
