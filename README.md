# Proyecto final DevOps — API de tareas con PostgreSQL

**Estudiante:** estudiante13
**API:** http://178.128.14.98:8013
**Servidor:** `178.128.14.98` (usuario `estudiante13`)
**Repositorio base:** https://github.com/jsansis-utp/devops-final
**Repositorio (fork):** https://github.com/Craos6518/devops-final

---

## 1. Descripción

Despliegue de una **API de tareas** escrita en Python (Flask + Gunicorn) que
persiste sus datos en **PostgreSQL**, ejecutada con **Docker Compose** en el
servidor compartido de la clase. El proyecto incluye además:

- control de versiones con **Git/GitHub** (fork + commits propios),
- documentación de los **comandos Linux** usados para ponerlo en marcha,
- un pipeline local de **DevSecOps** (`seguridad.sh`) con Gitleaks, Semgrep,
  Syft, Trivy y Hadolint,
- **monitoreo** con la función `monitorear` (estado de la API, contenedores y
  logs) y registro fechado en `monitoreo.log`.

### Puertos

| Uso | Puerto | Nota |
|---|---|---|
| API publicada en el servidor | **8013** | `8000 + 13` (número de estudiante) |
| API dentro del contenedor | 5000 | Gunicorn escucha aquí |
| PostgreSQL dentro de la red Docker | 5432 | **interno**, no se publica |
| Puerto PostgreSQL asignado en el servidor | 5445 | **no se usa en este proyecto** |

> El puerto `5445` es el de PostgreSQL del servidor y **no** se publica. El
> servicio `db` no tiene sección `ports` y la API se conecta por la red interna
> de Docker en `db:5432` (en `.env`: `DB_HOST=db`, `DB_PORT=5432`).

---

## 2. Arquitectura

```
                         Internet
                            │
                            │  http://178.128.14.98:8013
                            ▼
             ┌──────────────────────────────┐
             │  red Docker: estudiante13_red │
             │                              │
             │  ┌────────────────────────┐  │
             │  │ est13_api              │  │
             │  │ Flask + Gunicorn :5000 │  │
             │  │ (publica 8013:5000)    │  │
             │  └───────────┬────────────┘  │
             │              │ db:5432       │
             │  ┌───────────▼────────────┐  │
             │  │ est13_db               │  │
             │  │ PostgreSQL 16 (interno)│  │
             │  └───────────┬────────────┘  │
             │              │               │
             └──────────────┼───────────────┘
                            ▼
                 volumen estudiante13_datos
                 (persistencia de los datos)
```

| Recurso Docker | Nombre | Detalle |
|---|---|---|
| Proyecto Compose | `estudiante13` | primera línea de `docker-compose.yml` |
| Contenedor API | `est13_api` | `8013:5000` |
| Contenedor BD | `est13_db` | sin `ports`, solo red interna |
| Volumen | `estudiante13_datos` | datos de PostgreSQL |
| Red | `estudiante13_red` | red bridge del proyecto |

Los nombres con prefijo `est13_`/`estudiante13` son obligatorios en un servidor
compartido: sin `name:` Docker usaría el nombre de la carpeta (`devops-final`)
y los 35 estudiantes compartirían red, volumen y base de datos.

---

## 3. Estructura del repositorio

```
devops-final/
├── app/
│   ├── app.py               # API Flask (CRUD de tareas + /health + logs JSON)
│   └── requirements.txt     # Flask, Gunicorn, psycopg2-binary
├── Dockerfile               # imagen de la API (usuario sin privilegios)
├── docker-compose.yml       # servicios api + db, red y volumen propios
├── .env.example             # plantilla de variables de entorno
├── .env                     # variables reales (LOCAL, nunca se sube)
├── seguridad.sh             # Gitleaks, Semgrep, Syft, Trivy, Hadolint + monitorear
├── monitoreo.log            # registro fechado de cada monitoreo
├── reportes/                # resultados de los escaneos
│   ├── gitleaks.json
│   ├── semgrep.json
│   ├── syft.json / syft.txt
│   ├── trivy.txt
│   ├── hadolint.txt
│   └── resumen.txt
├── INSTRUCCIONES.md
└── README.md
```

---

## 4. Requisitos

- Docker Engine 24+ y Docker Compose v2 (`docker compose`).
- Acceso SSH al servidor con el usuario `estudiante13`.
- Opcional (si no están instaladas, `seguridad.sh` usa las imágenes Docker
  oficiales): `gitleaks`, `semgrep`, `syft`, `trivy`, `hadolint`, `curl`.

