#!/usr/bin/env bash
###############################################################################
# seguridad.sh - DevSecOps + monitoreo (Proyecto final DevOps)
#
# Estudiante : estudiante13
# API        : http://178.128.14.98:8013
# Contenedores: est13_api / est13_db
#
# Uso:
#   ./seguridad.sh              # ejecuta los 5 escaneos y el monitoreo
#   ./seguridad.sh seguridad    # solo los escaneos (Gitleaks/Semgrep/Syft/Trivy/Hadolint)
#   ./seguridad.sh monitorear   # solo la funcion monitorear
#   ./seguridad.sh --help
#
# Cada herramienta se usa instalada en el servidor; si no esta, se ejecuta con
# su imagen oficial de Docker (no requiere instalar nada).
# Resultados: reportes/      Registro de monitoreo: monitoreo.log
###############################################################################
set -uo pipefail

# Colores desactivados: los reportes se guardan como texto plano
export NO_COLOR=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTES="$ROOT_DIR/reportes"
LOG_MONITOREO="$ROOT_DIR/monitoreo.log"

# --------------------------------------------------------------- parametros
ESTUDIANTE="${ESTUDIANTE:-estudiante13}"
API_PORT="${API_PORT:-8013}"
API_URL="${API_URL:-http://127.0.0.1:${API_PORT}}"
CONTENEDOR_API="${CONTENEDOR_API:-est13_api}"
CONTENEDOR_DB="${CONTENEDOR_DB:-est13_db}"
IMAGEN="${IMAGEN:-estudiante13/api-tareas:1.0.0}"

# Imagenes oficiales de las herramientas (se pueden sobreescribir por variable)
IMG_GITLEAKS="${IMG_GITLEAKS:-ghcr.io/gitleaks/gitleaks:latest}"
IMG_SEMGREP="${IMG_SEMGREP:-semgrep/semgrep:latest}"
IMG_SYFT="${IMG_SYFT:-anchore/syft:latest}"
IMG_TRIVY="${IMG_TRIVY:-aquasec/trivy:latest}"
IMG_HADOLINT="${IMG_HADOLINT:-hadolint/hadolint:latest}"

# ------------------------------------------------------------------- utils
log()  { printf '%s\n' "$*"; }
info() { printf '\n=== %s ===\n' "$*"; }
error(){ printf 'ERROR: %s\n' "$*" >&2; }

hay_comando() { command -v "$1" >/dev/null 2>&1; }

docker_ok() {
  hay_comando docker && docker info >/dev/null 2>&1
}

preparar() {
  mkdir -p "$REPORTES"
  : > "$REPORTES/resumen.txt"
}

resumen() { # resumen <herramienta> <estado> <archivo>
  printf '%-10s | %-25s | %s\n' "$1" "$2" "$3" >> "$REPORTES/resumen.txt"
}

preparar_herramientas() {
  # Descarga silenciosa de las imagenes que se van a usar, para que los
  # reportes no se llenen de mensajes de "Pulling from ...".
  docker_ok || return 0
  hay_comando gitleaks || docker pull -q "$IMG_GITLEAKS" >/dev/null 2>&1 || true
  hay_comando semgrep  || docker pull -q "$IMG_SEMGREP"  >/dev/null 2>&1 || true
  hay_comando syft     || docker pull -q "$IMG_SYFT"     >/dev/null 2>&1 || true
  hay_comando trivy    || docker pull -q "$IMG_TRIVY"    >/dev/null 2>&1 || true
  hay_comando hadolint || docker pull -q "$IMG_HADOLINT" >/dev/null 2>&1 || true
}

ejecutar_imagen() { # ejecutar_imagen <imagen> <args...>  (ejecuta como usuario actual)
  local imagen="$1"; shift
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp "$imagen" "$@"
}

