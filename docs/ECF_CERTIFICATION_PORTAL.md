# Portal de certificación electrónica (DOSA)

Estado: **implementado y validado en local**. La publicación en el dominio
autorizado está **preparada pero no ejecutada** (requiere autorización, §8).

Un solo portal para todas las plataformas. No hay un asistente por dispositivo.

---

## 1. Por qué un portal y no un componente embebido

DOSA solo permite enmarcar su asistente desde
`https://fullposcloud.fulltechrd.com` (CSP `frame-ancestors`). Por eso:

- En **Web/PWA, Windows, Android e iOS** la acción es la misma: abrir
  `https://fullposcloud.fulltechrd.com/ecf/certificacion` en el navegador.
- El componente oficial se monta **dentro de ese documento**, no en un WebView
  con contenido local (un iframe desde local está bloqueado por el proveedor).

---

## 2. Piezas

| Capa | Pieza | Función |
| --- | --- | --- |
| API | `src/ecf/portal/ecf-certification-portal.service.ts` | Tickets, sesiones y contexto |
| API | `src/ecf/portal/ecf-certification-portal.controller.ts` | 4 endpoints |
| BD | `ecf_certification_portal_tickets` / `_sessions` | Solo hashes SHA-256, caducidad, revocación |
| Portal | `deploy/ecf-certificacion/index.html` | Página estática, responsive, identidad FullPOS |
| App | `lib/features/ecf/dosa/dosa_portal_launcher.dart` | Pide el ticket y abre el portal |
| App | `dosa_assistant_section.dart` | Botón único «Iniciar o continuar certificación» |
| Ops | `scripts/dev/publish_ecf_portal.ps1` | Publicación con dry-run por defecto |

### Endpoints

| Método | Ruta | Auth | Notas |
| --- | --- | --- | --- |
| `POST` | `/ecf/certification-portal/tickets` | JWT + `manageEcfOnboarding` | Empresa del token; invalida tickets vivos |
| `POST` | `/ecf/certification-portal/sessions` | ticket de un solo uso | Canje; consume el ticket (atómico) |
| `GET` | `/ecf/certification-portal/context` | cabecera `x-fullpos-portal` | Solo lectura |
| `DELETE` | `/ecf/certification-portal/sessions` | cabecera `x-fullpos-portal` | Revoca |

Cabecera `x-fullpos-portal`, **nunca** el token en la URL.

---

## 3. Modelo de seguridad

0. **Compuerta del piloto**: `ECF_PORTAL_PILOT_COMPANY_IDS` lista los `companyId`
   autorizados. **Vacía o ausente = portal cerrado**. Se aplica al emitir ticket,
   al canjear la sesión y al leer el contexto. Ver `docs/ECF_CERTIFICATION_PILOT.md`.

1. **Ticket**: 32 bytes aleatorios (base64url), TTL **120 s**, un solo uso. Se
   guarda solo su SHA-256. En la URL viaja el ticket, no una sesión; el portal
   lo canjea y **borra el parámetro del historial** con `replaceState`.
2. **Sesión del portal**: TTL **30 min**, revocable, también hasheada. Vive en
   `sessionStorage` del portal, no en la app ni en la URL.
3. **Tenant**: la empresa sale del ticket y de la fila de sesión. El navegador
   no elige empresa: si reclama otra, el canje se rechaza con 403 y el ticket
   **no se consume**.
4. **Permisos**: emitir ticket exige `manageEcfOnboarding`; un usuario sin ese
   permiso recibe 403 y nunca puede abrir el portal.
5. **Claves**: la publicable (`pk_live_`) es pública y solo vive en el portal
   publicado. Las claves privadas de emisión y el secreto del webhook siguen
   exclusivamente en el backend (`vault://`, `.secrets/`).
6. **Alcance fiscal**: el portal no activa e-CF, no emite y no envía nada a la
   DGII. `cert:complete` **no** es una certificación aprobada.

---

## 4. Continuidad entre dispositivos

El proceso pertenece a la empresa: se reutilizan `EcfDosaCertificationSession`
(`attemptNo`, `status`, `providerPostulationId`) y el expediente existente. Abrir
el portal en otro equipo **no** crea una postulación nueva; el contexto lee el
intento más reciente de esa empresa.

---

## 5. Fase 5 — la sesión técnica solo se crea si el administrador lo pide

El HTML del proveedor hace `POST /api/certificacion/sesiones-publicas` al
cargarse. Por eso el portal **no** monta el componente al abrirse: muestra el
recorrido y un botón explícito. Consultar Configuración en FullPOS nunca crea
una sesión en DOSA.

---

## 6. Validaciones ejecutadas en local (2026-11-02)

```
apps/api: jest src/ecf/portal .......................... 13 passed
apps/api: tsc -p tsconfig.build.json --noEmit ......... 0 errores
apps/fulltech_app: flutter analyze (dosa + api_routes)  No issues found
apps/fulltech_app: flutter test dosa_portal_launcher .. 9 passed
prisma migrate deploy (BD desechable) ................. aplicada
```

Prueba de extremo a extremo contra la API local (BD desechable, empresa de
pruebas FULLTECH SRL):

