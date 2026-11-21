# Comandos de terminal ejecutados — Proyecto final DevOps

**Estudiante:** estudiante13
**Servidor:** `178.128.14.98` (usuario `estudiante13`)
**API:** http://178.128.14.98:8013/health
**Puerto PostgreSQL asignado:** 5445 — **no se usa** (la BD queda en la red interna en `5432`)

Este documento reúne, en orden, todos los comandos usados para preparar,
desplegar, verificar, escanear y monitorear el proyecto. Se ejecutaron desde
dos lugares:

- **Local (laptop):** `/home/craos6518/Documentos/Semestre 2/DevOps/Proyecto final/devops-final`
- **Servidor:** `/home/estudiante13/estudiante13/devops-final`

---

## 1. Verificación del entorno

### 1.1 Local

```bash
docker --version                 # Docker version 29.10.0
docker compose version           # Docker Compose version v5.7.1
git --version
gh auth status                   # sesión de GitHub activa
id                               # usuario en el grupo docker
docker info                      # daemon de Docker disponible
```

### 1.2 Servidor

```bash
ssh estudiante13@178.128.14.98
hostname                         # taller-utp
whoami                           # estudiante13
pwd                              # /home/estudiante13
docker --version                 # Docker version 29.7.2
docker compose version           # Docker Compose version v5.4.0
git --version
curl --version
id                               # groups=1013(estudiante13),998(docker)
free -m                          # memoria disponible
df -h /                          # espacio en disco
```

Herramientas de DevSecOps disponibles en el servidor:

```bash
for t in git curl gitleaks semgrep syft trivy hadolint python3; do
  printf "%s: " "$t"; command -v "$t" || echo "no"
done
```

---

## 2. Git y GitHub (fork y clonación)

### 2.1 Local: fork del repositorio base y clonación

```bash
mkdir -p "Proyecto final"
cd "Proyecto final"
gh repo fork jsansis-utp/devops-final --clone    # crea el fork y clona
cd devops-final
git remote -v                                   # origin = mi fork, upstream = docente
git branch -a
git log --oneline --graph --decorate
```

### 2.2 Servidor: clonación del fork

```bash
ssh estudiante13@178.128.14.98
mkdir -p ~/estudiante13
cd ~/estudiante13
git clone https://github.com/Craos6518/devops-final.git
cd devops-final
git log --oneline
git status -sb
```

---

## 3. Variables de entorno

### 3.1 Local

```bash
cd "Proyecto final/devops-final"
cp .env.example .env              # plantilla -> archivo real
openssl rand -base64 24 | tr -d '/+=' | cut -c1-24   # generar contraseña
nano .env                         # ESTUDIANTE, API_PORT, claves
chmod 600 .env                    # solo el dueño puede leerlo
git check-ignore -v .env          # confirmar que Git lo ignora
```

Contenido resultante (sin la contraseña real):

```env
ESTUDIANTE=estudiante13
API_PORT=8013
POSTGRES_DB=tareas
POSTGRES_USER=estudiante13
POSTGRES_PASSWORD=<clave_generada>
DB_HOST=db
DB_PORT=5432
```

### 3.2 Copia al servidor

```bash
# desde la laptop
scp .env estudiante13@178.128.14.98:~/estudiante13/devops-final/.env

# en el servidor
cd ~/estudiante13/devops-final
chmod 600 .env
ls -l .env                        # -rw------- estudiante13 estudiante13
grep -E "ESTUDIANTE|API_PORT|DB_" .env
```

---

## 4. Revisión previa del servidor compartido

```bash
ss -ltn | grep ":8013" || echo "puerto libre"
docker ps -a                                        # ver todos los contenedores
docker ps -a --filter "name=est13_"                 # posibles choques de nombre
docker compose ls                                   # proyectos Compose existentes
docker volume ls | grep estudiante13                # volúmenes previos
docker network ls | grep estudiante13               # redes previas
```

> Solo se detienen/eliminan contenedores con prefijo `est13_`. Los de otros
> estudiantes no se tocan.

---

## 5. Despliegue con Docker Compose

### 5.1 Validación del archivo

```bash
docker compose config               # ver configuración final resuelta
docker compose config -q            # validar sin imprimir (exit 0 = correcto)
```

### 5.2 Construcción y arranque

```bash
# local (prueba previa)
docker compose up -d --build

# servidor
cd ~/estudiante13/devops-final
docker compose up -d --build
```

### 5.3 Estado de los servicios

```bash
docker compose ps
docker compose ls
docker volume ls | grep estudiante13
docker network ls | grep estudiante13
docker ps --filter name=est13_
docker inspect est13_api --format '{{.State.Health.Status}}'
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
```