# --------------------------------------------------------------- 1. Gitleaks
escanear_gitleaks() {
  info "1/5 Gitleaks - busqueda de secretos en el repositorio"
  local salida="$REPORTES/gitleaks.json" texto="$REPORTES/gitleaks.txt"
  local codigo=1

  if hay_comando gitleaks; then
    gitleaks detect --source "$ROOT_DIR" --report-format json \
      --report-path "$salida" --redact --no-banner -v > "$texto" 2>&1
    codigo=$?
  elif docker_ok; then
    docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e NO_COLOR=1 \
      -v "$ROOT_DIR:/repo" "$IMG_GITLEAKS" detect \
      --source /repo --report-format json \
      --report-path /repo/reportes/gitleaks.json \
      --redact --no-banner -v > "$texto" 2>&1
    codigo=$?
  else
    error "Gitleaks no esta instalado y Docker no responde"
    resumen "Gitleaks" "NO EJECUTADO" "sin docker"
    return 1
  fi

  # Gitleaks devuelve 1 cuando encuentra hallazgos: es un resultado valido.
  if [ "$codigo" -eq 0 ]; then
    resumen "Gitleaks" "sin hallazgos" "reportes/gitleaks.json"
  elif [ "$codigo" -eq 1 ]; then
    resumen "Gitleaks" "CON HALLAZGOS (revisar)" "reportes/gitleaks.json"
  else
    resumen "Gitleaks" "error de ejecucion ($codigo)" "reportes/gitleaks.txt"
  fi
  tail -n 5 "$texto" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------- 2. Semgrep
escanear_semgrep() {
  info "2/5 Semgrep - analisis estatico del codigo"
  local json="$REPORTES/semgrep.json" texto="$REPORTES/semgrep.txt"
  local codigo=0

  # p/default funciona sin token y con metrics desactivadas (auto exige metrics)
  if hay_comando semgrep; then
    semgrep scan --config=p/default --metrics=off --json --output "$json" "$ROOT_DIR/app" \
      > "$texto" 2>&1
    codigo=$?
  elif docker_ok; then
    docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e NO_COLOR=1 \
      -e SEMGREP_SEND_METRICS=off \
      -v "$ROOT_DIR:/src" --entrypoint semgrep "$IMG_SEMGREP" \
      scan --config=p/default --metrics=off --json --output /src/reportes/semgrep.json \
      /src/app > "$texto" 2>&1
    codigo=$?
  else
    error "Semgrep no esta instalado y Docker no responde"
    resumen "Semgrep" "NO EJECUTADO" "sin docker"
    return 1
  fi

  # Si p/default falla (por ejemplo sin salida a Internet) se reintenta con p/ci
  if [ "$codigo" -ne 0 ] || [ ! -s "$json" ]; then
    log "Reintentando Semgrep con las reglas p/ci..."
    if hay_comando semgrep; then
      semgrep scan --config=p/ci --metrics=off --json --output "$json" "$ROOT_DIR/app" \
        > "$texto" 2>&1
      codigo=$?
    elif docker_ok; then
      docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e NO_COLOR=1 \
        -e SEMGREP_SEND_METRICS=off \
        -v "$ROOT_DIR:/src" --entrypoint semgrep "$IMG_SEMGREP" \
        scan --config=p/ci --metrics=off --json --output /src/reportes/semgrep.json \
        /src/app > "$texto" 2>&1
      codigo=$?
    fi
  fi

  if [ "$codigo" -eq 0 ]; then
    resumen "Semgrep" "sin hallazgos" "reportes/semgrep.json"
  elif [ "$codigo" -eq 1 ]; then
    resumen "Semgrep" "CON HALLAZGOS (revisar)" "reportes/semgrep.json"
  else
    resumen "Semgrep" "error de ejecucion ($codigo)" "reportes/semgrep.txt"
  fi
  tail -n 5 "$texto" 2>/dev/null
  return 0
}

# ------------------------------------------------------------------- 3. Syft
escanear_syft() {
  info "3/5 Syft - inventario de dependencias (SBOM) de la imagen $IMAGEN"
  local json="$REPORTES/syft.json" tabla="$REPORTES/syft.txt"

  if ! hay_comando syft && ! docker_ok; then
    error "Syft no esta instalado y Docker no responde"
    resumen "Syft" "NO EJECUTADO" "sin docker"
    return 1
  fi

  if hay_comando syft; then
    syft "$IMAGEN" -o json > "$json" 2> "$REPORTES/syft-errores.txt"
    syft "$IMAGEN" -o table > "$tabla" 2>> "$REPORTES/syft-errores.txt"
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      "$IMG_SYFT" "docker:$IMAGEN" -o json > "$json" 2> "$REPORTES/syft-errores.txt"
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      "$IMG_SYFT" "docker:$IMAGEN" -o table > "$tabla" 2>> "$REPORTES/syft-errores.txt"
  fi

  if [ -s "$json" ] || [ -s "$tabla" ]; then
    local paquetes
    paquetes="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1])).get("artifacts",[])))' "$json" 2>/dev/null || true)"
    [ -n "$paquetes" ] || paquetes="$(grep -o '"name"' "$json" 2>/dev/null | wc -l)"
    resumen "Syft" "SBOM generado (${paquetes:-?} paquetes)" "reportes/syft.json, syft.txt"
  else
    resumen "Syft" "error (imagen no encontrada?)" "reportes/syft-errores.txt"
  fi
  return 0
}

# ------------------------------------------------------------------ 4. Trivy
escanear_trivy() {
  info "4/5 Trivy - vulnerabilidades de la imagen $IMAGEN"
  local salida="$REPORTES/trivy.txt"

  if hay_comando trivy; then
    trivy image --no-progress --scanners vuln --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
      "$IMAGEN" > "$salida" 2>&1
  elif docker_ok; then
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      "$IMG_TRIVY" image --no-progress --scanners vuln \
      --severity UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL \
      "$IMAGEN" > "$salida" 2>&1
  else
    error "Trivy no esta instalado y Docker no responde"
    resumen "Trivy" "NO EJECUTADO" "sin docker"
    return 1
  fi

  # Se suman los totales por severidad que Trivy imprime por cada objetivo
  local criticas altas
  criticas="$(awk '/^Total:/{ if (match($0, /CRITICAL: [0-9]+/)) s += substr($0, RSTART+10, RLENGTH-10) } END{ print s+0 }' "$salida" 2>/dev/null)"
  altas="$(awk '/^Total:/{ if (match($0, /HIGH: [0-9]+/)) s += substr($0, RSTART+6, RLENGTH-6) } END{ print s+0 }' "$salida" 2>/dev/null)"
  resumen "Trivy" "CRITICAL:${criticas:-0} HIGH:${altas:-0}" "reportes/trivy.txt"
  grep '^Total:' "$salida" 2>/dev/null | head -n 10
  return 0
}

# --------------------------------------------------------------- 5. Hadolint
escanear_hadolint() {
  info "5/5 Hadolint - buenas practicas del Dockerfile"
  local salida="$REPORTES/hadolint.txt"
  local codigo=0

  if hay_comando hadolint; then
    ( cd "$ROOT_DIR" && hadolint --no-color Dockerfile ) > "$salida" 2>&1
    codigo=$?
  elif docker_ok; then
    docker run --rm -i -u "$(id -u):$(id -g)" -e HOME=/tmp \
      --entrypoint hadolint "$IMG_HADOLINT" --no-color - \
      < "$ROOT_DIR/Dockerfile" > "$salida" 2>&1
    codigo=$?
  else
    error "Hadolint no esta instalado y Docker no responde"
    resumen "Hadolint" "NO EJECUTADO" "sin docker"
    return 1
  fi

  if [ "$codigo" -eq 0 ]; then
    resumen "Hadolint" "sin hallazgos" "reportes/hadolint.txt"
  else
    resumen "Hadolint" "con observaciones" "reportes/hadolint.txt"
  fi
  cat "$salida" 2>/dev/null | head -n 10
  return 0
}

# -------------------------------------------------------------- monitoreo
monitorear() {
  local fecha estado_http respuesta
  fecha="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  {
    printf '\n%s\n' "=============================================================="
    printf 'MONITOREO %s (UTC) - %s\n' "$fecha" "$ESTUDIANTE"
    printf '%s\n' "=============================================================="

    # 1) La API responde?
    if hay_comando curl; then
      respuesta="$(curl -sS -m 5 -w '\nHTTP:%{http_code}' "$API_URL/health" 2>&1)"
    elif hay_comando wget; then
      respuesta="$(wget -q -T 5 -O - "$API_URL/health" 2>&1)"
    else
      respuesta="sin curl ni wget disponibles"
    fi
    estado_http="$(printf '%s' "$respuesta" | sed -n 's/.*HTTP:\([0-9]\{3\}\).*/\1/p')"

    printf 'API          : %s/health\n' "$API_URL"
    if [ "${estado_http:-000}" = "200" ]; then
      printf 'Estado API   : OK (HTTP %s) %s\n' "$estado_http" \
        "$(printf '%s' "$respuesta" | head -n 1)"
    elif [ -n "${estado_http:-}" ]; then
      printf 'Estado API   : FALLA (HTTP %s)\n' "$estado_http"
      printf 'Respuesta    : %s\n' "$(printf '%s' "$respuesta" | head -n 1)"
    else
      printf 'Estado API   : FALLA (sin respuesta del puerto %s)\n' "$API_PORT"
      printf 'Detalle      : %s\n' "$(printf '%s' "$respuesta" | head -n 1)"
    fi
    printf 'Codigo       : %s\n' "${estado_http:-000}"

    # 2) Estado de los contenedores
    if hay_comando docker && docker info >/dev/null 2>&1; then
      printf '\n--- Contenedores del proyecto ---\n'
      docker ps -a --filter "name=est13_" \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>&1

      printf '\n--- Uso de recursos ---\n'
      docker stats --no-stream --format \
        'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>&1 \
        | grep -E 'NAME|est13_' || true

      # 3) Ultimos logs
      printf '\n--- Ultimos logs de %s ---\n' "$CONTENEDOR_API"
      docker logs --tail 15 --since 10m "$CONTENEDOR_API" 2>&1 || true

      printf '\n--- Ultimos logs de %s ---\n' "$CONTENEDOR_DB"
      docker logs --tail 10 --since 10m "$CONTENEDOR_DB" 2>&1 || true
    else
      printf '\nDocker no responde: no se puede consultar contenedores ni logs.\n'
    fi

    printf '\nResultado    : %s\n' \
      "$([ "${estado_http:-000}" = "200" ] && echo 'SERVICIO OPERATIVO' || echo 'REVISAR SERVICIO')"
  } | tee -a "$LOG_MONITOREO"

  return 0
}

