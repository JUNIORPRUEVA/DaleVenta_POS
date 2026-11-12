# Design research — investigaciones visuales de FullPOS Cloud

Carpeta de **evidencia y propuestas** producida por la skill
[`auditor-visual-pos`](../../.github/skills/auditor-visual-pos/SKILL.md).

Esta carpeta **no es** documentación del sistema de diseño ni especificación funcional.
La fuente de verdad visual sigue siendo [`docs/DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md).

## Qué se guarda aquí

- Investigaciones de interfaces públicas o autorizadas, medidas con Playwright MCP.
- Comparaciones entre un patrón observado y su equivalente en FullPOS Cloud.
- Propuestas **originales** de rediseño en Flutter (sin implementar).
- Capturas y mediciones que respaldan cada afirmación.

## Qué no se guarda aquí

- Código, CSS, logos, iconos, ilustraciones ni tipografías licenciadas de terceros.
- Credenciales, tokens, cookies o valores de `.env`.
- Capturas de zonas privadas de terceros o de producción con datos de clientes.
- Cambios de comportamiento de facturación, inventario, caja, autenticación o base de datos.

## Convención de nombre

```
docs/design-research/YYYY-MM-DD-<tema>-<fuente>.md
```

Ejemplo: `docs/design-research/2026-11-08-tablas-productos-referencia-x.md`.

## Estructura obligatoria del informe

La plantilla completa está en la skill. Secciones mínimas:

1. Objetivo y alcance
2. Fuentes y fecha de observación
3. Evidencia (capturas, snapshot, consola)
4. Medidas verificadas (`HECHO`) — layout, tipografía, espaciado, color y contraste,
   sombras/radios, iconografía, animaciones/motion, navegación y responsive
5. Observaciones de UX/UI
6. Comparación con el sistema de diseño FullPOS
7. Propuesta original en Flutter (`RECOMENDACIÓN`)
8. Limitaciones
9. Archivos Flutter relevantes
10. Próximos pasos (requieren autorización explícita)

## Etiquetas

| Etiqueta | Significado |
| --- | --- |
| `HECHO` | Extraído del navegador, archivo o comando ejecutado en el turno. |
| `HIPÓTESIS` | Interpretación plausible, no verificada. |
| `RECOMENDACIÓN` | Propuesta de diseño o implementación. |

## Informes existentes

| Fecha | Informe | Fuente | Estado |
| --- | --- | --- | --- |
| — | — | — | — |

## Regla de cierre

Un informe aquí **no autoriza** a modificar `apps/fulltech_app`. La implementación es un turno
distinto, con autorización explícita y el flujo normal del repositorio (`AGENTS.md`,
`docs/DESIGN_SYSTEM.md`, `flutter analyze`, `flutter test`).
