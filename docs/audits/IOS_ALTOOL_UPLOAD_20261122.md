# iOS: subida a Apple después del PR #54

## Evidencia real

Codemagic build `6b033c458f52ca27512a3f03`, índice 26, workflow
`ios-testflight`, rama `production-main`, commit del merge `c70701e0`.
La sesión abierta de Codemagic permitió confirmar:

- Análisis y regresión móvil aprobados.
- Firma, compilación de IPA y verificación de la IPA aprobadas.
- Artefacto `FULLTECH.ipa`, versión `1.0.7`, build `151`.
- Bundle `com.fulltechrd.fullposcloud`, distribución App Store, iOS mínimo 15.5.
- Fallo exclusivamente en Publishing: altool de Xcode 26.6 no pudo resolver
  el Apple ID a partir del bundle, errores 19 y 31.

No se infiere un error en las pantallas ni pérdida de commits a partir de ese fallo.
La validación de firma no acredita que la clave pueda acceder a la ficha Apple.

## Diagnóstico y cambio mínimo

La documentación oficial de Codemagic describe exactamente el error. Sus causas
posibles incluyen acuerdos pendientes en Apple y la resolución de aplicaciones
por el nuevo altool en Xcode 26, especialmente con varios proveedores.

Fuente:
https://help.codemagic.io/articles/7154824641-why-am-i-getting-a-cannot-determine-the-apple-id-from-bundle-id-error-during-an-ios-build

El ajuste añade al entorno de **ios-testflight únicamente**:

```yaml
APP_STORE_CONNECT_ALTOOL_ADDITIONAL_ARGUMENTS: "--use-old-altool"
```

Es el workaround publicado por Codemagic, no una prueba de que esa sea la única
causa en esta cuenta. No cambia certificado, API key, equipo, bundle, versión,
build, código Flutter, workflow sin firma ni publicación automática a testers.
No se incorpora ninguna credencial al repositorio.

## Acceso y límites

La aplicación de Codemagic no tenía variables de entorno de aplicación definidas
en la pantalla revisada; la integración Apple existente se conserva en YAML como
`CodemagicKey`. No se revelaron secretos guardados en la interfaz.

Se encontró un archivo local de clave Apple y se verificó su formato EC. Eso no
demuestra vigencia remota ni que sea la clave de la integración activa. No se
encontró un token Codemagic en las rutas locales examinadas y no se generó uno.

App Store Connect abrió la página de login: el propietario debe autenticarse
personalmente. Hasta revisar la cuenta no se afirma que la ficha, acuerdos y
permisos estén correctos. No se aceptaron acuerdos ni se crearon apps o claves.

## Recorrido para terminar

1. Revisar la ficha existente de `com.fulltechrd.fullposcloud` en Apple, el equipo
   elegido, los acuerdos pendientes y acceso de la integración. No duplicar apps.
2. Revisar e integrar el PR de este ajuste sobre `production-main`.
3. El propietario inicia `ios-testflight` desde el nuevo commit integrado.
4. Confirmar que Publishing usa la opción legacy, Apple acepta la carga y termina
   su procesamiento. Si vuelve a fallar, conservar el nuevo error y revisar el
   acceso a la ficha; no repetir builds idénticos indefinidamente.
5. Comprobar en App Store Connect si 151 ya fue recibido antes de reutilizarlo.
   La subida fallida no prueba por sí sola que Apple no haya recibido el binario.

NO-GO para declarar publicación resuelta hasta una carga efectiva aceptada.
No hubo deploy de servicios ni cambios en FullPOS productivo.

## Validación local del ajuste

- Parser YAML: los dos workflows iOS se resuelven correctamente.
- Los 14 scripts conservan sintaxis Bash válida; ambos preparan su configuración
  pública desde directorios limpios (`CLEAN_CONFIG_PASS`).
- Comparación exacta con HEAD: solo se añade la variable y sus dos comentarios
  dentro de `ios-testflight`. Firma, publicación y workflow sin firma intactos.
- `git diff --check`: aprobado.

No se repitió Flutter porque no cambió código ni dependencias de la app. El build
real ya acredita análisis, pruebas y firma; validar el cambio de transporte exige
ejecutarlo en Codemagic/macOS, algo aún no realizado con este ajuste.
