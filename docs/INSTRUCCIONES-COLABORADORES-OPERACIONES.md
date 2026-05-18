# 📋 INSTRUCCIONES PARA COLABORADORES - OPERACIONES FULLTECH

**Última actualización:** Mayo 2026  
**Responsable:** Equipo de Operaciones

---

## 📌 TABLA DE CONTENIDOS

1. [Roles y Responsabilidades](#roles-y-responsabilidades)
2. [Estados y Transiciones (IMPORTANTE)](#estados-y-transiciones)
3. [Instrucciones por Rol](#instrucciones-por-rol)
4. [Flujos Diarios Paso a Paso](#flujos-diarios-paso-a-paso)
5. [Checklist Diario](#checklist-diario)
6. [Preguntas Frecuentes](#preguntas-frecuentes)

---

## 🎯 ROLES Y RESPONSABILIDADES

### 👨‍💼 ADMINISTRADOR (ADMIN) / ASISTENTE DE OPERACIONES

**¿Qué puede hacer?**
- ✅ Ver todas las órdenes y servicios del sistema
- ✅ Crear nuevas órdenes de servicio
- ✅ Asignar técnicos a órdenes
- ✅ Cambiar estados de órdenes
- ✅ Cambiar fases de trabajo
- ✅ Aprobar cambios de técnico
- ✅ Cancelar órdenes
- ✅ Ver reportes y dashboard
- ✅ Gestionar garantías
- ✅ Editar información de clientes

**Responsabilidades principales:**
1. Asegurar que todas las órdenes tengan un técnico asignado
2. Monitorear el avance diario de todas las órdenes
3. Resolver conflictos o problemas técnicos
4. Coordinar cambios de técnico o reprogramaciones
5. Aprobar cambios de costo o extras
6. Mantener la información actualizada

---

### 🔧 TÉCNICO (OPERACIONES TÉCNICO)

**¿Qué puede hacer?**
- ✅ Ver órdenes asignadas a su nombre
- ✅ Cambiar el estado de "EN PROCESO" ↔ "PAUSA"
- ✅ Subir evidencias (fotos/videos)
- ✅ Reportar problemas técnicos
- ✅ Cambiar la fase de trabajo (ej. reserva → levantamiento)
- ✅ Registrar horas trabajadas
- ✅ Solicitar cambios de técnico (si es necesario)
- ✅ Acceder a datos del cliente (teléfono, dirección)
- ✅ Ver órdenes en garantía

**Responsabilidades principales:**
1. Marcar "EN PROCESO" cuando comienza a trabajar
2. Marcar "PAUSA" si deja el trabajo para continuar otro día
3. Marcar "EN PROCESO" nuevamente cuando retoma el trabajo
4. Subir evidencias después de cada paso importante
5. Actualizar el reporte técnico con detalles del trabajo
6. Notificar a operaciones si hay problemas

---

### 💰 VENDEDOR / ASESOR DE VENTAS

**¿Qué puede hacer?**
- ✅ Ver las órdenes que él/ella creó
- ✅ Ver estado de sus propias órdenes
- ✅ Cambiar información del cliente (hasta que se asigne técnico)
- ✅ Cancionar órdenes propias
- ✅ Descargar evidencias y reportes

**Responsabilidades principales:**
1. Crear órdenes con información correcta del cliente
2. Seleccionar el tipo de servicio apropiado
3. Asegurar que el cliente firme la orden
4. Contactar al cliente para confirmar la orden

---

## 🔄 ESTADOS Y TRANSICIONES (IMPORTANTE)

### Estados Principales del Servicio

```
RESERVADO
    ↓
LEVANTAMIENTO
    ↓
AGENDADO
    ↓
EN PROCESO ←→ PAUSA
    ↓
FINALIZADO
    ↓
GARANTÍA (si aplica)
    ↓
CERRADO
```

### ¿Cuándo cambiar de estado?

| Estado | Significa | Acción Requerida |
|--------|-----------|-----------------|
| **RESERVADO** | Se creó la orden, espera confirmación | Admin debe asignar técnico |
| **LEVANTAMIENTO** | Técnico está haciendo levantamiento inicial | Técnico marca "EN PROCESO" |
| **AGENDADO** | Orden programada para una fecha específica | Técnico se prepara para el día |
| **EN PROCESO** 🔴 | Técnico está trabajando AHORA | Subir evidencias regularmente |
| **PAUSA** ⏸️ | Se pausó el trabajo, continúa otro día | Guardar estado, fotografías, notas |
| **FINALIZADO** ✅ | Trabajo completado, espera cierre | Admin revisa y cierra |
| **GARANTÍA** | Dentro del período de garantía | Registrar incidencias |
| **CERRADO** 🔒 | Orden completamente cerrada | No se puede cambiar |

---

## 📖 INSTRUCCIONES POR ROL

### 👨‍💼 PARA EL ADMINISTRADOR / ASISTENTE

#### Diariamente:

1. **Al iniciar el día (8:00 AM)**
   - Abre el dashboard de Operaciones
   - Revisa todas las órdenes en estado "AGENDADO" para hoy
   - Verifica que todas tengan técnico asignado
   - Si falta asignación → asigna técnico disponible
   - Notifica al técnico: "Tienes orden XYZ para hoy"

2. **Durante el día (cada 2 horas)**
   - Revisa órdenes "EN PROCESO"
   - Verifica que tengan evidencias subidas
   - Si no hay evidencias → contacta al técnico
   - Revisa si hay órdenes en "PAUSA" sin razón documentada

3. **Cuando técnico marca "FINALIZADO"**
   - Revisa reporte técnico completo
   - Verifica que haya evidencias (fotos antes/después)
   - Revisa si el cliente pagó o no
   - Decide:
     - ✅ Si todo está correcto → marca "CERRADO"
     - ❌ Si falta algo → devuelve a "EN PROCESO" con nota

4. **Fin del día (5:00 PM)**
   - Reporte de órdenes cerradas hoy
   - Identifica órdenes atrasadas
   - Planifica para mañana

#### Si técnico marca "PAUSA":
```
1. Revisa la nota del técnico
2. Verifica que hay evidencias subidas
3. Calcula tiempo trabajado
4. Documenta por qué se pausó
5. Si es por problema → busca solución
6. Coordina retoma para mañana
```

---

### 🔧 PARA EL TÉCNICO

#### Instrucciones paso a paso para cada orden:

**PASO 1: Antes de empezar**
- [ ] Verifica que la orden esté asignada a tu nombre
- [ ] Lee toda la información del cliente (teléfono, dirección, tipo de servicio)
- [ ] Revisa los requisitos especiales o notas

**PASO 2: Cuando llegas al cliente**
- [ ] Saluda, preséntate y verifica datos del cliente
- [ ] Toma foto de la dirección (para evidencia)
- [ ] Comienza el trabajo y **marca orden en "EN PROCESO"** en la app
- [ ] Sube foto inicial del lugar

**PASO 3: Durante el trabajo**
- [ ] Trabaja de acuerdo al plan técnico
- [ ] Toma fotos/videos del progreso regularmente
- [ ] Sube evidencias cada 30-60 minutos
- [ ] Mantén actualizado el estado en la app
- [ ] Si encuentras problemas → documenta en notas

**PASO 4: Si necesitas parar y continuar mañana**
- [ ] Toma foto del estado actual
- [ ] **Marca orden en "PAUSA"** en la app
- [ ] Escribe nota clara: "Falta XXX para terminar, retomamos mañana"
- [ ] Sube todas las evidencias
- [ ] Cierra la sesión

**PASO 5: Cuando retomas el trabajo**
- [ ] Abre la app
- [ ] Encuentra la orden que estaba en "PAUSA"
- [ ] **Marca nuevamente en "EN PROCESO"**
- [ ] Continúa donde dejaste
- [ ] Sube nuevas evidencias

**PASO 6: Cuando terminas el trabajo**
- [ ] Toma foto final de lo completado
- [ ] Obtén firma del cliente (si aplica)
- [ ] **Marca orden en "FINALIZADO"**
- [ ] Escribe reporte detallado de qué se hizo
- [ ] Sube todas las evidencias
- [ ] Verifica que no falte nada

**PASO 7: Después de finalizar**
- [ ] Admin revisa tu trabajo
- [ ] Si admin marca "CERRADO" → orden completa ✅
- [ ] Si admin devuelve a "EN PROCESO" → se vuelve a trabajar

---

#### Cambios de Fase (si aplica)

Si el trabajo cubre varias fases:

```
RESERVA
   ↓ (después de levantamiento inicial)
LEVANTAMIENTO
   ↓ (cuando empiezas instalación)
INSTALACIÓN
   ↓ (cuando terminas instalación)
MANTENIMIENTO (si aplica)
   ↓ (si hay garantía)
GARANTÍA
```

**Instrucción:** Cuando cambies de fase, actualiza en la app y notifica a admin.

---

### 💰 PARA EL VENDEDOR

#### Cuando creas una orden:

1. **Información del cliente**
   - Nombre completo (sin abreviaturas)
   - Teléfono correcto (verifica digitos)
   - Correo (si tiene)
   - Dirección exacta (calle, número, ciudad)

2. **Tipo de servicio**
   - Selecciona: Instalación, Mantenimiento, Garantía, POS, Otro
   - Describe qué equipo o servicio

3. **Detalles de la orden**
   - Escribe qué necesita el cliente claramente
   - Notas especiales (ej. "cliente es difícil", "debe ir entre 9-11 AM")
   - Costo estimado

4. **Firma**
   - Cliente debe firmar la orden
   - Toma foto de la firma

5. **Después de crear**
   - Notifica a admin que hay orden nueva
   - Proporciona teléfono del cliente
   - Ten disponible el correo para follow-up

---

## 📅 FLUJOS DIARIOS PASO A PASO

### Flujo Completo de una Orden (de inicio a fin)

```
DÍA 1: CREACIÓN
├─ Vendedor crea orden en sistema
├─ Cliente firma
└─ Admin revisa y asigna técnico

DÍA 2: ASIGNACIÓN Y LEVANTAMIENTO
├─ Técnico recibe notificación
├─ Técnico va al cliente
├─ Técnico marca "EN PROCESO"
├─ Técnico hace levantamiento inicial
├─ Técnico sube fotos
└─ Técnico marca orden en "LEVANTAMIENTO"

DÍA 3-4: PAUSA (si es necesario)
├─ Técnico marca "PAUSA" al terminar el día
├─ Técnico anota qué falta hacer
├─ Admin revisa estado
└─ Técnico retoma al día siguiente

DÍA N: CONTINUACIÓN
├─ Técnico marca "EN PROCESO" nuevamente
├─ Técnico continúa trabajo
└─ Técnico sube evidencias

DÍA FINAL: FINALIZACIÓN
├─ Técnico marca "FINALIZADO"
├─ Técnico sube reporte completo
├─ Admin revisa todo
└─ Admin marca "CERRADO"

DESPUÉS: GARANTÍA (si aplica)
├─ Si hay problemas → "GARANTÍA"
├─ Técnico resuelve
└─ Admin cierra nuevamente
```

---

### Escenario: Técnico se enferma o no puede continuar

```
SITUACIÓN: Técnico X no puede continuar orden
├─ Técnico marca "PAUSA" en la app
├─ Técnico avisa a Admin inmediatamente (llamada/whatsapp)
├─ Técnico escribe nota clara: "No puedo continuar por: RAZÓN"
├─ Admin revisa órdenes en PAUSA
├─ Admin asigna técnico diferente
├─ Nuevo técnico revisa notas y evidencias del anterior
└─ Nuevo técnico marca "EN PROCESO" y continúa

IMPORTANTE: No dejes orden en PAUSA sin avisar a admin
```

---

### Escenario: Cliente pide cambiar técnico

```
SITUACIÓN: Cliente no quiere técnico X
├─ Técnico X marca "PAUSA" y avisa a Admin
├─ Cliente explica por qué quiere cambio
├─ Admin evalúa si cambio es razonable
├─ Si SÍ → admin asigna nuevo técnico y desasigna al anterior
├─ Si NO → admin habla con cliente para resolver
└─ Nuevo técnico retoma desde donde dejó técnico X
```

---

### Escenario: Descubrimiento de problema importante

```
SITUACIÓN: Técnico descubre problema no previsto
├─ Técnico marca orden en "PAUSA"
├─ Técnico escribe nota detallada del problema
├─ Técnico sube fotos del problema
├─ Técnico contacta a Admin inmediatamente
├─ Admin revisa notas y fotos
├─ Admin coordina con cliente si hay costo extra
├─ Admin y técnico planean próximos pasos
└─ Técnico retoma cuando esté aclarado
```

---

## ✅ CHECKLIST DIARIO

### Para ADMIN al iniciar (8:00 AM)

- [ ] Entro al dashboard de Operaciones
- [ ] Reviso órdenes "AGENDADO" para hoy
- [ ] Verifico que todas tengan técnico asignado
- [ ] Reviso órdenes "EN PROCESO" de ayer que sigan activas
- [ ] Contacto a técnicos sin movimiento en 2 horas
- [ ] Reviso órdenes en "PAUSA" sin razón documentada

### Para ADMIN cada 2 horas

- [ ] Reviso estado de órdenes "EN PROCESO"
- [ ] Verifico que haya evidencias subidas
- [ ] Contacto a técnicos si falta movimiento
- [ ] Reviso problemas reportados

### Para ADMIN al cerrar (5:00 PM)

- [ ] Cuento órdenes cerradas hoy
- [ ] Identifico órdenes atrasadas
- [ ] Notifico a gerencia si hay problemas
- [ ] Planeo asignaciones para mañana

### Para TÉCNICO al iniciar (antes de salir)

- [ ] Entro a la app
- [ ] Busco mi orden del día
- [ ] Reviso toda la información del cliente
- [ ] Reviso notas de admin si hay
- [ ] Preparo herramientas necesarias
- [ ] Confirmo dirección correcta

### Para TÉCNICO cuando llega al cliente

- [ ] Verifico identidad del cliente
- [ ] Tomo foto de la dirección
- [ ] Marco orden en "EN PROCESO"
- [ ] Empiezo a subir evidencias
- [ ] Trabajo según plan

### Para TÉCNICO cuando se va (pausa o fin)

- [ ] Tomo foto del estado actual
- [ ] Subo todas las evidencias
- [ ] Escribo nota sobre qué hice y qué falta
- [ ] Si es pausa → marco "PAUSA"
- [ ] Si es fin → marco "FINALIZADO"
- [ ] Cierre sesión

---

## ❓ PREGUNTAS FRECUENTES

### P: ¿Qué significa exactamente "EN PROCESO"?

**R:** Significa que AHORA el técnico está trabajando en esa orden. No es "voy a trabajar", es "estoy trabajando". Por eso debe estar el técnico en el lugar del cliente.

---

### P: ¿Puedo tener varias órdenes "EN PROCESO" al mismo tiempo?

**R:** NO. Solo una orden debe estar "EN PROCESO" por técnico a la vez. Si cambias de orden, marca la anterior como "PAUSA" o "FINALIZADO" primero.

---

### P: Si tengo que parar a las 3 PM para ir a otra cita, ¿qué hago?

**R:**
1. Marca orden actual como "PAUSA"
2. Escribe: "Pausada a las 3 PM por cita personal. Retomo a las 4 PM"
3. Sube fotos de lo hecho
4. Cuando regreses → marca "EN PROCESO" nuevamente

---

### P: ¿Cada cuánto debo subir evidencias?

**R:** **Cada 30-60 minutos** mientras estés trabajando. O al menos:
- Foto inicial cuando llegas
- Fotos durante trabajo importante
- Foto final antes de pausa o finalización

---

### P: ¿Qué pasa si el cliente no está en casa?

**R:**
1. Toma foto de la puerta
2. Marca orden en "PAUSA"
3. Escribe: "Cliente no estaba. Reprogramar para FECHA"
4. Contacta inmediatamente a Admin
5. Admin contacta cliente para nueva fecha

---

### P: ¿Puedo marcar orden "FINALIZADO" sin terminar el trabajo?

**R:** **NO**. Si marques "FINALIZADO", admin asumirá que terminaste. Si después resulta que falta trabajo, habría complicación con cliente.

---

### P: ¿Qué si descubro problema técnico importante?

**R:**
1. Marca orden en "PAUSA" inmediatamente
2. Toma fotos del problema
3. Escribe nota detallada
4. Llama a Admin (no esperes)
5. Admin coordina próximos pasos

---

### P: ¿Puedo ver órdenes que no me asignaron?

**R:** 
- **TÉCNICO**: Solo ves las tuyas (a menos que Admin active permiso especial)
- **ADMIN**: Ves todo
- **VENDEDOR**: Solo ves las que creaste

---

### P: ¿Si trabajo después del horario normal, cómo lo registro?

**R:**
1. Continúa en "EN PROCESO"
2. Sube evidencias cada hora
3. Cuando termines → marca "FINALIZADO"
4. Admin verá marca de tiempo en sistema

---

### P: ¿Qué si pauso una orden pero cambio de parecer y quiero terminarla hoy?

**R:**
1. Abre la orden en "PAUSA"
2. Marca nuevamente "EN PROCESO"
3. Continúa trabajo
4. Cuando termines → marca "FINALIZADO"

---

### P: ¿Cuánto tiempo puede estar una orden en "PAUSA"?

**R:** 
- **Normal**: máximo 2-3 días
- **Si hay problema**: documentar con Admin
- **Pasado el tiempo límite**: Admin contacta para resolver

---

## 🚨 IMPORTANTE - RESUMEN DE REGLAS DE ORO

```
1. UNA orden por técnico en "EN PROCESO" a la vez
2. Cuando empiezas → marca "EN PROCESO"
3. Cuando paras → marca "PAUSA" (no dejes sin marcar)
4. Cuando retomas → marca "EN PROCESO" de nuevo
5. Cuando terminas → marca "FINALIZADO"
6. Cada cambio de estado = evidencia que lo justifique
7. No marques "FINALIZADO" si no está completamente listo
8. Si hay problema → avisa a Admin INMEDIATAMENTE
9. Documenta SIEMPRE por qué cambias de estado
10. Sube fotos/evidencias cada hora mínimo
```

---

## 📞 CONTACTOS IMPORTANTES

| Rol | Responsable | Contacto | Función |
|-----|-------------|----------|---------|
| **Administrador** | [Nombre] | [Teléfono] | Coordina todo |
| **Jefe Operaciones** | [Nombre] | [Teléfono] | Supervisa |
| **Técnico Líder** | [Nombre] | [Teléfono] | Apoya técnicos |

---

## 📝 NOTAS FINALES

- Este documento se actualiza regularmente
- Si encuentras que algo no está claro → avisa a Admin
- Cumplir estos pasos = satisfacción del cliente
- El trabajo en equipo hace que todo funcione
- Calidad + velocidad = éxito

---

**Aprobado por:** Equipo de Operaciones  
**Fecha de vigencia:** Indefinida  
**Próxima revisión:** Cada trimestre
