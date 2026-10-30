# F3 — Auditoría de despliegue y compatibilidad de clientes

> **Estado global: `F3 = PARCIALMENTE VERIFICADO`.**
> El **contrato de los clientes** quedó determinado con evidencia (HECHO). El
> **valor efectivo del interruptor en producción NO pudo verificarse** desde este
> entorno y se declara como bloqueo, no se asume.

## 1. El contrato real, por versión de cliente (HECHO)

El backend clasifica cada venta en
`apps/api/src/common/financial-legacy-compat.ts` con:

- campo nuevo **requerido**: `originCashSessionId`
- campo nuevo **opcional**: `originTerminalId`

| Regla | Resultado |
| --- | --- |
| Requerido presente | `SAFE_NEW_PATH` |
| Ningún campo nuevo presente | `LEGACY_COMPAT_PATH` |
| Solo el opcional presente | `INVALID_PARTIAL_REQUEST` (rechazo **siempre**) |

Evidencia del cliente, obtenida del historial real del repositorio:

| Versión de app | ¿Qué envía? | Clasificación |
| --- | --- | --- |
| **< 1.0.6+130** | `terminalId` y `deviceFingerprint`. **No** envía `originCashSessionId` ni `originTerminalId` | `LEGACY_COMPAT_PATH` |
| **>= 1.0.6+130** (incluye la actual **1.0.6+140**) | `originCashSessionId` **siempre no vacío** y además `originTerminalId` | `SAFE_NEW_PATH` |

- El cambio se introdujo en el commit **`1259993e`** («fix: harden offline
  financial operations and sync safety», 2026-10-05), que corresponde a
  `pubspec.yaml` **version: 1.0.6+130**.
- Ese commit **es ancestro de `production-main`** (`git merge-base --is-ancestor`
  → exit 0), es decir, la rama desplegada ya lo contiene.

### 1.1 Consecuencia importante (HECHO)

El cliente actual **no puede** producir una solicitud parcial: en
`ventas_repository.dart` hay una guarda explícita antes de construir la petición:

```dart
final originCashSessionId = await _resolveOriginCashSessionId();
if (originCashSessionId.isEmpty) {
  throw ApiException('Debes abrir caja antes de facturar.');
}
```

Envía el campo requerido o falla en el dispositivo; nunca envía solo el opcional.
Por tanto `INVALID_PARTIAL_REQUEST` **no es alcanzable desde ninguna versión
publicada**: es una defensa contra builds a medias, no contra clientes reales.

## 2. Comportamiento por escenario

| # | Escenario | Comportamiento verificado |
| --- | --- | --- |
| 1 | Cliente `>= +130`, turno abierto | Venta creada por la ruta nueva |
| 2 | Cliente `>= +130`, sin turno | Falla **en el dispositivo**: «Debes abrir caja antes de facturar» |
| 3 | Cliente `< +130`, interruptor **activo** | `LEGACY_COMPAT_PATH` → se resuelve el turno abierto y la venta se crea |
| 4 | Cliente `< +130`, interruptor **apagado** | **409 `LEGACY_MISSING_SESSION`**; no se crea la venta |
| 5 | Cliente `< +130`, sin turno abierto | 400 «Debes abrir caja antes de facturar» |
| 6 | Reintento con el mismo `clientRequestId` | Devuelve la venta existente (idempotente) |
| 7 | Venta encolada offline | Se aplica exactamente al turno que la originó; si ese turno ya no está abierto, se rechaza de forma controlada |
| 8 | Venta que no toca caja/inventario | Sin cambios respecto al comportamiento previo |

Escenarios 3–5 y 2 están cubiertos por pruebas ejecutadas:
`apps/api/src/ecf/pos/legacy-pos-compatibility-http.e2e-spec.ts` (6 pruebas
verdes) y las suites de caja.

## 3. Riesgo operativo real (HECHO)

**El único riesgo es de despliegue, no de código:**

- Los clientes `< 1.0.6+130` **dependen de que `FINANCIAL_LEGACY_COMPAT` esté
  activo** en el entorno desplegado. Si estuviera apagado, esos clientes **no
  podrían vender**.
- `FINANCIAL_LEGACY_COMPAT` **no aparece definido en ningún fichero del
  repositorio**: ni `.env`, ni scripts de despliegue, ni configuración de
  contenedor. Solo se lee en `financial-legacy-compat.ts` y se fija en pruebas.

Su valor efectivo vive **exclusivamente** en las variables de entorno de la
plataforma de despliegue.

## 4. Bloqueo declarado

```text
F3 (valor efectivo del interruptor) = NO VERIFICADO
Motivo: no existe acceso de solo lectura autorizado al entorno desplegado desde
        este entorno de trabajo.
Decisión: NO se usaron credenciales de escritura como sustituto.
```

Comprobar en el panel de despliegue (solo lectura, sin modificar nada):

1. Valor de `FINANCIAL_LEGACY_COMPAT` en el servicio del backend.
2. Versión del backend desplegada frente a esta rama.
3. Si existe algún negocio activo con app `< 1.0.6+130` sin actualizar.

## 5. Mitigación y recomendación

- **Recomendación (RECOMENDACIÓN):** confirmar que
  `FINANCIAL_LEGACY_COMPAT=true` en el entorno desplegado **antes** de promover
  cualquier cambio de esta rama. Es una verificación de lectura, sin riesgo.
- **No se cambió el interruptor** ni su valor por defecto.
- **No se modificó código** para F3: el comportamiento es correcto y está
  probado; el riesgo es de configuración.
- Autoupdate de Windows ya existe en el producto, lo que reduce la ventana de
  exposición de instalaciones antiguas (no la elimina para equipos apagados o
  sin conexión).

## 6. Qué NO se hizo

- No se consultó producción: sin credenciales de solo lectura autorizadas.
- No se probaron APKs antiguos en dispositivo real.
- No se desplegó, ni se reinició ningún servicio, ni se tocó ninguna variable de
  entorno.
