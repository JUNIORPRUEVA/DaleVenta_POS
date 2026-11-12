# Estrategia de conversión — web pública FullPOS Cloud

Documento de trabajo de la Fase 1 (sitio estático). No es un canal de venta: explica
qué se pide en cada zona, por qué se pide así y qué se puede medir cuando exista
analítica. **No contiene métricas inventadas.**

## 1. Principio

> Una sola promesa (probar FullPOS Cloud 7 días sin tarjeta) y varias formas de decirla
> según el momento del visitante.

El visitante no llega al sitio con la misma intención en el hero que al final de la
página ni en la barra del móvil. Repetir el mismo botón en todas partes gasta la
atención; variar el verbo la conserva.

## 2. Embudo y CTA por zona

Solo hay **una accion principal por vista** y **una sola puerta de entrada** (`/registro`).
El resto de acciones se presentan como enlace con flecha o como accion discreta, para
que el visitante no vea diez botones pidiendo lo mismo.

| Zona | Elemento | Texto | Intención |
| --- | --- | --- | --- |
| Header | Boton primario | **Empezar gratis** | Visitante frio, bajo compromiso |
| Header | Enlace de texto | **Ingresar** | Cliente que ya tiene cuenta |
| Hero | Boton primario | **Crear mi cuenta gratis** | Primera toma de contacto |
| Hero | Enlace con flecha | **Ver precios** | Quien compara antes de decidir |
| Planes | Boton por tarjeta | **Probar Básico / Negocio / Pro / Empresa 7 días** | Nombra el plan: elimina la duda de "¿cuál me toca?" |
| Funciones | Enlace con flecha | **Ver el detalle de las funciones** | Profundizar sin salir del embudo |
| Descargas | Accion discreta por fila | **Disponible ahora / Instalador / App móvil** | Abre el diálogo de cuenta, no compite con el CTA |
| Cierre | Boton primario | **Empezar gratis hoy** | Decision final |
| Cierre | Enlace dentro de la nota | **Hablar por WhatsApp** | Salida para quien no está listo |
| Barra movil | Boton primario + enlace | **Empezar gratis** / **Precios** | Persistente, dos palabras |
| Formulario | Boton primario | **Crear mi cuenta · 7 días gratis** | Repite la promesa antes del clic |

Variedad sin ruido: se usan cinco textos distintos (Empezar gratis, Crear mi cuenta
gratis, Probar X 7 días, Empezar gratis hoy, Crear mi cuenta · 7 días), pero el destino
es siempre el mismo.

## 3. Microcopy que sostiene el CTA

- `7 días gratis · sin tarjeta · activación por WhatsApp` bajo el botón del hero.
- Chip **7 días gratis** dentro de cada tarjeta de plan (no oculto en letra pequeña).
- Línea **¿Para quién es?** en cada plan, para que el visitante se reconozca.
- Bloque **Todos los planes incluyen** con seis certezas, incluido "datos separados
  por empresa".
- Nota de transparencia sobre límites: se confirman al activar la licencia; la
  activación es por WhatsApp; no hay cobro automático desde la web.

## 4. Reductores de riesgo (en orden de aparición)

1. Sin tarjeta (hero y planes).
2. Sin instalación obligatoria: la web/PWA funciona de inmediato.
3. Los mismos datos en todos los dispositivos.
4. Datos aislados por empresa.
5. Soporte humano por WhatsApp con horario visible.
6. e-CF declarado como módulo aparte y opcional (evita expectativas falsas).
7. Salida lateral siempre disponible: "Escribir por WhatsApp" para quien no está listo
   para registrarse.

## 5. Jerarquía visual (qué se ve primero)

1. Hero: promesa + una acción principal.
2. **Planes** justo después del hero — el usuario pidió que fueran protagonistas, y en
   un POS la duda número uno es el precio.
3. Pasos (cómo empieza): reduce la incertidumbre operativa.
4. Funciones: refuerza lo que ya vio en precios.
5. Producto en uso (showcase) y descargas.
6. FAQ: objeciones finales.
7. Cierre con `Iniciar gratis hoy`.

## 6. Qué medir cuando exista analítica

Sin inventar datos; solo qué evento conviene instrumentar:

- Clic en CTA por zona (`header`, `hero`, `plan:<id>`, `steps`, `final`, `mobile`).
- Inicio de formulario en `/registro` y abandono por campo.
- Clic en "Escribir por WhatsApp" (señal de intención alta sin registro).
- Clic en "Descargar" y elección entre las dos opciones del diálogo.
- Profundidad de scroll hasta `#planes` y hasta FAQ.

Con eso se decide qué variante de CTA promover, sin cambiar la promesa.

## 7. Límites explícitos de esta fase

- Los formularios son **solo interfaz** (`data-phase="2"`): no envían datos todavía.
- No hay enlaces de descarga oficiales: `url: null` abre la opción de pedir el enlace
  por WhatsApp en lugar de inventar una URL.
- No se publican límites de plan ni condiciones fiscales que no estén confirmadas.