```
LOGIN=201 · TOKEN_PRESENT=True
TICKET=201 · len=43 · TTL=120
EXCHANGE=201 · PORTAL_TOKEN len=43
CONTEXT=200 · COMPANY=<empresa del expediente> · RNC=<el de app_config>
MILESTONES=in_progress/locked/locked
POSTULATION=intento 1 NOT_STARTED
ECF_ENABLED=False                      (no se enciende nada)
REUSE_TICKET=409                       (un solo uso)
OTHER_COMPANY_CLAIM=403                (el navegador no elige empresa)
NO_HEADER=401
LOGOUT=200 · AFTER_LOGOUT=401          (revocación efectiva)
```

Prueba en navegador real del portal:

- El ticket de la URL se canjea y **desaparece de la barra de direcciones**.
- Se muestran empresa, RNC e «Intento 1 · NOT_STARTED».
- Recorrido: **Solicitud en curso**, Pruebas y Certificación bloqueadas.
- Al pulsar el botón se carga `dosa-cert.js` y se monta `<dosa-cert-wizard>`.
- En `localhost` el evento es `cert:blocked { origin: "http://127.0.0.1:8090" }`
  porque la CSP del proveedor solo autoriza el dominio oficial. Es el
  comportamiento esperado fuera del dominio autorizado.

Capturas: `portal-01-context.png`, `portal-02-asistente-montado.png`.

---

## 7. Piloto exclusivo para FULLTECH SRL

1. La empresa ya tiene su intento (`Intento 1 · NOT_STARTED`).
2. Publicar el portal en el dominio autorizado (§8). No se toca la PWA ni el
   backend: es una página estática nueva bajo `/ecf/certificacion`.
3. Abrir desde FullPOS: el botón «Iniciar o continuar certificación» pide el
   ticket y abre el portal. Solo lo puede hacer un administrador con
   `manageEcfOnboarding` de **esa** empresa.
4. En el portal, pulsar «Iniciar o continuar certificación» para montar el
   asistente oficial y verificar `cert:ready`.
5. e-CF sigue **OFF** (`ECF_ENABLED=False`): el piloto no habilita emisión.

### Restricción adicional a nivel de red (opcional)

El portal ya exige ticket, así que un visitante anónimo no ve nada. Si además se
quiere cerrar por completo, añadir al `server` de
`/etc/nginx/conf.d/default.conf`:

```nginx
location /ecf/certificacion/ {
    auth_basic           "FullPOS - certificación";
    auth_basic_user_file /etc/nginx/.htpasswd_ecf;
    try_files $uri $uri/ =404;
}
```

con `/etc/nginx/.htpasswd_ecf` generado en el servidor (`openssl passwd -apr1`),
`nginx -t` y `nginx -s reload`. **No** forma parte de este cambio.

---

## 8. Cambio mínimo y autorización

Cambio: copiar **un archivo** (`index.html`) dentro del contenedor nginx que ya
existe. Sin reconstruir la imagen, sin reiniciar el servicio, sin migraciones en
producción, sin tocar el backend.

> **OJO:** el piloto requiere la migración `20261103210000_ecf_certification_portal`
> aplicada en la base de datos de producción para que existan los endpoints. Eso
> **sí** es un cambio de esquema (aditivo: dos tablas nuevas, sin alterar nada
> existente) y necesita autorización explícita.

```
Autorizo, para el piloto de FULLTECH SRL:
  1) aplicar la migración aditiva 20261103210000_ecf_certification_portal
     en la base de datos de producción;
  2) desplegar la API con el módulo del portal;
  3) crear /usr/share/nginx/html/ecf/certificacion/index.html dentro del
     contenedor daleventapos_pwa (sin reconstruir imagen ni reiniciar servicio);
  4) [opcional] location /ecf/certificacion/ con auth_basic + nginx -s reload
     (con respaldo previo del default.conf);
  5) eliminar /ecf/certificacion al terminar la verificación.
No se autoriza: habilitar e-CF, emitir comprobantes, enviar postulaciones o
documentos a la DGII, cargar certificados, pagar, ni tocar datos de clientes.
```

Comandos:

```powershell
# API + migración (requiere autorización)
npm run api:build
# (en el servidor) npx prisma migrate deploy

# Portal estático (dry-run primero)
pwsh -File scripts/dev/publish_ecf_portal.ps1
pwsh -File scripts/dev/publish_ecf_portal.ps1 -Apply
```

---

## 9. Reversión

```powershell
# Portal: borra solo esta vista, la PWA sigue igual
ssh -i "$env:USERPROFILE\.ssh\daleventas_codex" root@31.97.99.70 `
  "docker exec <container> rm -rf /usr/share/nginx/html/ecf"

# API: desplegar la imagen anterior (rollback por tag, ver docs/RELEASE.md).
# Migración: es aditiva; revertirla solo si se revierte la API
#   DROP TABLE "ecf_certification_portal_sessions", "ecf_certification_portal_tickets";
```

Como el portal vive dentro del contenedor, un redeploy de la PWA lo elimina
solo: no queda residuo si se olvida el paso manual.