Resultado esperado:

```
NAME        STATUS                    PORTS
est13_api   Up ... (healthy)          0.0.0.0:8013->5000/tcp
est13_db    Up ... (healthy)          5432/tcp
```

---

## 6. Verificación de la API

### 6.1 Desde el servidor

```bash
curl -s http://127.0.0.1:8013/
curl -s -w '\nHTTP %{http_code}\n' http://127.0.0.1:8013/health
```

### 6.2 Desde fuera (laptop)

```bash
curl -s -m 10 http://178.128.14.98:8013/health
curl -s -m 10 http://178.128.14.98:8013/
```

### 6.3 CRUD completo

```bash
B=http://127.0.0.1:8013

curl -s -X POST $B/tareas -H "Content-Type: application/json" \
     -d '{"titulo":"Tarea de prueba en el servidor"}'
curl -s $B/tareas
curl -s -X PUT $B/tareas/1 -H "Content-Type: application/json" \
     -d '{"completada":true}'
curl -s -X DELETE $B/tareas/1
curl -s $B/tareas
```

### 6.4 Logs

```bash
docker logs --tail 50 est13_api
docker logs --tail 50 est13_db
docker logs --tail 15 --since 10m est13_api
```

---

## 7. DevSecOps — `seguridad.sh`

```bash
chmod +x seguridad.sh
bash -n seguridad.sh            # validar sintaxis sin ejecutar
./seguridad.sh                  # 5 escaneos + monitoreo
./seguridad.sh seguridad        # solo escaneos
./seguridad.sh monitorear       # solo monitoreo
./seguridad.sh --help
```

Comandos que ejecuta el script por dentro (versión instalada):

```bash
gitleaks detect --source . --report-format json \
  --report-path reportes/gitleaks.json --redact --no-banner -v

semgrep scan --config=p/default --metrics=off --json \
  --output reportes/semgrep.json app

syft estudiante13/api-tareas:1.0.0 -o json > reportes/syft.json
syft estudiante13/api-tareas:1.0.0 -o table > reportes/syft.txt

trivy image --no-progress --scanners vuln \
  --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
  estudiante13/api-tareas:1.0.0 > reportes/trivy.txt

hadolint --no-color Dockerfile > reportes/hadolint.txt
```

Equivalente con imágenes Docker (si la herramienta no está instalada):

```bash
docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:latest \
  detect --source /repo --report-format json --report-path /repo/reportes/gitleaks.json

docker run --rm -v "$PWD:/src" --entrypoint semgrep semgrep/semgrep:latest \
  scan --config=p/default /src/app

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/syft:latest "docker:estudiante13/api-tareas:1.0.0" -o table

docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image estudiante13/api-tareas:1.0.0

docker run --rm -i --entrypoint hadolint hadolint/hadolint:latest \
  --no-color - < Dockerfile
```

Resultados obtenidos en el servidor:

```bash
cat reportes/resumen.txt
```

```
Gitleaks   | sin hallazgos             | reportes/gitleaks.json
Semgrep    | sin hallazgos             | reportes/semgrep.json
Syft       | SBOM generado (105 paquetes) | reportes/syft.json, syft.txt
Trivy      | CRITICAL:0 HIGH:48        | reportes/trivy.txt
Hadolint   | sin hallazgos             | reportes/hadolint.txt
```

---

## 8. Monitoreo

```bash
./seguridad.sh monitorear
tail -n 40 monitoreo.log
grep -c "MONITOREO" monitoreo.log
docker ps -a --filter "name=est13_" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker stats --no-stream
```

Registros generados: dos entradas fechadas (`monitoreo.log`), ambas con
`Resultado : SERVICIO OPERATIVO`.

### 8.1 Monitoreo automático (cron cada 10 minutos)

```bash
cd ~/estudiante13/devops-final
chmod 700 monitoreo_auto.sh
cp .monitoreo.env.example .monitoreo.env   # solo la primera vez
chmod 600 .monitoreo.env                   # completar credenciales aquí
nano .monitoreo.env

# instalación del cron (evita solapamientos con flock)
REPO=$HOME/estudiante13/devops-final
LINEA="*/10 * * * * /usr/bin/flock -n /tmp/est13_monitoreo_auto.lock $REPO/monitoreo_auto.sh >/dev/null 2>&1"
( crontab -l 2>/dev/null | grep -v "monitoreo_auto.sh"; echo "$LINEA" ) | crontab -
crontab -l

# prueba manual y revisión del registro
./monitoreo_auto.sh
cat monitoreo_auto.log
cat .monitoreo_auto.estado

# simular una caída (detiene y deja que el script lo levante)
docker compose stop
./monitoreo_auto.sh

# desactivar el chequeo
( crontab -l | grep -v "monitoreo_auto.sh" ) | crontab -
```

