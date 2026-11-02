# Integración DOSA — materiales y configuración del entorno

Estado: **Fase 1 completada**. No hay ninguna conexión con DOSA, ninguna llamada de
red y ninguna emisión fiscal real. Este documento fija **dónde** debe vivir cada
material cuando se autoricen las fases siguientes.

Regla que no se negocia: **cero valores en el repositorio**. Ni en código, ni en
`docs`, ni en Flutter, ni en logs, ni en informes, ni en mensajes de error.

---

## 1. Inventario de materiales y destino

Los materiales los entregó DOSA. La auditoría del repositorio no los encontró
porque **no deben estar en el repositorio**: su sitio es el entorno local o el
gestor de secretos del servidor.

| # | Material | Destino correcto | Nunca |
| --- | --- | --- | --- |
| 1 | Script del asistente embebible | Fichero estático servido por el backend/estático del PWA, o URL en `DOSA_ASSISTANT_SCRIPT_URL` | Copiarlo dentro de `lib/` de Flutter |
| 2 | Clave publicable del componente | Config pública entregada por el backend al abrir el asistente, o `--dart-define` en build | Hardcodearla en `lib/` ni en un test |
| 3 | Ejemplo del evento «certificación finalizada» | `apps/api/src/ecf/provider/dosa/` como **fixture de pruebas** (datos sintéticos) | Reutilizarlo como respuesta real |
| 4 | Secreto del webhook | `apps/api/.secrets/dosa-webhook.secret` (ya ignorado) o gestor de secretos; se referencia con `DOSA_WEBHOOK_SECRET_REF` | Pegar el valor en `.env` versionado, en `docker-compose` o en logs |
| 5 | API Key de TEST | `apps/api/.env.dosa.test.local` (ignorado) o gestor de secretos; referencia con `DOSA_API_KEY_SECRET_REF` | Reutilizar la clave de producción en ensayos |
| 6 | RNC de prueba | `apps/api/.env.dosa.test.local` como `DOSA_TEST_RNC` | Usarlo como RNC de una empresa real |
| 7 | Rangos e-NCF de prueba y vencimiento | `apps/api/.env.dosa.test.local` (`DOSA_TEST_ENCF_FROM/TO/EXPIRES_ON`) y datos de la empresa de pruebas en la BD de pruebas | Asignarlos a una empresa de producción |
| 8 | Documentación pública de emisión y consultas | `V:\docs\` (documentación, sin credenciales) | — |

### Ficheros locales esperados (todos ignorados por Git)

```
apps/api/.env.dosa.test.local      <- material 5, 6, 7
apps/api/.secrets/dosa-webhook.secret <- material 4
```

`apps/api/.env.*.local` y `apps/api/.secrets/` están en `.gitignore`. Un
`.env.dosa.test.local` recién creado no aparecerá en `git status`; si aparece,
algo está mal y hay que revisarlo antes de continuar.

---

## 2. Variables de entorno (solo nombres y forma)

Se sigue la convención del proveedor actual (`ALANUBE_*`), en paralelo y sin
borrar nada:

| Variable | Forma esperada | Sensible |
| --- | --- | --- |
| `DOSA_ENV` | `test` \| `production` | No |
| `DOSA_API_BASE_URL` | URL https | No |
| `DOSA_ENABLE_REAL_CALLS` | `true` \| `false` (por defecto `false`) | No |
| `DOSA_HTTP_TRANSPORT_ENABLED` | `true` \| `false` (por defecto `false`) | No |
| `DOSA_API_KEY_SECRET_REF` | `env://…` \| `secret://…` \| `vault://…` | Sí (referencia, no valor) |
| `DOSA_WEBHOOK_SECRET_REF` | `env://…` \| `secret://…` \| `vault://…` | Sí (referencia, no valor) |
| `DOSA_ASSISTANT_SCRIPT_URL` | URL https | No |
| `DOSA_ASSISTANT_PUBLISHABLE_KEY` | Clave pública del componente | Pública por diseño, pero se entrega por configuración, no por código |
| `DOSA_TEST_RNC` | RNC de pruebas (distinto de FULLTECH SRL) | No |
| `DOSA_TEST_ENCF_FROM` / `_TO` / `_EXPIRES_ON` | Rango y vencimiento | No |

Reglas:

1. **Doble interruptor, como Alanube.** Una llamada real exige
   `DOSA_ENABLE_REAL_CALLS=true` **y** `DOSA_HTTP_TRANSPORT_ENABLED=true` **y**
   configuración completa. Cualquier pieza ausente deja el transporte apagado.
2. **Producción bloqueada por defecto**, igual que hoy: `DOSA_ENV=production`
   no habilita nada por sí solo.
3. **Referencias, no valores.** El servicio de secretos
   (`ecf-secret-resolver.service.ts`) ya resuelve `env://`, `secret://`,
   `vault://` y `uat://`; DOSA debe reutilizarlo, no inventar otro camino.
4. **La clave publicable no es un secreto**, pero tampoco es una constante de
   compilación: se sirve por configuración para poder rotarla.

---

## 3. Qué NO puede pasar

- La API Key de TEST nunca se registra en el paquete de Flutter.
- El secreto del webhook nunca aparece en una respuesta HTTP ni en un log; si
  un evento no valida la firma, la respuesta es un código de error, no un
  detalle del cálculo.
- Ningún ensayo usa credenciales de producción.
- Ninguna empresa real recibe e-NCF del rango de pruebas.

---

## 4. Pendiente de DOSA (contratos, no credenciales)

Falta confirmación por escrito de:

1. **Firma del webhook**: cabecera exacta, algoritmo, inclusión de marca de
   tiempo, ventana anti-replay y formato del cuerpo firmado (bytes exactos).
2. **Vinculación Partner**: cómo se asocia el RNC del cliente a *nuestra*
   empresa y cómo se evita una postulación duplicada.
3. **Asistente**: origen permitido (dominios), eventos que emite y estado de
   progreso recuperable.
4. **Catálogo de estados** del asistente y de la emisión, y su correspondencia
   con los códigos DGII `0/1/2/3/4`.
5. **Idempotencia**: si el mismo e-NCF reenviado devuelve el mismo `trackId`
   o un error de secuencia duplicada.
6. **Vigencia de los rangos e-NCF** de pruebas: fecha exacta y qué ocurre al
   agotarse.

Inconsistencias ya detectadas en la documentación pública que DOSA debe
resolver antes de implementar:

- `codigo = 0` está descrito como «No encontrado» en la tabla oficial, pero el
  ejemplo de manejo de respuestas lo trata como «Rechazado».
- «Nunca reutilizar una secuencia, incluso si el envío falló» convive con la
  recomendación de reintentar **con el mismo eNCF** tras un HTTP 502.
- `codigo` aparece como texto (`"4"`) en unos ejemplos y como entero en la tabla.
- Las facturas de consumo (E32 < RD$250.000) se envían como RFCE y **no**
  devuelven `trackId`, así que `trackId` no sirve como clave de idempotencia
  universal.

---

## 5. Verificación antes de cualquier fase con red

```powershell
# 1. Ningun fichero con secretos entra en Git
git status --short          # no debe listar .env.*.local ni .secrets/

# 2. La emision sigue apagada para todos los proveedores
npx jest src/ecf/provider   # availability => emissionAllowed: false

# 3. El backend compila y las pruebas pasan
npm run api:build
npm --workspace apps/api test
```
