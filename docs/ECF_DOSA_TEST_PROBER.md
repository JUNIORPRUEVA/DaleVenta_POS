# DOSA — probador E31 de TEST y barreras de seguridad

Estado: Fase G. **No se ha realizado ninguna emisión externa.**

---

## 1. Barrera de la estrategia de firma no verificada

`UNVERIFIED_PLAINTEXT_SECRET` sirve solo para probar el mecanismo del webhook
con tráfico propio. Tener `BLOCKED` como valor por defecto **no era suficiente**:
un error de configuración podía activarla en un entorno real. Ahora hay dos
barreras independientes.

**Barrera 1 — degradación silenciosa pero segura.**
`readDosaSignatureConfig()` solo aplica la estrategia si se cumplen las tres
condiciones a la vez:

| Condición | Valor exigido |
| --- | --- |
| `NODE_ENV` | distinto de `production` |
| `APP_ENV` | uno de `local`, `local-boot`, `lab`, `test`, `e2e` |
| `DATABASE_URL` | host de loopback (`localhost`, `127.0.0.1`, `::1`) |

Si falla cualquiera, la estrategia efectiva es `BLOCKED` y la configuración
devuelve `downgradedFrom` + `downgradeReason` para que el operador lo vea.

**Barrera 2 — el arranque falla ruidosamente.**
`assertDosaSignatureLabSafety()` se ejecuta en `main.ts` antes de crear la
aplicación. Si la variable pide la estrategia no verificada fuera de laboratorio,
la aplicación **no arranca**:

```
Error: DOSA safety refused startup: DOSA_WEBHOOK_SIGNATURE_STRATEGY=UNVERIFIED_PLAINTEXT_SECRET
solo se permite en un laboratorio local (NODE_ENV!=production, APP_ENV local/test
y DATABASE_URL de loopback).
```

Verificado contra el binario compilado: `NODE_ENV=production` + estrategia no
verificada ⇒ **exit code 1**, la aplicación no llega a escuchar. Y con
`APP_ENV=local-boot` + base de loopback ⇒ arranca normal.

Cobertura: 22 pruebas negativas en `dosa-signature-safety.spec.ts` (producción,
staging, UAT, base remota, contexto ausente, valores basura).

---

## 2. Probador E31 de TEST

Dos piezas:

- `dosa-test-emission.probe.ts` — lógica con transporte inyectable. **No importa
  Prisma, no conoce empresas y no puede tocar la configuración e-CF de nadie.**
- `dosa-test-emission.probe.cli.ts` — CLI que escribe evidencia en un JSONL local.

### Qué valida antes de abrir un socket

| # | Validación | Si falla |
| --- | --- | --- |
| 1 | `environment === TEST` | `DOSA_PROBE_NOT_TEST_ENVIRONMENT` |
| 2 | `baseUrl === https://dosasystem.com` (exacto) | `DOSA_PROBE_BASE_URL_NOT_DOCUMENTED` |
| 3 | Hay API Key | `DOSA_PROBE_API_KEY_MISSING` |
| 4 | Hay RNC de prueba | `DOSA_PROBE_TEST_RNC_MISSING` |
| 5 | Documento E31 | `DOSA_PROBE_DOCUMENT_TYPE_UNSUPPORTED` |
| 6 | RNC emisor == RNC de prueba | `DOSA_PROBE_SENDER_RNC_MISMATCH` |
| 7 | e-NCF dentro del rango | `DOSA_PROBE_ENCF_OUTSIDE_ALLOWED_RANGE` |
| 8 | Totales coherentes y con 2 decimales | `DOSA_PROBE_TOTALS_INCOHERENT` |
| 9 | Token de autorización correcto | `DOSA_PROBE_EXTERNAL_POST_NOT_AUTHORIZED` |

El token es `AUTHORIZE-<eNCF>`. Sin él no hay petición: un comando copiado por
error no puede consumir una secuencia.

### Uso

```powershell
cd apps/api
# 1) Simulacro: valida todo y deja evidencia, SIN enviar nada
node dist/ecf/provider/dosa/dosa-test-emission.probe.cli.js --encf=E31000113500 --dry-run

# 2) Envío real (solo cuando esté autorizado y las variables estén cargadas)
node dist/ecf/provider/dosa/dosa-test-emission.probe.cli.js `
  --encf=E31000113500 --token=AUTHORIZE-E31000113500
```

Variables (ninguna se imprime):

```
DOSA_EMISSION_ENVIRONMENT=TEST
DOSA_BASE_URL=https://dosasystem.com
DOSA_TEST_API_KEY=<clave TEST>
DOSA_TEST_RNC=133306001
DOSA_TEST_SEQUENCE_PREFIX=E31
DOSA_TEST_SEQUENCE_FROM=113500
DOSA_TEST_SEQUENCE_TO=115500
DOSA_PROBE_EVIDENCE_FILE=.dosa-probe/evidence.jsonl
```

### Comportamiento ante fallo

- **Un solo intento.** Nunca reintenta automáticamente.
- Timeout o error de red ⇒ evidencia `UNCERTAIN`, `safeToRetrySameEncf: false`.
- HTTP 502 con `estado: "Error de envío"` ⇒ único caso con
  `safeToRetrySameEncf: true` (la DGII no recibió nada).
- La evidencia guarda hash de la respuesta y `apiKeyLength`, **nunca la clave**
  (probado: la cadena de la clave no aparece en el registro).

---

## 3. Rotación de credenciales del laboratorio

La contraseña de la base desechable usada en fases anteriores quedó expuesta en
las transcripciones del terminal. Se sustituyó:

1. Se generó una contraseña nueva y se guardó en un fichero fuera del
   repositorio, sin imprimirla.
2. Se eliminaron el contenedor anterior y todos los ficheros `.env`/secretos
   temporales de `C:\b\fullpos-boot`.
3. Se recreó el contenedor con la contraseña nueva y se reaplicaron las 51
   migraciones desde cero (144 tablas).
4. Las 43 pruebas de integración se reejecutaron contra la base nueva.

La clave maestra de la bóveda y el secreto del webhook del laboratorio anterior
también se descartaron: eran efímeros y no están en Git.
