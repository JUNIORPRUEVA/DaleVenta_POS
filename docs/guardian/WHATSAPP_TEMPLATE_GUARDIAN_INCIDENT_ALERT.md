# APPYRA Guardian AI — Plantilla administrativa `guardian_incident_alert`

Documento operativo para introducir la plantilla en **WhatsApp Manager** y para
revisarla cuando cambie el contrato del código.

- Nombre de la plantilla: `guardian_incident_alert`
- Categoría: **UTILITY** (aviso operativo solicitado por el negocio; no es marketing)
- Idioma: **es** (se admite `es_DO` si Meta lo ofrece para la cuenta)
- Remitente visible: **APPYRA**
- Número de parámetros de cuerpo: **8** (contrato vigilado por pruebas)

> Estado: **NO aprobada todavía.** Este documento prepara el texto para enviarlo a
> revisión. La aprobación la otorga Meta y no puede afirmarse desde el repositorio.

Fuente única de verdad en código:
`apps/api/src/guardian/guardian.whatsapp.config.ts`
(`GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY`, `GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS`).
La prueba `guardian.whatsapp.template.spec.ts` falla si el cuerpo o el orden de
los parámetros dejan de coincidir con este documento.

---

## 1. Texto exacto para WhatsApp Manager (cuerpo)

```text
APPYRA Guardian — alerta de incidente

Nivel: {{1}}
Empresa: {{2}}
Módulo: {{3}}
Fecha y hora: {{4}}

Problema: {{5}}
Diagnóstico: {{6}}
Impacto: {{7}}

Estado: incidente registrado, investigación en curso.
ID: {{8}}

Mensaje automático de monitoreo. No se modificó información de tus clientes.
```

Notas de cumplimiento:

- El **estado** del incidente va en texto fijo, no como parámetro: así el contrato
  de 8 variables no cambia y Meta no tiene que reaprobar la plantilla por un
  parámetro nuevo.
- **No** se incluye enlace al panel: el contrato actual no lo contempla y añadir
  una URL obligaría a redefinir la plantilla aprobada.
- No se piden datos fiscales (RNC/NCF/e-CF), datos de clientes finales ni
  información sensible. La evidencia que origina la alerta ya llega redactada.

## 2. Parámetros, en orden, con ejemplos sintéticos

| # | Variable | Contenido | Ejemplo sintético | Límite |
| - | --- | --- | --- | --- |
| 1 | `severity` | Nivel del incidente | `CRÍTICO` | 40 |
| 2 | `company` | Empresa afectada | `Comercial Ejemplo SRL` | 120 |
| 3 | `moduleOperation` | Módulo / operación | `caja / cierre de sesión` | 120 |
| 4 | `occurredAtLocal` | Día/mes y hora local (es-DO) | `26/10, 03:15 a. m.` | 60 |
| 5 | `problem` | Síntoma redactado | `El cierre de caja no completa el cálculo del efectivo esperado` | 400 |
| 6 | `diagnosis` | Hipótesis con evidencia o pendiente | `Información pendiente de confirmar.` | 400 |
| 7 | `impact` | Impacto operativo | `La sesión de caja queda abierta y no se puede facturar con turno cerrado` | 400 |
| 8 | `incidentShortId` | ID corto del incidente | `INC-4F2A9C` | 20 |

Los ocho valores los produce
`buildGuardianAlertTemplateParams()` en `guardian.alert.service.ts`; el envío los
coloca como `components[0].parameters` de tipo `text`.

## 3. Ejemplo completo del mensaje que recibirá el administrador

```text
APPYRA Guardian — alerta de incidente

Nivel: CRÍTICO
Empresa: Comercial Ejemplo SRL
Módulo: caja / cierre de sesión
Fecha y hora: 26/10, 03:15 a. m.

Problema: El cierre de caja no completa el cálculo del efectivo esperado
Diagnóstico: Información pendiente de confirmar.
Impacto: La sesión de caja queda abierta y no se puede facturar con turno cerrado

Estado: incidente registrado, investigación en curso.
ID: INC-4F2A9C

Mensaje automático de monitoreo. No se modificó información de tus clientes.
```

## 4. Pasos para crear la plantilla (WhatsApp Manager)

1. WhatsApp Manager → **Message templates** → *Create template*.
2. Categoría **Utility**, nombre `guardian_incident_alert`, idioma `es`.
3. Pegar el cuerpo de la sección 1 tal cual (los `{{n}}` son los marcadores).
4. Añadir los ejemplos de la sección 2 cuando el asistente los pida (son
   obligatorios para la revisión).
5. Enviar a revisión. Meta suele responder en minutos u horas; un rechazo indica
   categoría incorrecta o falta de ejemplos válidos.

## 5. Verificación después de la aprobación

- `GUARDIAN_WA_TEMPLATE_NAME=guardian_incident_alert`
- `GUARDIAN_WA_TEMPLATE_LANG=es`
- `npm --workspace apps/api run guardian:integraciones-check` debe mostrar
  `[OK] wa.template ... parámetros=8`.
- La primera prueba real (una sola alerta sintética) está descrita en
  `WHATSAPP_DEEPSEEK_ACCEPTANCE.md` §7.

## 6. Plantilla del watchdog (referencia, 4 parámetros)

`guardian_watchdog_alert` se usa cuando el propio Guardian no responde. Su
contrato vigente es de 4 parámetros y **no** se modifica en este trabajo:

1. Estado general (`CRÍTICO`, `RECUPERADO`).
2. Motivo corto (por ejemplo `base de datos inaccesible`).
3. Hora local del chequeo.
4. Identificador del watchdog (`WD-XXXXXX`).

Si se cambia el número de parámetros del watchdog, hay que actualizar
`guardian-watchdog.ts`, la plantilla aprobada y este documento a la vez.
