# Activación de emisión DOSA — preparación de UAT

Documento operativo. **Nada de esto se ha ejecutado en producción.** Las banderas
siguen apagadas y el transporte real sigue inaccesible por defecto.

## 1. Variables por ambiente

### Núcleo (ya existentes)

| Variable | UAT | Producción | Nota |
| --- | --- | --- | --- |
| `DOSA_EMISSION_ENABLED` | `true` solo durante la prueba | `false` hasta autorización | Sin ella la compuerta rechaza antes de la red |
| `DOSA_PRODUCTION_EMISSION_ENABLED` | `false` | `false` hasta autorización | Requisito extra para ambiente `PRODUCTION` |
| `DOSA_EMISSION_ENVIRONMENT` | `TEST` | `PRODUCTION` | Decide qué credencial de la empresa se usa |
| `DOSA_BASE_URL` | `https://dosasystem.com` | igual | HTTPS obligatorio fuera de UAT local |
| `DOSA_CREDENTIALS_MASTER_KEY` | clave de UAT | clave de producción | 32 bytes en base64; **nunca** la misma que UAT |
| `DOSA_EMISSION_TIMEOUT_MS` | `15000` | `15000` | Hay abort explícito; un timeout deja resultado desconocido, no reintento |

### Nuevas

| Variable | Valores | Efecto |
| --- | --- | --- |
| `DOSA_EMISSION_TRANSPORT` | `FETCH` (defecto) \| `FAKE` | `FAKE` **solo** se acepta con `APP_ENV=uat` o `UAT_LOCAL_ONLY=true`; fuera de ahí la app **no arranca** |

## 2. Validación al iniciar

`validateDosaEmissionStartup()` se ejecuta al construir el proveedor de
transporte. Impide el arranque (con mensaje `DOSA_EMISSION_CONFIG_INVALID`) si:

- se pide el transporte `FAKE` fuera de una UAT local;
- `DOSA_EMISSION_ENABLED=true` y no hay `DOSA_BASE_URL`;
- la URL no es HTTPS ni un `http://127.0.0.1` de UAT local;
- el ambiente declarado no es `TEST` ni `PRODUCTION`.

**No** impide arrancar (solo advierte) cuando PRODUCCIÓN está configurada pero
sin autorizar, o cuando falta la clave global de un ambiente: son estados
legítimos y la compuerta rechaza cada emisión con su motivo.

## 3. Migraciones pendientes

Ninguna nueva en esta entrega. El estado esperado es el ya validado:

```powershell
cd apps/api
npx prisma migrate status   # Database schema is up to date
npx prisma validate         # schema valid
```

## 4. Respaldo y restauración (antes de tocar un ambiente compartido)

```powershell
pg_dump -Fc -f respaldo_$(Get-Date -f yyyyMMdd_HHmm).dump $env:DATABASE_URL
pg_restore -l respaldo_*.dump | Select-Object -First 20     # verificar legible
```

Restauración probada **en una base desechable**, comparando recuentos de:
`ecf_electronic_documents`, `ecf_dosa_company_credentials`,
`ecf_dosa_webhook_events`, `ecf_portal_enrollments`.

## 5. Rollback

1. `docker service rollback daleventapos_backend` (Swarm guarda la versión previa).
2. Si el rollback de imagen no basta, `git revert` de los commits de la rama.
3. **No** hay migración que deshacer en esta entrega.
4. Las banderas pueden apagarse sin desplegar: `DOSA_EMISSION_ENABLED=false`
   vuelve a dejar la emisión inaccesible en el siguiente arranque.

## 6. Prueba de conectividad al proveedor (cuando se autorice TEST)

No existe una ruta que "solo pruebe conexión", y no se añade: una prueba de red
es una llamada. El procedimiento es:

1. Autorizar explícitamente una ventana de TEST.
2. Elegir **una** empresa con credencial TEST `ACTIVE` y certificación
   `AUTHORIZED_SANDBOX`.
3. Preparar un comprobante de importe mínimo y despachar por
   `POST /ecf/documents/:id/dispatch-dosa`.
4. Verificar en la respuesta: `ok`, `environment: TEST`, `httpStatus`, y el
   `encf` devuelto igual al enviado.
5. **No** repetir el envío: el segundo intento es conflicto por diseño.

## 7. Verificación de credenciales por ambiente (sin revelar secretos)

```sql
SELECT company_id, rnc, environment, status,
       left(fingerprint, 12) AS fingerprint_prefix,
       updated_at
  FROM ecf_dosa_company_credentials
 ORDER BY company_id, environment;
```

Comprobaciones:

- Cada empresa que va a emitir tiene la fila del ambiente que corresponde.
- Ninguna empresa tiene `status='ACTIVE'` en un ambiente para el que no fue
  autorizada.
- Dos empresas **no** comparten `fingerprint`: si lo hicieran, tendrían la misma
  clave.

Nunca se imprime la clave ni se descifra la bóveda para esta verificación.

## 8. Reclasificación de FULLTECH en modo dry-run

Solo lectura, sin `--apply`:

```powershell
cd apps/api
npm run dosa:credentials:reclassify        # dry-run por defecto
```

Se revisa la propuesta y **no** se aplica sin autorización explícita.

## 9. Monitoreo

| Qué | Dónde |
| --- | --- |
| Incidencias | `GET /ecf/platform/dosa/incidents?status=OPEN` (requiere personal + concesión) |
| Aviso de severidad alta | log estructurado `ECF_DOSA_INCIDENT` |
| Eventos de webhook | `ecf_dosa_webhook_events` por empresa |
| Intentos de emisión | `ecf_electronic_document_attempts` (`SEND_TO_PROVIDER`) |
| Documentos en revisión | `GET /ecf/documents?status=HUMAN_REVIEW_REQUIRED` |

## 10. Activación gradual por empresa

Por cada empresa, en este orden y parando si algo falla:

- [ ] RNC registrado y configuración fiscal completa.
- [ ] Postulación DOSA iniciada y credenciales recibidas (webhook verificado).
- [ ] Credencial del ambiente en `ACTIVE`.
- [ ] `certification_status` en `AUTHORIZED_SANDBOX` (TEST) o `PRODUCTION_READY`.
- [ ] `GET /ecf/capabilities` → `emissionPathAvailable: true`.
- [ ] Una venta de importe mínimo preparada y despachada.
- [ ] Estado del documento revisado; si quedó en revisión humana, se cierra con
      evidencia antes de continuar.
- [ ] Segunda empresa: repetir sin tocar configuración del servidor.

## 11. Lo que sigue bloqueado (no es código)

- Confirmación de P1 (unidad de `t`) y P2 (encoding del secreto) para habilitar la
  verificación de webhooks reales.
- Confirmación de P6 (`api_secret` por empresa o por ambiente).
- Autorización de la primera emisión TEST real contra DOSA.
