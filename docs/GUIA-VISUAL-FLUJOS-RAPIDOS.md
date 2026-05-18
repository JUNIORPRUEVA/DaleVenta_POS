# 🎯 GUÍA VISUAL - FLUJOS Y CHECKLISTS RÁPIDOS

Este documento es una referencia visual rápida para el trabajo diario.

---

## 1️⃣ FLUJO RÁPIDO - TÉCNICO (QUÉ HACER HOY)

### Cuando recibes una orden asignada:

```
┌─────────────────────────────────────────┐
│ ORDEN ASIGNADA A MÍ                     │
│ (Estado: AGENDADO)                      │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ 1. LEO toda la información             │
│    • Cliente: nombre, teléfono         │
│    • Dirección exacta                  │
│    • Tipo de trabajo                   │
│    • Notas especiales de admin         │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ 2. VOY AL CLIENTE                       │
│    • Preparo herramientas              │
│    • Confirmo dirección                │
│    • Salgo con tiempo                  │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│ 3. LLEGO AL CLIENTE                     │
│    • Tomo foto de dirección            │
│    • Me presento                       │
│    • Verifico datos                    │
└────────────┬────────────────────────────┘
             │
             ▼
╔═════════════════════════════════════════╗
║ 4. MARCO ORDEN EN "EN PROCESO"   ✅✅✅   ║
║    (AHORA estoy trabajando)             ║
╚════════════┬════════════════════════════╝
             │
             ▼
┌─────────────────────────────────────────┐
│ 5. TRABAJO Y SUBO EVIDENCIAS            │
│    • Foto inicial                      │
│    • Cada 30-60 minutos: nuevas fotos  │
│    • Actualizo notas si hay problemas  │
└────────────┬────────────────────────────┘
             │
             ▼
             ├─── ¿TERMINO HOY? ───┐
             │                      │
             ▼                      ▼
    ┌──────────────────┐   ┌──────────────────┐
    │ SÍ, TERMINÉ      │   │ NO, DEJO PAUSA   │
    │                  │   │                  │
    │ ➤ Foto final     │   │ ➤ Foto actual    │
    │ ➤ Reporte       │   │ ➤ Nota clara     │
    │ ➤ "FINALIZADO"  │   │ ➤ "PAUSA"        │
    │ ➤ Firma cliente │   │ ➤ Evidencias     │
    └────────┬─────────┘   └────────┬─────────┘
             │                      │
             ▼                      ▼
    ┌──────────────────┐   ┌──────────────────┐
    │ ESPERO REVISIÓN  │   │ SALGO DEL LUGAR  │
    │ DE ADMIN         │   │                  │
    │                  │   │ MAÑANA:          │
    │ Admin marca:     │   │ ➤ Abro en app    │
    │ ✅ "CERRADO"     │   │ ➤ "EN PROCESO"   │
    │ ❌ "VUELVE A     │   │ ➤ Continúo       │
    │    PROCESO"      │   │                  │
    └──────────────────┘   └──────────────────┘
```

---

## 2️⃣ FLUJO RÁPIDO - ADMIN (QUÉ REVISAR HOY)

### Checklist cada 2 horas:

```
┌─────────────────────────────────────────┐
│ 08:00 AM - INICIO DEL DÍA              │
└────────────┬────────────────────────────┘
             │
      ┌──────┴────────┬────────────┬────────────┐
      ▼               ▼            ▼            ▼
  Órdenes       Órdenes       Órdenes      Órdenes
  AGENDADO      EN PROCESO    PAUSA        SIN TECNICO
  para hoy      de ayer       sin razón    ASIGNADO
      │               │            │            │
      └──────┬────────┴────────┬───┴────────┬──┘
             │                 │            │
             ▼                 ▼            ▼
   ✅ Verificar        ✅ Hay       ✅ Asignar
      técnico          evidencias    técnico
      asignado         subidas?      disponible
             │                 │            │
             ▼                 ▼            ▼
   📞Notificar   ❌ No hay      📞Notificar
      técnico        evidencias   técnico
                     ➜ Contactar
                        técnico
```