---

## 5. Bitácora de comandos Linux (en orden)

Todos los comandos usados para poner en marcha el proyecto, desde la conexión
hasta la verificación. El puerto de la API es **8013**. El registro completo y
ampliado (incluye DevSecOps, monitoreo, diagnóstico y limpieza) está en
[`COMANDOS.md`](COMANDOS.md).

### 5.1 Conexión al servidor

```bash
ssh estudiante13@178.128.14.98
hostname                 # verifica en qué máquina está
whoami                   # debe responder: estudiante13
pwd                      # /home/estudiante13
```

### 5.2 Navegación y creación de la carpeta de trabajo

```bash
cd ~                       # ir al home del usuario
mkdir -p ~/estudiante13    # carpeta de trabajo (si no existe)
cd ~/estudiante13          # entrar a la carpeta
ls -la                     # listar contenido, incluidos ocultos
```

### 5.3 Clonación del fork (Git)

```bash
git clone https://github.com/Craos6518/devops-final.git
cd devops-final
git remote -v              # origin  = mi fork
                           # upstream = repositorio del docente
git log --oneline --graph  # historial de commits
```

### 5.4 Archivo de variables de entorno

```bash
cp .env.example .env       # crear el .env a partir de la plantilla
nano .env                  # editar: ESTUDIANTE, API_PORT, claves
chmod 600 .env             # solo el dueño puede leerlo (contiene contraseña)
ls -l .env                 # verificar permisos: -rw-------
```

Contenido esperado de `.env` (la contraseña se cambia por una propia):

```env
ESTUDIANTE=estudiante13
API_PORT=8013

POSTGRES_DB=tareas
POSTGRES_USER=estudiante13
POSTGRES_PASSWORD=<clave_propia>

DB_HOST=db
DB_PORT=5432
```

> `.env` está en `.gitignore` y **nunca** se sube al repositorio.

### 5.5 Revisar contenedores previos (servidor compartido)

```bash
docker ps -a                       # ver todos los contenedores, incluso detenidos
docker ps -a | grep est13          # buscar nombres que puedan chocar
```

Si existe un contenedor con el mismo nombre (`est13_db` o `est13_api`), se
detiene y se elimina **solo si es propio**:

```bash
docker stop est13_db est13_api
docker rm   est13_db est13_api
```

> No se detienen ni eliminan contenedores de otros estudiantes: solo los que
> empiezan con el prefijo `est13_`.

### 5.6 Despliegue con Docker Compose

```bash
chmod +x seguridad.sh              # permisos de ejecución del script
docker compose config              # valida el YAML y muestra la configuración final
docker compose up -d --build       # construye la imagen y levanta api + db
docker compose ps                  # estado de los servicios del proyecto
docker compose ls                  # nombre de proyecto: estudiante13
docker volume ls | grep estudiante13   # volumen: estudiante13_datos
docker network ls | grep estudiante13  # red: estudiante13_red
```

### 5.7 Verificación de la API

```bash
curl -s http://127.0.0.1:8013/                      # info del servicio
curl -s http://127.0.0.1:8013/health                # {"estado":"ok",...}
curl -s -X POST http://127.0.0.1:8013/tareas \
     -H "Content-Type: application/json" \
     -d '{"titulo":"Primera tarea"}'                # crear
curl -s http://127.0.0.1:8013/tareas                # listar
curl -s -X PUT http://127.0.0.1:8013/tareas/1 \
     -H "Content-Type: application/json" \
     -d '{"completada":true}'                       # actualizar
curl -s -X DELETE http://127.0.0.1:8013/tareas/1     # eliminar
```

Verificación desde fuera del servidor (navegador o terminal local):

```bash
curl http://178.128.14.98:8013/health
```

### 5.8 Logs y monitoreo

```bash
docker logs --tail 50 est13_api           # logs JSON de la API
docker logs --tail 50 est13_db            # logs de PostgreSQL
docker stats --no-stream                  # CPU / memoria de los contenedores
./seguridad.sh monitorear                 # monitoreo fechado en monitoreo.log
tail -n 40 monitoreo.log                  # revisar el registro
```

### 5.9 Git: commits y publicación

```bash
git status                                # archivos modificados
git add docker-compose.yml seguridad.sh README.md .env.example .gitignore
git commit -m "Agrega docker-compose, script DevSecOps y documentacion"
git push origin main                      # publicar en el fork
git log --oneline --graph                 # evidencia del historial
```

