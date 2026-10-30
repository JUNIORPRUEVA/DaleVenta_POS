# Solicitud técnica — Alanube DOM / FULLTECH, SRL

BORRADOR NO ENVIADO. Preparado el 2026-10-14 para integración Fullpos Cloud,
multiempresa, República Dominicana. No incluye token, certificados ni datos
reales de clientes. Enviar manualmente solo tras revisión del responsable.

Estimado equipo técnico de Alanube:

Estamos preparando la integración DOM de Fullpos Cloud. Ya consultamos las
referencias públicas E31/E32/E34 y recuperamos sus esquemas OpenAPI 3.0.3
incrustados. Solicitamos confirmar su vigencia y facilitarnos una distribución
oficial versionada, completa y descargable que incluya referencias compartidas,
variantes síncronas/asíncronas y condiciones fiscales. No hemos emitido documentos.

Necesitamos resolver los puntos siguientes:

1. **OpenAPI DOM y esquemas:** versión soportada, changelog, compatibilidad,
   JSON Schema request/response E31/E32/E34, referencias y reglas condicionales.
   Aclarar restricciones no representadas en OpenAPI y diferencias con XML DGII.
2. **Ejemplos:** requests y respuestas ficticias válidas para gravados/exentos,
   descuentos, E32 bajo/sobre umbral, E34 parcial/total y modificación textual;
   resultados de validación, pendientes, aceptación y rechazo.
3. **Idempotencia DOM:** confirmar soporte de Idempotency-Key u otro mecanismo,
   formato, alcance por empresa/documento, TTL, comparación de payload,
   concurrencia, respuesta a duplicados y garantías tras timeout/5xx. No asumimos
   que la documentación de Colombia aplique a DOM.
4. **Consulta/conciliación:** endpoints por id/idCompany/e-NCF/correlación,
   autorización por compañía, filtros, consistencia eventual, tratamiento de
   404 tras timeout y forma segura de recuperar un resultado si no recibimos id.
5. **Estados:** diccionario de status/ legalStatus/governmentResponse,
   transiciones válidas y estados terminales. Aclarar por qué FINISHED no debe
   interpretarse sin evidencia adicional y diferencias por tipo/documento.
6. **Errores:** catálogo vigente, estructura y clasificación reintentable,
   distinción entre rechazo definitivo y resultado desconocido.
7. **Webhooks:** JSON Schema de eventos, identificador único, empresa y documento,
   orden, duplicados, reenvíos, ACK esperado, timeouts y política de entrega.
   Confirmar autenticación soportada, firma HMAC/asimétrica si existe,
   canonicalización, timestamp/tolerancia, protección replay y rotación de claves.
   Vimos el flujo público de autenticación previa; no asumimos que sea una firma.
8. **Límites:** cuotas/rate limits DOM por token/empresa/endpoint, headers,
   Retry-After, polling aconsejado, límites de concurrencia y SLA Sandbox.
9. **Certificación:** pasos Alanube/DGII, evidencias requeridas y responsabilidades
   del proveedor, FULLTECH y empresa cliente; distinguir simulación Sandbox y
   habilitación legal productiva.
10. **Reseller y clientes:** requisitos comerciales/técnicos para FULLTECH, SRL,
    alta/activación de compañías asociadas, permisos/token scopes, titularidad
    del certificado, custodia/renovación y segregación multiempresa.
11. **Numeración Sandbox:** RNC ficticio permitido, rangos/secuencias e-NCF,
    vencimientos, reglas de consumo/reutilización y procedimiento de pruebas.
12. **Primera prueba futura:** requisitos para una única emisión ficticia
    controlada y su conciliación, sin conexión a producción ni efectos legales.

La emisión permanece deshabilitada hasta confirmar estos contratos y recibir
autorización explícita del operador. Agradecemos respuestas con referencias
versionadas y ejemplos sintéticos, sin enviar secretos por este documento.

## Ampliación técnica — fases 91–100 (borrador no enviado)

Solicitamos además un contrato de confianza versionado: bytes exactos a verificar,
firma/autenticación soportada (sin asumir HMAC), canonicalización si aplica,
encabezados, timestamps/replay, rotación/revocación y ejemplos positivos/negativos.
Indicar qué artefacto verificable demuestra aceptación/rechazo DGII, su identidad
de empresa/documento y política de conservación/reverificación.

Confirmar cómo correlacionar de forma autenticada la primera respuesta con
operación/fingerprint/intento local, recuperar un id nunca recibido tras timeout,
tratar respuestas tardías/contradictorias y eventos fuera de orden. Precisar
consistencia del GET, significado del 404, autorización idCompany y diferencias
entre respuesta de emisión y consulta. No asumimos que el schema de POST sirva
para GET ni que el id remoto pruebe autenticidad.

Para E34: ejemplos y reglas oficiales de parciales/acumuladas por concepto,
cantidad/tasa/impuesto, descuentos, exenciones, redondeos y restricciones de plazo.
Indicar pruebas necesarias para aplicar/rechazar una reserva tras UNKNOWN_RESULT.
Nuestro receptor público y envío fiscal continúan deshabilitados.

## Referencias públicas consultadas

- [E31](https://developer.alanube.co/reference/createinvoicefiscals)
- [E32](https://developer.alanube.co/reference/createinvoices)
- [E34](https://developer.alanube.co/reference/createcreditnotes)
- [Consulta E31](https://developer.alanube.co/reference/checkinvoicefiscals)
- [Consulta E32](https://developer.alanube.co/reference/checkinvoices)
- [Consulta E34](https://developer.alanube.co/reference/checkcreditnotes)
- [Autenticación webhook DOM](https://developer.alanube.co/changelog/api-fe-dom-mejoras-en-lo-webhooks-para-notificaciones-de-documentos-electr%C3%B3nicos)
- [Certificación](https://developer.alanube.co/docs/proceso-de-certificaci%C3%B3n)

No se envió esta solicitud, no se registraron compañías y no se contactó DGII.