Configuración de notificaciones (`.monitoreo.env`, permisos `600`):

```env
NOTIFICAR=telegram          # telegram | email | ambos | ninguno
TG_TOKEN=<token de @BotFather>
TG_CHAT_ID=<id del chat>

# alternativa por correo
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USER=<correo>
SMTP_PASS=<contraseña de aplicación>
MAIL_FROM=<correo>
MAIL_TO=<destino>
```

---

## 9. Git: commits y publicación

```bash
# local
git status
git diff --stat
git add docker-compose.yml seguridad.sh README.md COMANDOS.md
git commit -m "Actividad ...: descripción del cambio"
git push origin main

# evidencias que están en .gitignore
git add -f reportes/ monitoreo.log
git commit -m "Actividad 4 y 5: agrega reportes y monitoreo"
git push origin main

# historial de la entrega
git log --oneline --graph --decorate
git remote -v
```

En el servidor, para sincronizar:

```bash
cd ~/estudiante13/devops-final
git pull --ff-only
git log --oneline
```

---

## 10. Diagnóstico y solución de problemas

```bash
# SSH
ssh -v estudiante13@178.128.14.98
ssh-keygen -lf ~/.ssh/id_ed25519.pub

# puertos y procesos
ss -ltn | grep ":8013"
ss -ltnp | grep ":8013"

# contenedores
docker ps -a
docker inspect est13_api --format '{{.State.Health.Status}}'
docker compose logs --tail 100 api
docker compose ps

# recursos del servidor
df -h
free -m

# validaciones del proyecto
bash -n seguridad.sh
docker compose config -q
hadolint --no-color Dockerfile
```

Errores encontrados y su corrección durante las pruebas:

| Error | Causa | Solución aplicada |
|---|---|---|
| `exec: "--no-color": executable file not found` | la imagen `hadolint/hadolint` no trae `ENTRYPOINT` | `docker run --entrypoint hadolint ... --no-color -` |
| Trivy informaba `CRITICAL:2` inexistentes | se contaban líneas, no los totales | sumar los `Total:` por severidad con `awk` |
| `Syft ... (1 paquetes)` | `grep -c` cuenta líneas y el JSON es una sola línea | contar `artifacts` con `python3` y fallback `grep -o` |

---

## 11. Limpieza usada durante las pruebas

```bash
# en la laptop, para liberar el puerto 8013 y los recursos de la prueba local
cd "Proyecto final/devops-final"
docker compose down -v
docker ps -a --filter name=est13_
```

---

## 12. Detener y eliminar el despliegue

### 12.1 Detener sin eliminar

```bash
cd ~/estudiante13/devops-final

docker compose stop          # detiene los contenedores; conserva red y volumen
docker compose ps -a         # ambos quedan en estado "Exited (0)"

docker ps --filter name=est13_     # vacío: no hay nada en ejecución
docker volume ls | grep estudiante13   # el volumen sigue existiendo
```

Con `restart: unless-stopped`, los servicios detenidos con `stop` **no** se
reinician solos al reiniciar el servidor.

Reactivar el despliegue:

```bash
cd ~/estudiante13/devops-final
docker compose start
curl http://127.0.0.1:8013/health
```

> Para la revisión del docente el despliegue debe estar **activo**: ejecutar
> `docker compose start` y comprobar `http://178.128.14.98:8013/health` (HTTP
> 200). Gracias a `restart: unless-stopped`, si el servidor se reinicia los
> contenedores que estaban en ejecución vuelven a arrancar solos.

### 12.2 Eliminar el despliegue (no ejecutado)

> **Advertencia:** estos comandos eliminan la API y sus datos. Hoy solo se
> detuvo el proyecto; no se eliminó nada.

```bash
cd ~/estudiante13/devops-final

docker compose down          # elimina contenedores y red (conserva el volumen)
docker compose down -v       # además elimina el volumen estudiante13_datos (borra datos)
docker image rm estudiante13/api-tareas:1.0.0

# eliminar el código del servidor
cd ~
rm -rf ~/estudiante13/devops-final
```

Verificación posterior:

```bash
docker ps -a --filter "name=est13_"
docker volume ls | grep estudiante13
docker network ls | grep estudiante13
ss -ltn | grep ":8013"
```