### Estados a revisar regularmente:

```
┌──────────────────────────────────────────────────────┐
│ ESTADO         │ FRECUENCIA    │ ACCIÓN             │
├──────────────────────────────────────────────────────┤
│ AGENDADO       │ Mañana previo  │ Verificar técnico  │
│ EN PROCESO     │ Cada 2 horas   │ Revisar evidencias │
│ PAUSA          │ Cada 4 horas   │ Verificar progreso │
│ FINALIZADO     │ Inmediato      │ Revisar calidad    │
│ EN GARANTÍA    │ Diario         │ Revisar estado     │
└──────────────────────────────────────────────────────┘
```

---

## 3️⃣ TABLA DE ESTADOS RÁPIDA

### Significado de cada estado:

```
╔════════════════════════════════════════════════════════════╗
║ ESTADO          │ SIGNIFICA           │ QUIÉN ACTÚA        ║
╠════════════════════════════════════════════════════════════╣
║ 📌 RESERVADO    │ Orden creada, sin   │ Admin/Vendedor     ║
║                 │ técnico aún         │                    ║
╠════════════════════════════════════════════════════════════╣
║ 📋 LEVANTAMIENTO│ Técnico evalúa      │ Técnico + Admin    ║
║                 │ que hay que hacer   │                    ║
╠════════════════════════════════════════════════════════════╣
║ 📅 AGENDADO     │ Orden programada    │ Admin              ║
║                 │ para fecha X        │                    ║
╠════════════════════════════════════════════════════════════╣
║ 🔴 EN PROCESO   │ AHORA estoy         │ Técnico (trabajando║
║                 │ trabajando          │ en el lugar)       ║
╠════════════════════════════════════════════════════════════╣
║ ⏸️  PAUSA        │ Pausé el trabajo,   │ Técnico (en pausa, ║
║                 │ continúo mañana     │ fuera del lugar)   ║
╠════════════════════════════════════════════════════════════╣
║ ✅ FINALIZADO   │ Terminé el trabajo, │ Técnico           ║
║                 │ espero revisión      │                    ║
╠════════════════════════════════════════════════════════════╣
║ 🔒 CERRADO      │ Orden completada    │ Admin              ║
║                 │ y archivada         │                    ║
╠════════════════════════════════════════════════════════════╣
║ 🛡️  GARANTÍA    │ Dentro del período  │ Técnico (si       ║
║                 │ de garantía         │ hay problemas)     ║
╚════════════════════════════════════════════════════════════╝
```

---

## 4️⃣ TRANSICIONES DE ESTADOS PERMITIDAS

### Cuándo puedo cambiar a cada estado:

```
SOLO TÉCNICO PUEDE CAMBIAR:
┌─────────────────────────────────────────┐
│ EN PROCESO  ←→  PAUSA                   │
│                                         │
│ (cambio directo entre estos dos)        │
└─────────────────────────────────────────┘

SOLO ADMIN PUEDE CAMBIAR:
┌─────────────────────────────────────────┐
│ RESERVADO ➜ LEVANTAMIENTO               │
│ LEVANTAMIENTO ➜ AGENDADO                │
│ AGENDADO ➜ EN PROCESO                   │
│ FINALIZADO ➜ CERRADO                    │
│ FINALIZADO ➜ EN PROCESO (si necesita    │
│              más trabajo)                │
└─────────────────────────────────────────┘

AMBOS PUEDEN (con restricciones):
┌─────────────────────────────────────────┐
│ EN PROCESO ➜ FINALIZADO                 │
│ (solo técnico, al terminar)             │
│                                         │
│ CUALQUIERA ➜ CANCELADO                  │
│ (en casos excepcionales)                │
└─────────────────────────────────────────┘
```

---

