# Plantilla Meta `guardian_incident_alert` — especificación exacta

Estado: **NO aprobada**. Este documento describe lo que el backend **envía**;
la aprobación sólo puede confirmarla Meta. No se declara aprobada sin evidencia.

Fuente: `apps/api/src/guardian/guardian.alert.service.ts` →
`buildGuardianAlertTemplateParams()` y `guardian.alert.channels.ts` →
`WhatsAppCloudChannel` (componente `body`).

---

## 1. Cómo se envía

```json
{
  "messaging_product": "whatsapp",
  "to": "<E.164 sin +>",
  "type": "template",
  "template": {
    "name": "guardian_incident_alert",
    "language": { "code": "es" },
    "components": [{ "type": "body", "parameters": [
      { "type": "text", "text": "..." },  // 8 en total, en este orden
    ]}]
  }
}
```

- Nombre por defecto: `guardian_incident_alert` (`GUARDIAN_WA_TEMPLATE_NAME`).
- Idioma por defecto: `es` (`GUARDIAN_WA_TEMPLATE_LANG`).
- **Sólo componente `body`**. No se envían cabecera, botones ni parámetros de URL.
- Cada parámetro se recorta a 400 caracteres.
- Categoría declarada en el perfil: `UTILITY`.

## 2. Los 8 parámetros, en orden

| # | Origen | Valores posibles / formato | Ejemplo |
| --- | --- | --- | --- |
| `{{1}}` | `severityLabel` | Literal: `CRÍTICO` · `ALTO` · `MEDIO` · `BAJO` | `CRÍTICO` |
| `{{2}}` | `companyName` | Nombre de la empresa del incidente | `Antonio Celulares` |
| `{{3}}` | módulo / operación | `"<module> / <operation>"` | `cash / closeSession` |
| `{{4}}` | `occurredAt` | `toLocaleString('es-DO', {hour,minute,hour12,day,month})` | `03:14 a. m., 25/10` |
| `{{5}}` | `problemText(module, operation)` | Texto fijo por módulo/operación (ver §3) | `No se pudo cerrar el turno de caja.` |
| `{{6}}` | resumen del diagnóstico IA | `diagnosis.summary` o `Información pendiente de confirmar.` | `Error de conexión al cierre` |
| `{{7}}` | impacto | `diagnosis.impact` o `incident.impactSummary` o `Pendiente de determinar.` | `Posible impacto en caja` |
| `{{8}}` | identificador corto | `INC-` + 6 primeros caracteres hex del id (sin guiones, mayúsculas) | `INC-3F9A1C` |

## 3. Textos de `problemText` (parámetro {{5}})

Definidos en el servicio de alertas; son frases fijas por módulo/operación, no
texto libre. Al crear la plantilla en Meta, el cuerpo debe dejar claro que
`{{5}}` es una frase corta (una línea), no un párrafo.

## 4. Cuerpo sugerido para Meta (aparecerá en el mensaje)

```text
🚨 Guardian AI · {{1}}

Empresa: {{2}}
Módulo: {{3}}
Hora: {{4}}

Qué ocurrió: {{5}}
Diagnóstico: {{6}}
Impacto: {{7}}

Expediente: {{8}}
No se modificó información del cliente.
```

Reglas de Meta a respetar al crearla:

- Categoría **UTILITY** (no MARKETING).
- Idioma `es` (o el que se configure en `GUARDIAN_WA_TEMPLATE_LANG`; debe coincidir exactamente con un idioma aprobado).
- Los `{{n}}` deben ser consecutivos y en este orden; si Meta los renumera, hay que ajustar el envío.
- Variables no pueden abrir ni cerrar el cuerpo.
- Si se añade una cabecera o botón, el envío actual **no los rellenará**.

## 4 bis. Anexo: payload listo para registrar en Meta

Contenido para `POST /{waba-id}/message_templates` (ejecutado por el propietario
desde el panel de Meta o con su propio cliente). Nada de esto se ha enviado.

```json
{
  "name": "guardian_incident_alert",
  "language": "es",
  "category": "UTILITY",
  "parameter_format": "POSITIONAL",
  "components": [
    {
      "type": "BODY",
      "text": "🚨 Guardian AI · {{1}}\n\nEmpresa: {{2}}\nMódulo: {{3}}\nHora: {{4}}\n\nQué ocurrió: {{5}}\nDiagnóstico: {{6}}\nImpacto: {{7}}\n\nExpediente: {{8}}\nNo se modificó información del cliente.",
      "example": {
        "body_text": [[
          "CRÍTICO",
          "Antonio Celulares",
          "cash / closeSession",
          "03:14 a. m., 25/10",
          "No se pudo cerrar el turno de caja.",
          "Conexión interrumpida durante el cierre",
          "Posible impacto en caja o turnos",
          "INC-3F9A1C"
        ]]
      }
    }
  ]
}
```

### Mensaje resultante (ejemplo con datos ficticios)

```text
🚨 Guardian AI · CRÍTICO

Empresa: Antonio Celulares
Módulo: cash / closeSession
Hora: 03:14 a. m., 25/10

Qué ocurrió: No se pudo cerrar el turno de caja.
Diagnóstico: Conexión interrumpida durante el cierre
Impacto: Posible impacto en caja o turnos

Expediente: INC-3F9A1C
No se modificó información del cliente.
```

> Los valores del ejemplo son ficticios y solo sirven para que Meta valide la
> plantilla. No contienen datos de clientes ni credenciales.

## 5. Plantilla del watchdog: declarada pero **sin uso**

`guardian.whatsapp.config.ts` declara `guardian_watchdog_alert` con 4 parámetros
(`GUARDIAN_WA_WATCHDOG_TEMPLATE_NAME`), pero **ningún emisor la utiliza**:
el watchdog envía JSON a `GUARDIAN_WATCHDOG_WEBHOOK_URL` con `Authorization:
Bearer <GUARDIAN_WATCHDOG_WEBHOOK_TOKEN>`.

Consecuencia: **no es necesario crear esa segunda plantilla** para el piloto.
Es una previsión de diseño, no un requisito de la activación.

## 6. Estados de entrega que el webhook procesa

`GET|POST /guardian/webhooks/whatsapp` (backend de Fullpos, sin prefijo global).

| Estado Meta | Estado interno | Notas |
| --- | --- | --- |
| `queued`/`accepted` (equivalente interno) | `QUEUED` → `ACCEPTED` | `ACCEPTED` sólo si Meta devuelve `messages[0].id` |
| `sent` | `SENT` | |
| `delivered` | `DELIVERED` | |
| `read` | `READ` | |
| `failed` | `FAILED_PERMANENT` | guarda `errors[0].message/title` |

El orden es monotónico: un `read` que llega antes que `delivered` no hace
retroceder el estado. Un webhook de otra WABA o de otro `phone_number_id` se
descarta (`ignored`).

## 7. Checklist de aprobación (a completar con evidencia de Meta)

- [ ] Plantilla creada en la WABA de APPYRA (no la de Phytoemagry/Altomamita).
- [ ] Categoría UTILITY e idioma que coincida con `GUARDIAN_WA_TEMPLATE_LANG`.
- [ ] 8 parámetros `body` en el orden de §2.
- [ ] Estado en Meta: **APPROVED** (capturar evidencia: nombre, idioma, fecha).
- [ ] `GUARDIAN_WA_TEMPLATE_NAME` y `GUARDIAN_WA_TEMPLATE_LANG` con esos valores exactos.
- [ ] Destinatarios de prueba añadidos en `GUARDIAN_ALERT_RECIPIENTS`.
- [ ] Webhook verificado con el `hub.verify_token` real.
