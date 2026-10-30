# UAT Windows — el binario puede apuntar a producción si falta el perfil UAT

> **Hallazgo de seguridad del proceso de UAT (2026-10-18).** No es un fallo de
> la aplicación comercial: es un fallo del **procedimiento de construcción de la
> UAT**. Un build de validación sin el perfil correcto habla con **producción**.

## 1. Qué pasó exactamente (HECHO)

Se compiló la UAT con:

```text
flutter build windows --release --dart-define=APP_ENV=uat
```

La aplicación arrancó, pero mostraba una empresa (**FULLTECH, SRL**) y productos
que **no existían** en la base local desechable. Comprobado:

| Comprobación | Resultado |
| --- | --- |
| Empresa mostrada en la UI presente en `fullpos_alanube_uat_test` | **No** (0 filas) |
| Producto mostrado en la UI presente en la base local | **No** (0 filas) |
| Conexiones establecidas del proceso | **32**, todas a `31.97.99.70:443` |
| Host por defecto `ProductConfig.productionApiBaseUrl` | `https://daleventapos-backend.gcdndd.easypanel.host` |

**Conclusión:** la aplicación UAT estaba leyendo **producción**. La sesión
persistida y el catálogo mostrado eran reales, no sintéticos.

## 2. Por qué ocurre (HECHO, en el código)

`lib/core/api/env.dart` resuelve `API_BASE_URL` en este orden:

1. `String.fromEnvironment('API_BASE_URL')` — es decir, `--dart-define`.
2. Entorno de ejecución (solo Web).
3. `dotenv.env['API_BASE_URL']` — el `.env` empaquetado.

Y después:

```dart
if (raw.isEmpty) {
  return _defaultApiBaseUrl; // = ProductConfig.productionApiBaseUrl
}
```

El `.env` **sí** estaba empaquetado (`data/flutter_assets/.env` con
`API_BASE_URL=http://127.0.0.1:4004`). Por tanto el valor del `.env` **no basta**:
si `dotenv` no ha cargado todavía cuando se resuelve la URL —o si el cliente HTTP
se construyó antes— el resultado es la **URL de producción**, sin aviso visible.

## 3. El blindaje ya existe, pero hay que activarlo

`lib/core/config/uat_api_config.dart` implementa un perfil **fail-closed**:

- solo se activa con `--dart-define=FULLPOS_UAT_PROFILE=true`;
- exige `API_BASE_URL` explícita;
- admite únicamente `localhost` / `127.0.0.1` / `::1`;
- rechaza marcadores productivos (`gcdndd`, `easypanel`, `31.97.99.70`, …);
- **no tiene valor por defecto**: si falta o no es local, lanza excepción visible.

Sin esa bandera, el mecanismo **no se aplica**. Ese fue el defecto del build.

## 4. Comando correcto (obligatorio para cualquier UAT)

```powershell
flutter build windows --release `
  --dart-define=APP_ENV=uat `
  --dart-define=FULLPOS_UAT_PROFILE=true `
  --dart-define=API_BASE_URL=http://127.0.0.1:4004 `
  --dart-define=APP_BASE_URL=http://127.0.0.1:4004
```

Con `FULLPOS_UAT_PROFILE=true` y `--dart-define`, el valor es **de compilación**
(prioridad 1), no depende de que `dotenv` cargue, y un error de configuración
**falla en voz alta** en vez de conectar con producción.

## 5. Verificación obligatoria antes de usar la UAT

No basta con leer el `.env` del binario. Hay que comprobar el **tráfico real**:

```powershell
$p = Get-Process fullpos_cloud | Select-Object -First 1
Get-NetTCPConnection -OwningProcess $p.Id -State Established |
  Select-Object RemoteAddress, RemotePort -Unique
```

| Resultado | Veredicto |
| --- | --- |
| Solo `127.0.0.1:4004` | **Correcto** |
| Cualquier IP pública (p. ej. `31.97.99.70`) | **DETENER**: el build no es UAT |

## 6. Qué se hizo al detectarlo

1. Se cerró el proceso de inmediato para detener el tráfico.
2. No se ejecutó ninguna escritura contra producción: la sesión era de **lectura**
   (arranque de la app con sesión persistida). No se creó ni modificó nada.
3. Se recompiló con el comando de §4 y se repitió la verificación de §5.

## 7. Solución permanente (2026-10-18, segunda iteración)

El blindaje por `--dart-define` dependía de que alguien recordara pasarlo. Ahora
el riesgo está cerrado **en ejecución**, no solo en el procedimiento:

| Capa | Archivo | Qué garantiza |
| --- | --- | --- |
| Guardia de destinos | `lib/core/config/uat_network_guard.dart` | Se activa con `FULLPOS_UAT_PROFILE=true` **o** `APP_ENV=uat`. Exige URL explícita, valida **host y puerto parseados** (no subcadenas) y rechaza hosts productivos y cualquier `*.easypanel.host` |
| Resolución de URLs | `lib/core/api/env.dart` | `API_BASE_URL`, `APP_BASE_URL` y `RELEASES_API_BASE_URL` pasan por la guardia. Sin fallback a producción |
| Cliente HTTP | `lib/core/api/api_client.dart` | En UAT no sigue redirecciones y un interceptor valida el destino real de **cada** petición antes de enviar credenciales |
| Sesión | `lib/core/auth/token_storage.dart` | En UAT las claves llevan prefijo `uat.`. Los builds comerciales conservan sus claves intactas |
| Datos locales | `lib/core/offline/offline_store.dart` | En UAT la base SQLite es `fulltech_offline_uat.db`; el build comercial sigue usando `fulltech_offline.db` |
| Build | `scripts/build/build_windows_ecf_uat.ps1` | Verifica rama, rechaza URLs productivas, compila con el perfil, comprueba que `app.so` se regeneró y emite un manifiesto sin secretos |

Comportamiento ante configuración incompleta (verificado por pruebas):

```text
UAT sin API_BASE_URL        -> UAT_CONFIG_REFUSED (..._REQUIRED)
UAT con URL productiva      -> UAT_CONFIG_REFUSED (.../URL_POINTS_TO_PRODUCTION)
UAT con redirección a prod. -> petición rechazada antes de enviarse
Build comercial             -> sin cambios (la guardia no interviene)
```

## 8. Regla permanente

> Un build de UAT **siempre** lleva `FULLPOS_UAT_PROFILE=true` y `API_BASE_URL`
> local por `--dart-define`. Un `.env` empaquetado **no** es garantía suficiente.
> Antes de cualquier prueba visual se verifica el tráfico, no la configuración.

## 9. Por qué esto explicaba los fallos de acceso anteriores

El usuario sintético de la UAT **no existe en producción**. Cualquier intento de
inicio de sesión desde un binario sin el perfil UAT iba a fallar siempre, por muy
correcta que fuese la contraseña. El problema no era la credencial: era el
destino de la petición.