## 5️⃣ CHECKLIST DIARIO PARA IMPRIMIR/FOTOCOPIAR

### 📋 CHECKLIST DEL TÉCNICO

**Nombre:** _________________ **Fecha:** _________

```
ANTES DE SALIR:
□ Leo información de cliente (nombre, teléfono, dirección)
□ Verifico tipo de trabajo que debo hacer
□ Reviso notas especiales del admin
□ Preparo herramientas necesarias
□ Confirmo que orden está asignada a mi nombre

CUANDO LLEGO AL CLIENTE:
□ Tomo foto de la dirección/puerta
□ Me presento y verifico datos del cliente
□ Confirmo qué trabajo debo hacer
□ Marco orden en "EN PROCESO" en app

DURANTE EL TRABAJO:
□ Subo foto inicial
□ Trabajo según lo planificado
□ Cada 30-60 minutos: subo foto de progreso
□ Actualizo notas si hay cambios/problemas
□ Documentó cualquier descubrimiento importante

SI DEJO PAUSA AL FINAL DEL DÍA:
□ Tomo foto del estado actual
□ Escrito nota clara de qué falta
□ Subo todas las fotos
□ Marco orden en "PAUSA"
□ Aviso a admin si hay problema

SI TERMINO EL TRABAJO:
□ Tomo foto final
□ Obtengo firma del cliente (si aplica)
□ Escribo reporte completo
□ Subo todas las evidencias
□ Marco orden en "FINALIZADO"
□ Verifico que no falte nada
□ Espero revisión de admin

PROBLEMAS ENCONTRADOS:
□ Si hay problema importante: LLAMO A ADMIN INMEDIATAMENTE
□ Documento con foto y nota
□ Marco orden en PAUSA mientras se resuelve
```

---

### 📋 CHECKLIST DEL ADMIN

**Nombre:** _________________ **Fecha:** _________

```
08:00 AM - INICIO:
□ Entro al dashboard de operaciones
□ Reviso órdenes AGENDADO para hoy
□ Verifico que todas tengan técnico asignado
□ Contacto a técnicos sin asignación
□ Reviso órdenes EN PROCESO de ayer que sigan activas

10:00 AM:
□ Reviso estado de órdenes EN PROCESO
□ Verifico que haya evidencias subidas en últimas 2 horas
□ Contacto a técnicos sin movimiento
□ Reviso problemas reportados

12:00 PM:
□ Repito revisión de EN PROCESO
□ Verifico órdenes en PAUSA sin razón
□ Valido que todas tengan documentación

02:00 PM:
□ Reviso nuevas órdenes FINALIZADO
□ Evalúo calidad (evidencias, reporte, firma)
□ Decido: CERRADO o DEVOLVER A EN PROCESO

04:00 PM:
□ Repito ciclo de EN PROCESO
□ Reviso garantías activas
□ Planeo para mañana

05:00 PM - CIERRE:
□ Cuento órdenes cerradas hoy
□ Identifico órdenes atrasadas
□ Notifico a gerencia si hay problemas
□ Planeo asignaciones para mañana
□ Documento resumen del día
```

---

## 6️⃣ EJEMPLOS PRÁCTICOS DE CÓMO DOCUMENTAR

### Ejemplo 1: Técnico en proceso normal

```
Orden: OP-2026-05-18-001
Técnico: Juan García
Hora: 09:00 AM - Marco "EN PROCESO"

09:15 AM - Foto inicial de la instalación
09:45 AM - Instalación 50% completada, todo OK
10:15 AM - Instalación 90% completada
10:45 AM - Terminado, cliente firma, foto final

Reporte final:
"Se completó instalación de equipo POS modelo X200 
sin incidentes. Cliente satisfecho y pagó. 
Entrega de manuales completada."

Estado: FINALIZADO ✅
```

### Ejemplo 2: Técnico con pausa