---

## 6. Puesta en marcha rápida

```bash
ssh estudiante13@178.128.14.98
cd ~/estudiante13/devops-final
cp .env.example .env && nano .env      # ajustar ESTUDIANTE=estudiante13, API_PORT=8013
docker compose up -d --build
curl http://127.0.0.1:8013/health
./seguridad.sh
```

Para detener sin borrar datos:

```bash
docker compose down          # conserva el volumen estudiante13_datos
docker compose down -v       # ¡borra también los datos! (uso excepcional)
```

---

## 7. Endpoints de la API

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/` | Información del servicio y del estudiante |
| GET | `/health` | Estado de la API y de la conexión a PostgreSQL |
| GET | `/tareas` | Lista todas las tareas |
| POST | `/tareas` | Crea una tarea: `{"titulo": "..."}` |
| PUT | `/tareas/<id>` | Actualiza `titulo` y/o `completada` |
| DELETE | `/tareas/<id>` | Elimina una tarea |

Ejemplos:

```bash
curl http://178.128.14.98:8013/health
curl -X POST http://178.128.14.98:8013/tareas \
     -H "Content-Type: application/json" -d '{"titulo":"Primera tarea"}'
curl http://178.128.14.98:8013/tareas
```

Respuesta de `/health`:

```json
{"base_de_datos":"conectada","estado":"ok"}
```

La API escribe un log JSON por cada petición; se consulta con
`docker logs est13_api`.

---

## 8. DevSecOps — `seguridad.sh`

El script ejecuta las cinco herramientas y guarda los resultados en
`reportes/`. Si una herramienta está instalada en el servidor la usa
directamente; si no, la ejecuta con su imagen oficial de Docker.

```bash
chmod +x seguridad.sh
./seguridad.sh                # los 5 escaneos + monitoreo
./seguridad.sh seguridad      # solo escaneos
./seguridad.sh monitorear     # solo monitoreo
```

| Herramienta | Qué revisa | Comando (resumen) | Reporte |
|---|---|---|---|
| **Gitleaks** | secretos en el historial de Git | `gitleaks detect --source . --redact` | `reportes/gitleaks.json` |
| **Semgrep** | análisis estático de `app/` | `semgrep scan --config=p/default` | `reportes/semgrep.json` |
| **Syft** | inventario de dependencias (SBOM) de la imagen | `syft estudiante13/api-tareas:1.0.0 -o json` | `reportes/syft.json`, `syft.txt` |
| **Trivy** | vulnerabilidades de la imagen | `trivy image estudiante13/api-tareas:1.0.0` | `reportes/trivy.txt` |
| **Hadolint** | buenas prácticas del `Dockerfile` | `hadolint Dockerfile` | `reportes/hadolint.txt` |

Al final se genera `reportes/resumen.txt` con el estado de cada herramienta.

**Remediación aplicada al `Dockerfile`:** Hadolint reportaba `DL3066` (usuario no
numérico) y `DL3025` (HEALTHCHECK en formato shell). Se corrigieron usando
`USER 10001:10001` y la forma JSON en `HEALTHCHECK`; el análisis queda sin
hallazgos y la aplicación conserva el mismo comportamiento (usuario sin
privilegios, puerto 5000).

`reportes/` y `monitoreo.log` están en `.gitignore`; se entregan como evidencia
subiéndolos de forma explícita:

```bash
git add -f reportes/ monitoreo.log     # evidencia forzada (ignorada por .gitignore)
git commit -m "Agrega reportes de seguridad y monitoreo"
```

### Herramientas de forma manual (equivalente)

```bash
docker run --rm -v "$PWD:/repo" ghcr.io/gitleaks/gitleaks:latest \
  detect --source /repo --report-format json --report-path /repo/reportes/gitleaks.json
docker run --rm -v "$PWD:/src" semgrep/semgrep:latest scan --config=p/default /src/app
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  anchore/syft:latest "docker:estudiante13/api-tareas:1.0.0" -o table
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image estudiante13/api-tareas:1.0.0
docker run --rm -i hadolint/hadolint:latest < Dockerfile
```

---

## 9. Monitoreo — función `monitorear`

Dentro de `seguridad.sh`, `monitorear` hace lo siguiente y deja constancia con
fecha (UTC) en `monitoreo.log`:

1. Consulta `http://127.0.0.1:8013/health` y reporta `OK`/`FALLA` con el
   código HTTP.
