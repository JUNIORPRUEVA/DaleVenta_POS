# Kit de UAT manual — e-CF y expediente DGII

Estado: **preparado para una sola ronda manual**. No contiene credenciales ni
datos reales. Nada de este kit toca producción ni la base histórica `56550`.

## 1. Artefactos construidos (2026-10-19)

### Web UAT

- Origen: `apps/fulltech_app/build/web`
- `main.dart.js`: 11 898 493 bytes
- SHA-256: `38C95F334F76D08E813BEB23241EB32146FBF85F2DC1366528EF7D4BE2532A34`
- Defines: `APP_ENV=uat`, `FULLPOS_UAT_PROFILE=true`, `API_BASE_URL`, `APP_BASE_URL` y `RELEASES_API_BASE_URL` = `http://127.0.0.1:4004`

### Windows UAT

- Distribuible: `C:\b\ecf-uat-dist\FullPOS-UAT-20261019-154848`
- Manifiesto: `...\UAT_BUILD_MANIFEST.json`
- `app.so` SHA-256: `5877F42EE884F845EB5DB5934C250BCC5BE262DA58053A18BE33A3D2B75F14A4`
- `fullpos_cloud.exe` SHA-256: `98217A27D23A1E5BD8F605A9A07A0B7C02FED40825DACF13A4A18E7A408DB5A7`
- Construido por `scripts/build/build_windows_ecf_uat.ps1` (valida rama, rechaza URLs de producción y deja manifiesto sin secretos)

### Android / iOS

**BLOCKED.** No se compilaron en este entorno. No deben considerarse validados.

## 2. Aislamiento de producción

**Corregido:** una comprobación global («¿hay conexiones a `31.97.99.70`?»)
confunde la instalación **comercial** de DaleVentas POS con el ejecutable UAT.
La comprobación correcta atribuye cada conexión a su proceso:

```powershell
pwsh scripts/visual-uat/uat-connection-audit.ps1 -OutFile C:\b\uat_audit.txt
```

El script (solo lectura) resuelve PID → nombre → ruta y clasifica cada conexión:

| Clase | Significado | Efecto |
| --- | --- | --- |
| `UAT` | Ruta dentro de `ecf-uat-dist` o `C:\b\ecf` | Con conexión fuera de loopback ⇒ **FAIL** |
| `COMERCIAL` | `...\DaleVentas POS\...` | Informativa: **nunca bloquea** y nunca se cierra |
| `OTRO` | Chrome, VS Code, etc. | Informativa |
| `DESCONOCIDO` | Ruta no accesible (p. ej. `svchost`) | Informativa |

Códigos de salida: `0` = UAT aislado · `1` = un proceso UAT alcanzó algo que no
es loopback · `2` = **NOT_APPLICABLE** (no hay proceso UAT vivo, no hay nada que
probar todavía).

Evidencia de referencia del 2026-10-19: la conexión a `31.97.99.70:443`
pertenecía al **PID 3584** (`C:\Program Files\DaleVentas POS\app\fullpos_cloud.exe`,
instalación comercial) y a pestañas de Chrome; **no había ninguna conexión de
clase `UAT`**. El pre-flight anterior se detenía por esa conexión ajena.

Regla operativa: la instalación comercial **no se cierra ni se modifica**. Solo
se bloquea si una conexión pertenece a un artefacto UAT.


## 3. Levantar el entorno

```powershell
# 1. Base desechable (puerto 56551; NUNCA 56550)
pwsh scripts/ecf-test-db/up.ps1
pwsh scripts/ecf-test-db/reset.ps1
pwsh scripts/ecf-test-db/migrate.ps1

# 2. Personal de plataforma SOLO en este proceso (id de usuario sintético)
$env:ECF_PLATFORM_STAFF_USER_IDS = '<id-del-usuario-fulltech>'
$env:ALANUBE_ENABLE_REAL_CALLS = 'false'

# 3. API UAT
pwsh scripts/visual-uat/visual-uat.ps1 -Action start-api
```

Datos sintéticos: se crean en la propia UAT con
`POST /auth/register-business` (dos empresas distintas) y un usuario de
plataforma. Elige tú la contraseña en el momento; **no se guarda en este
documento**.

## 4. Abrir las aplicaciones

- **Windows**: ejecutar `fullpos_cloud.exe` desde
  `C:\b\ecf-uat-dist\FullPOS-UAT-20261019-154848`.
- **Web**: servir `apps/fulltech_app/build/web` en local (por ejemplo
  `python -m http.server 8080 --directory build/web`) y abrir
  `http://127.0.0.1:8080`.

## 5. Guion de prueba manual

| # | Paso | Resultado esperado |
| --- | --- | --- |
| 1 | Iniciar sesión con el usuario de empresa | Entra sin errores; sin conexiones a producción |
| 2 | e-CF → Habilitación DGII → Asistente | Paso «Datos» con 6 campos |
| 3 | Escribir el RNC y esperar ~1 s | «Guardando…» y luego «Guardado» |
| 4 | Cerrar la pantalla y volver a abrir | Datos recuperados del servidor |
| 5 | Vaciar un campo obligatorio y pulsar Siguiente | No avanza; indica qué falta |
| 6 | Completar empresa y representante legal | Avanza a Requisitos |
| 7 | Subir un PDF ficticio como documento | Aparece en la lista con su tipo |
| 8 | Llegar a Enviar y pulsar sin aceptar | No envía; exige consentimiento |
| 9 | Aceptar el consentimiento y enviar | «Expediente enviado. Versión 1.» |
| 10 | Repetir el envío idéntico | «Ya estaba enviado (versión 1)» |
| 11 | Con el usuario Fulltech: abrir el panel | Cola con el expediente de la empresa |
| 12 | Filtrar por estado y abrir el detalle | Datos, requisitos y evidencias; sin rutas de almacenamiento |
| 13 | Descargar un documento | El navegador descarga el archivo real |
| 14 | Revisar una evidencia rechazándola sin motivo | Rechaza y pide motivo |
| 15 | «Solicitar corrección» con motivo | El expediente pasa a corrección |
| 16 | Volver al usuario de empresa: Historial | El evento aparece con su autor |
| 17 | Corregir un dato y reenviar | Crea Versión 2; la 1 sigue en el historial |
| 18 | Repetir 2–13 en Windows y en 360×640 / 1440×900 | Sin desbordes, sin dobles envíos |

## 6. Recuperación y rollback

- **Datos**: `pwsh scripts/ecf-test-db/reset.ps1` recrea la base desechable. No
  hay nada que restaurar en producción porque nunca se tocó.
- **API**: `pwsh scripts/visual-uat/visual-uat.ps1 -Action stop-api`.
- **Artefactos**: se pueden borrar las carpetas `C:\b\ecf` y
  `C:\b\ecf-uat-dist\FullPOS-UAT-*`; no afectan a ninguna instalación
  comercial.
- **Conflicto de borrador**: si aparecen dos sesiones editando, la segunda debe
  mostrar «El borrador se actualizó en otro dispositivo» y cargar la versión
  del servidor. Verificarlo es parte del guion (paso 3 desde dos ventanas).

## 7. Qué NO se valida aquí

- Emisión fiscal real, consumo de e-NCF, certificados digitales y llamadas a
  Alanube o DGII: **fuera de alcance por diseño**.
- Android e iOS: sin build en este entorno.
