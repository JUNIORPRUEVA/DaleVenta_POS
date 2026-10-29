# Instalación de secretos en EasyPanel / Docker Swarm — auditoría y mecanismos válidos

Verificado en el VPS `srv902744` (Docker **28.3.0**, Swarm de 1 nodo). Solo lectura.

---

## 1. Evidencia (HECHO)

```text
docker service update --help | grep -c -- "--env-file"   -> 0
docker service create --help | grep -c -- "--env-file"   -> 1
docker service update --help | grep -E "^\s+--(env|secret|mount)"
  --env-add list      Add or update an environment
  --env-rm list       Remove an environment variable
  --mount-add mount   Add or update a mount on a service
  --mount-rm mount    Remove a mount by its target path
  --secret-add secret Add or update a secret on a service
  --secret-rm list    Remove a secret
```

**Conclusión: `docker service update --env-file` NO existe.** Cualquier plan que lo
use falla. (Corrijo aquí la propuesta de la entrega anterior: era incorrecta.)

Además:

- `docker secret ls` funciona y está **vacío** (0 secretos, 0 configs).
- `docker volume ls` usa nombres hash para los volúmenes de EasyPanel.
- EasyPanel guarda su estado en `/etc/easypanel` (`data`, `projects`, `traefik`…).
- Redes overlay por proyecto: `easypanel`, `easypanel-fullpos`, `easypanel-ventas`,
  `easypanel-daleventapos`, `easypanel-altomamita`, `easypanel-altomamita-uat`.

## 2. Los tres mecanismos posibles

| Mecanismo | Cómo se instala | Ventaja | Riesgo / límite |
| --- | --- | --- | --- |
| **A. EasyPanel (UI)** | Pegar variables en el panel del servicio | Enrutado y TLS ya resueltos por el panel; sin editar `main.yaml` | Los valores pasan por el navegador; quedan como env en la especificación del servicio |
| **B. `docker service create --env-file`** | `scp` del archivo a `/root/…` (chmod 600) + `--env-file` | Sin valores en argv ni en el historial | Solo sirve al **crear** el servicio; para cambiarlos hay que recrearlo o usar `--env-add` (que sí expone el valor en argv) |
| **C. Docker secrets** | `docker secret create <nombre> -` leyendo de **stdin** + `--secret-add` | El valor **no** queda en la especificación del servicio (solo el nombre) | La app lee únicamente `process.env`: requiere un entrypoint que exporte `$(cat /run/secrets/<name>)` |

### Prohibido en cualquier caso

- `docker service update --env-add CLAVE=valor` (el valor sería visible en `ps` e historial).
- `docker stack deploy` con secretos en el YAML versionado.
- Escribir secretos en un `.env` dentro de un repositorio.
- Pasar el archivo de credenciales como argumento de un comando.

## 3. Recomendación

**Opción A para el despliegue inicial** (es como operan hoy los servicios del VPS:
las credenciales viven como env de servicio, y el enrutado lo gestiona EasyPanel
sin tocar `main.yaml`), con estas condiciones:

1. Proyecto nuevo `guardian-uat`, nunca editar los servicios existentes.
2. Un valor por variable, pegado directamente en el panel; nunca en un chat o ticket.
3. Terminar con `docker service inspect` mostrando **solo nombres** (como el
   procedimiento de auditoría ya usado), nunca `Env` completo.
4. Rotación documentada en `docs/guardian/SECRET_ROTATION.md` (rotar el
   `GUARDIAN_PLATFORM_TOKEN` exige cambiar el valor en **los dos** servicios:
   Fullpos UAT y Appyra UAT, y reiniciar ambos).

**Opción C** queda como endurecimiento posterior si se acepta un entrypoint
`sh -c 'export GUARDIAN_WA_CLOUD_TOKEN=$(cat /run/secrets/guardian_wa_token); exec node dist/main.js'`.
Es la única que evita el valor en la especificación del servicio.

## 4. Canal de transferencia previsto (cuando se autorice)

```powershell
# El archivo ya está en C:\Users\pc\.guardian-uat\ (ACL restringida)
scp -i "C:\Users\pc\.ssh\daleventas_codex" `
    "C:\Users\pc\.guardian-uat\fullpos-backend.env" `
    root@31.97.99.70:/root/.guardian-uat/fullpos-backend.env
```

- `scp` cifra el contenido y **no** imprime valores.
- En el VPS: `chmod 600`, `chown root`, y borrado del archivo tras crear el servicio (`shred -u`).
- Solo se usa con `docker service create --env-file` (opción B) o para pegar en el panel (opción A).
- **Nada de esto se ha ejecutado.**

## 5. Auditoría posterior obligatoria

Tras cualquier instalación, comprobar sin leer valores:

```bash
for s in guardian-uat-api guardian-uat-workers guardian-uat-watchdog; do
  docker service inspect "$s" --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
    | awk -F= '/^[A-Za-z_][A-Za-z0-9_]*=/{k=$1; v=substr($0,length(k)+2); printf "%s %s\n", k, (length(v)>0?"SET":"EMPTY")}'
done
```