2. Muestra el estado de `est13_api` y `est13_db` (`docker ps -a --filter name=est13_`).
3. Muestra CPU y memoria (`docker stats --no-stream`).
4. Muestra los últimos logs de cada contenedor (`docker logs --tail`).
5. Cierra con `SERVICIO OPERATIVO` o `REVISAR SERVICIO`.

Ejemplo de entrada del log:

```
==============================================================
MONITOREO 2026-11-17T18:40:12Z (UTC) - estudiante13
==============================================================
API          : http://127.0.0.1:8013/health
Estado API   : OK (HTTP 200) {"base_de_datos":"conectada","estado":"ok"}
Codigo       : 200

--- Contenedores del proyecto ---
NAMES       STATUS                    PORTS
est13_api   Up 5 minutes (healthy)    0.0.0.0:8013->5000/tcp
est13_db    Up 5 minutes (healthy)    5432/tcp
...
Resultado    : SERVICIO OPERATIVO
```

### 9.1 Monitoreo automático cada 10 minutos

`monitoreo_auto.sh` verifica la API y, si no responde, la levanta sola:

1. Consulta `http://127.0.0.1:8013/health`.
2. Si falla, ejecuta `docker compose up -d` y espera hasta 120 s a que vuelva.
3. Notifica por **Telegram** y/o **correo** según `.monitoreo.env` (permisos
   `600`, fuera de Git; la plantilla es `.monitoreo.env.example`).
4. Registra los eventos en `monitoreo_auto.log` y evita avisos repetidos
   (máximo uno por hora mientras siga caída).

```bash
# instalación del cron (cada 10 minutos, sin solapamientos con flock)
REPO=$HOME/estudiante13/devops-final
LINEA="*/10 * * * * /usr/bin/flock -n /tmp/est13_monitoreo_auto.lock $REPO/monitoreo_auto.sh >/dev/null 2>&1"
( crontab -l 2>/dev/null | grep -v "monitoreo_auto.sh"; echo "$LINEA" ) | crontab -
crontab -l

# prueba manual
cd $REPO
./monitoreo_auto.sh
tail -n 20 monitoreo_auto.log
```

> El cron se ejecuta como `estudiante13`, que pertenece al grupo `docker`, y
> solo administra el proyecto `estudiante13`.

### 9.2 Prueba real del monitoreo y de las notificaciones

Se detuvo el stack a propósito y se ejecutó el script: detectó la caída, levantó
los contenedores y avisó por Telegram en ambos extremos del evento.

```
$ docker compose stop
 Container est13_api Stopped
 Container est13_db  Stopped
$ curl -o /dev/null -w '%{http_code}' http://127.0.0.1:8013/health
000

$ ./monitoreo_auto.sh          # recuperación en ~13 s
$ docker compose ps
NAME        STATUS
est13_api   Up 6 seconds (healthy)
est13_db    Up 12 seconds (healthy)
$ curl http://127.0.0.1:8013/health
{"base_de_datos":"conectada","estado":"ok"}   HTTP 200
```

Registro (`monitoreo_auto.log`):

```
2026-11-17T21:04:56Z API sin respuesta en http://127.0.0.1:8013/health (estado previo: ok)
2026-11-17T21:04:56Z EVENTO: ALERTA: la API no responde en http://127.0.0.1:8013/health. Reiniciando contenedores...
2026-11-17T21:04:57Z Telegram enviado
2026-11-17T21:05:08Z EVENTO: RESTABLECIDO: la API vuelve a responder tras reiniciar los contenedores.
2026-11-17T21:05:09Z Telegram enviado
```

Credenciales: el token del bot y el `chat_id` viven solo en `.monitoreo.env`
del servidor (`600`, ignorado por Git). En el repositorio queda únicamente la
plantilla `.monitoreo.env.example` con los campos vacíos.

---

## 10. Problemas y soluciones

| Síntoma | Causa | Solución |
|---|---|---|
| `Bind for 0.0.0.0:8013 failed` | el puerto ya está ocupado | `docker ps` / `ss -ltnp \| grep 8013` y liberar solo lo propio |
| `name already in use` al hacer `up` | existe `est13_db`/`est13_api` de un ejercicio anterior | `docker stop est13_db est13_api && docker rm est13_db est13_api` |
| `/health` responde 503 | la API no conecta a la BD | revisar `DB_HOST=db`, `DB_PORT=5432`, credenciales del `.env` y `docker logs est13_db` |
| `permission denied (publickey)` en SSH | la llave pública no está cargada en la cuenta del servidor | reportar al docente y verificar con `ssh -v estudiante13@178.128.14.98` |
| Contenedor API reinicia en bucle | error de configuración/BD no lista | `docker compose logs api` y `docker compose ps` |
| Cambios en `.env` no se aplican | el contenedor mantiene las variables viejas | `docker compose up -d --force-recreate` |