```
Orden: OP-2026-05-18-002
Técnico: María López
Hora: 10:00 AM - Marco "EN PROCESO"

10:15 AM - Foto inicial, cliente presente
10:45 AM - Levantamiento de requisitos completado
11:15 AM - Material insuficiente, necesito ir a almacén

Nota: "Falta tubo especial de 2 pulgadas. Voy al 
almacén a buscarlo. Retomo en 1 hora."

Hora: 12:00 PM - Marco "PAUSA"
Foto: estado actual con lo hecho

---

MAÑANA:
Hora: 09:00 AM - Marco nuevamente "EN PROCESO"
09:15 AM - Continúo con tubo traído
10:00 AM - Instalación completada
Hora: 10:30 AM - Marco "FINALIZADO"
```

### Ejemplo 3: Técnico encuentra problema

```
Orden: OP-2026-05-18-003
Técnico: Carlos Rodríguez
Hora: 14:00 - Marco "EN PROCESO"

14:15 - Foto inicial
14:45 - PROBLEMA ENCONTRADO:
        Equipo anterior tiene falla de manufactura
        No puede ser reparado, necesita reemplazo

Nota: "Equipo NO reparable. Requiere reemplazo 
completo. Contacté a cliente, espera aprobación 
de admin para continuar."

Hora: 15:00 - Marco "PAUSA"

ADMIN REVISA:
- Nota clara ✅
- Fotos del problema ✅
- Cliente contactado ✅
- Espera resolución ✅

Admin coordina reemplazo, luego técnico continúa.
```

---

## 7️⃣ RESPUESTAS A DUDAS RÁPIDAS

### ¿Qué hago si...?

```
...el cliente no está en casa?
→ Foto de puerta
→ Nota: "Cliente no presente, llamar para reprogramar"
→ Marca PAUSA
→ Llama a admin inmediatamente

...descubro más trabajo del planeado?
→ Documenta qué descubriste
→ Toma foto
→ Marca PAUSA
→ Avisa a admin AHORA (no esperes)

...se me daña una herramienta?
→ Toma foto del daño
→ Avisa a admin
→ Admin gestiona reemplazo
→ Pausa orden si es necesario

...el cliente quiere cambio de técnico?
→ Marca PAUSA
→ Avisa a admin
→ Admin evalúa y decide
→ Nuevo técnico retoma

...trabajo más allá de las 5 PM?
→ Continúa EN PROCESO
→ Sigue subiendo fotos cada hora
→ Cuando termines → FINALIZADO
→ Admin verá que trabajaste tarde

...tengo varias órdenes asignadas?
→ Solo UNA en EN PROCESO a la vez
→ Las otras están en AGENDADO
→ Cuando termines una → pasa a la siguiente
→ Marca PAUSA si dejas inconclusa
```

---

## 8️⃣ CONTACTO RÁPIDO EN EMERGENCIAS

```
PROBLEMA TÉCNICO GRAVE:
📞 Jefe Operaciones: _______________
   Que espera: foto + nota + contexto

ORDEN SIN TÉCNICO:
📞 Admin: _______________
   Que espera: orden asignada en 30 min

CLIENTE ENOJADO:
📞 Jefe Operaciones: _______________
   Que espera: evaluación + plan de acción

CAMBIO DE TÉCNICO:
📞 Admin: _______________
   Que espera: documentación + autorización
```

---

## ✨ RESUMEN EN 3 PASOS (PARA RECORDAR SIEMPRE)

```
TÉCNICO:
1️⃣  Llego al cliente ➜ Marco "EN PROCESO"
2️⃣  Trabajo + subo fotos cada hora
3️⃣  Termino ➜ Marco "FINALIZADO" o "PAUSA"

ADMIN:
1️⃣  Mañana: verifico órdenes AGENDADO
2️⃣  Durante día: reviso EN PROCESO cada 2 horas
3️⃣  Cuando termina técnico: reviso y cierro
```

---

**Imprime esta página y mantenla en un lugar visible** 📌
