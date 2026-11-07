# Aviso de incidencias DOSA — mecanismo y límites

Complementa a `docs/ecf/DOSA_INCIDENT_MONITORING.md` (qué se vigila y qué se
repara solo). Aquí: **cómo se entera una persona** de que hay una incidencia.

## 1. Qué existe hoy (HECHO, verificado)

Tres niveles, del más durable al más inmediato:

| Nivel | Dónde | Alcance |
| --- | --- | --- |
| Registro durable | tabla `ecf_dosa_incidents` | Toda incidencia, con severidad, `first_seen_at`, `last_seen_at`, intentos y estado |
| Bandeja de plataforma | `GET /ecf/platform/dosa/incidents` | Requiere `PlatformStaffGuard` **y** concesión de soporte de esa empresa |
| Registro operativo | log estructurado `ECF_DOSA_INCIDENT` | Solo severidad alta; alimenta la alerta del contenedor |

El registro operativo lo emite `LoggingDosaIncidentNotifier`
(`apps/api/src/ecf/provider/dosa/dosa-incident-notifier.ts`), invocado por
`DosaIncidentService` **solo al crear** una incidencia de severidad alta
(`HIGH`/`CRITICAL`). Las de severidad baja y media no interrumpen a nadie: se
acumulan en la bandeja. Avisar de todo es la forma más rápida de que nadie lea
nada.

## 2. Por qué NO se envía WhatsApp ni correo (HECHO)

- El outbox existente (`notifications`) es **solo WhatsApp**
  (`NotificationChannel = 'WHATSAPP'`) y su catálogo de plantillas está cerrado a
  casos de servicio técnico. No hay plantilla de incidencia autorizada por Meta.
- Enviar a un número cualquiera sin plantilla aprobada es una violación de la
  política del proveedor y, además, filtraría datos a un destino no acordado.
- El envío automático a DOSA está fuera de alcance por instrucción explícita del
  encargo.

Por tanto el aviso externo **es una dependencia pendiente**, no un olvido.

## 3. Cómo se enchufa un canal real (RECOMENDACIÓN)

El aviso está detrás de un **puerto**, no cableado en el servicio:

```ts
export interface DosaIncidentNotifier {
  notify(input: {
    companyId: string;
    incidentId: string;
    kind: string;
    severity: string;
    occurrences: number;
  }): Promise<void>;
}
export const ECF_DOSA_INCIDENT_NOTIFIER = Symbol("ECF_DOSA_INCIDENT_NOTIFIER");
```

Para cambiar de canal:

1. Implementar `DosaIncidentNotifier` (WhatsApp con plantilla aprobada, correo,
   webhook interno…).
2. Sustituir **una entrada** en `apps/api/src/ecf/ecf.module.ts`:

```ts
{
  provide: ECF_DOSA_INCIDENT_NOTIFIER,
  useFactory: () => new MiCanalDeAvisos(/* deps */),
},
```

3. Nada más. `DosaIncidentService` no cambia: si el canal falla, el error se
   registra y **no** rompe el barrido, porque la incidencia ya está persistida.

## 4. Garantías del contrato

- **Nunca lanza hacia arriba**: `safeNotify` captura y registra.
- **No propaga datos sensibles**: el aviso lleva empresa, identificador de
  incidencia, tipo, severidad y número de casos. Nunca credenciales, secretos,
  RNC ni cuerpos de evento (comprobado en `dosa-incident-notifier.spec.ts`).
- **Sin duplicados**: una incidencia se crea una sola vez por
  `(company_id, incident_key)`; el aviso ocurre en la creación, no en cada
  barrido (los barridos posteriores hacen `TOUCH`/`ESCALATE`).
- **Aislamiento**: el barrido recorre empresa por empresa y una excepción en una
  no afecta a las demás.

## 5. Qué sigue pendiente (HECHO)

- [ ] Plantilla de WhatsApp aprobada por Meta para avisos operativos, o canal de
      correo con destinatario acordado.
- [ ] Número/destinatario de guardia definido por negocio.
- [ ] Decidir si las severidades medias también deben avisar.

Mientras no exista canal, el procedimiento es el de la bandeja: revisar
`GET /ecf/platform/dosa/incidents?status=OPEN` en cada jornada. Es manual y así
se declara.