# ------------------------------------------------------------------- main
uso() {
  cat <<'AYUDA'
seguridad.sh - DevSecOps + monitoreo del proyecto final (estudiante13)

  ./seguridad.sh              ejecuta los 5 escaneos y luego monitorear
  ./seguridad.sh seguridad    solo los escaneos
  ./seguridad.sh monitorear   solo la funcion monitorear
  ./seguridad.sh --help       esta ayuda

Variables opcionales:
  API_PORT=8013  IMAGEN=estudiante13/api-tareas:1.0.0
  CONTENEDOR_API=est13_api  CONTENEDOR_DB=est13_db

Salidas:
  reportes/         gitleaks.json, semgrep.json, syft.json, trivy.txt,
                    hadolint.txt, resumen.txt
  monitoreo.log     registro con fecha de cada monitoreo
AYUDA
}

main() {
  case "${1:---todo}" in
    --help|-h) uso; exit 0 ;;
  esac

  preparar

  case "${1:---todo}" in
    --todo|seguridad|security|"")
      {
        printf 'Fecha      : %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf 'Estudiante : %s\n' "$ESTUDIANTE"
        printf 'Imagen     : %s\n' "$IMAGEN"
        printf 'Equipo     : %s\n' "$(hostname)"
        printf '%-10s | %-25s | %s\n' "HERRAMIENTA" "ESTADO" "ARCHIVO"
        printf '%s\n' "---------------------------------------------------------------"
      } > "$REPORTES/resumen.txt"

      preparar_herramientas
      escanear_gitleaks
      escanear_semgrep
      escanear_syft
      escanear_trivy
      escanear_hadolint
      monitorear

      info "Resumen de la ejecucion"
      cat "$REPORTES/resumen.txt"
      log ""
      log "Reportes en : $REPORTES"
      log "Monitoreo en: $LOG_MONITOREO"
      ;;
    monitorear|monitor)
      monitorear
      ;;
    *)
      error "Opcion no reconocida: $1"
      uso
      exit 2
      ;;
  esac
}

main "$@"