Comandos de diagnóstico útiles:

```bash
docker compose ps
docker compose logs --tail 100 api
docker inspect est13_api --format '{{.State.Health.Status}}'
ss -ltnp | grep 8013
df -h                     # espacio en disco del servidor
free -m                   # memoria disponible
```

---

## 11. Seguridad aplicada

- `.env` fuera de Git (`.gitignore`) y con permisos `600`; solo se versiona
  `.env.example` con valores de ejemplo.
- Contenedor de la API con usuario sin privilegios (`appuser`) definido en el
  `Dockerfile`.
- PostgreSQL **no publica** su puerto: solo es accesible desde la red interna
  del proyecto (`estudiante13_red`).
- Healthchecks en ambos servicios y `depends_on: condition: service_healthy`
  para que la API espere a la base de datos.
- Límite de memoria por contenedor y rotación de logs (`max-size`, `max-file`)
  para no afectar al resto del servidor compartido.
- Gitleaks en el pipeline local para detectar secretos antes de publicar.

---

## 12. Evidencias de la entrega

| Evidencia | Dónde |
|---|---|
| Repositorio con historial de commits | https://github.com/Craos6518/devops-final |
| `README.md` (descripción + comandos Linux) | este archivo |
| `docker-compose.yml` | raíz del repositorio |
| `seguridad.sh` | raíz del repositorio |
| Reportes de seguridad | `reportes/` |
| Registro de monitoreo | `monitoreo.log` |
| API en funcionamiento | http://178.128.14.98:8013/health |

Comandos para generar la evidencia de Git:

```bash
git log --oneline --graph --decorate
git remote -v
git status
```

---

## 13. Estado del despliegue

Despliegue realizado el **2026-11-17** en el servidor `178.128.14.98`.

| Paso | Estado |
|---|---|
| Fork del repositorio base | ✅ |
| `docker-compose.yml`, `seguridad.sh`, `README.md` | ✅ |
| Validación del compose (`docker compose config`) | ✅ |
| Conexión SSH y clonación en `~/estudiante13/devops-final` | ✅ |
| `docker compose up -d --build` | ✅ `est13_api` y `est13_db` en estado `healthy` |
| API pública `http://178.128.14.98:8013/health` | ✅ HTTP 200, base de datos conectada |
| CRUD `/tareas` (POST, GET, PUT, DELETE) | ✅ verificado contra el servidor |
| Gitleaks, Semgrep y Hadolint | ✅ sin hallazgos |
| Syft (SBOM de la imagen) | ✅ 105 paquetes inventariados |
| Trivy (vulnerabilidades de la imagen) | ⚠️ 0 CRITICAL, 48 HIGH (imagen base) y Flask 3.0.3 con 1 LOW |
| Monitoreo | ✅ `monitoreo.log` con dos registros del servidor |

Los hallazgos de Trivy corresponden a la imagen base `python:3.12-slim`
(paquetes del sistema operativo Debian 13.7) y a una vulnerabilidad LOW de
Flask 3.0.3; no hay hallazgos en el código de la aplicación. Mitigación
recomendada: reconstruir la imagen periódicamente para recibir las
actualizaciones de la imagen base.

### Operación

```bash
docker compose stop     # detiene los servicios conservando los datos
docker compose start    # los reactiva
```

### Evidencia del despliegue

```bash
docker compose ls
docker volume ls | grep estudiante13
docker ps --filter name=est13_
curl http://178.128.14.98:8013/health
```

Resultado de `/health`:

```json
{"base_de_datos":"conectada","estado":"ok"}
```

---

## 14. Nota de transparencia

En la elaboración de este proyecto se utilizaron herramientas de apoyo,
incluida asistencia con IA, para la redacción de la documentación, la revisión
de los comandos y la estructura de los scripts. El estudiante revisó y ejecutó
las pruebas locales y en el servidor (API, Gitleaks, Semgrep, Syft, Trivy y
Hadolint), y es responsable de los resultados con los comandos y reportes
incluidos en el repositorio.
