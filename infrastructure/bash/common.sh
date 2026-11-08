#!/usr/bin/env bash

VBOXMANAGE_BIN="${VBOXMANAGE_BIN:-$(command -v VBoxManage 2>/dev/null || command -v vboxmanage 2>/dev/null || true)}"
if [ -z "$VBOXMANAGE_BIN" ]; then
    echo "Error: VBoxManage no està instal·lat o no es troba al PATH del sistema." >&2
    exit 1
fi

VBOX_ROOT_GROUP="${VBOX_ROOT_GROUP:-/VirtualCorp}"
VM_ROUTERS_GROUP="${VM_ROUTERS_GROUP:-$VBOX_ROOT_GROUP/Routers}"
VM_TEMPLATES_GROUP="${VM_TEMPLATES_GROUP:-$VBOX_ROOT_GROUP/templates}"


ROUTEROS_VERSION="${ROUTEROS_VERSION:-7.21.4}"
ROUTEROS_VDI_FILENAME="${ROUTEROS_VDI_FILENAME:-chr-${ROUTEROS_VERSION}.vdi}"
URL="${ROUTEROS_URL:-https://download.mikrotik.com/routeros/${ROUTEROS_VERSION}/${ROUTEROS_VDI_FILENAME}.zip}"

ROUTER_MEMORY=256
ROUTER_CPU=1

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$COMMON_DIR/../.." && pwd)}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${PROJECT_ROOT}/artifacts/images/chr}"
CONFIGS_DIR="${CONFIGS_DIR:-${PROJECT_ROOT}/configs}"
SSH_PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR}/ssh}"
SSH_PRIVATE_KEY_DIR="${SSH_PRIVATE_KEY_DIR:-${HOME}/.ssh}"
ROUTEROS_VDI_PATH="${ROUTEROS_VDI_PATH:-${ARTIFACTS_DIR}/${ROUTEROS_VDI_FILENAME}}"

VM_NAME="routeros_template"
BOX_NAME="${ROUTEROS_BOX_NAME:-routeros-base}"
BOX_FILE="${ROUTEROS_BOX_FILE:-${ARTIFACTS_DIR}/${BOX_NAME}.box}"

SSH_PORT=2222
SSH_USER=sysadmin

AUDIT_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_DIR}/vcorp_auditor"
AUDIT_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_auditor.pub"
SYSADMIN_PRIVATE_KEY_FILE="${SSH_PRIVATE_KEY_DIR}/vcorp_sysadmin"
SYSADMIN_PUB_KEY_FILE="${SSH_PUBLIC_KEY_DIR}/vcorp_sysadmin.pub"

# Colors ANSI
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

log_err() {
    echo -e "${RED}[ERROR]${NC} $*"
}

wait_ssh() {
    local ip="${1:-127.0.0.1}"
    local port="${2:-22}"
    local max_wait="${3:-60}"
    local elapsed=0
    local interval=5

    log_info "Esperant servei SSH a ${ip}:${port} (màx ${max_wait}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        # ssh-keyscan valida que el dimoni SSH estigui actiu i responent
        if ssh-keyscan -p "$port" "$ip" >/dev/null 2>&1; then
            log_info "SSH disponible a ${ip}:${port}!"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    log_error "Timeout: SSH no disponible a ${ip}:${port} després de ${max_wait}s."
    return 1
}

# =========================================================
# ACTIVITAT 2: ISOs, templates i equipament
# =========================================================
log_error() { log_err "$@"; }   # àlies: alguns scripts criden log_error

ISO_DIR="${ISO_DIR:-${PROJECT_ROOT}/artifacts/images/iso}"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/artifacts/build}"
SECRETS_DIR="${SECRETS_DIR:-${PROJECT_ROOT}/artifacts/secrets}"
EQUIPMENT_FILE="${EQUIPMENT_FILE:-${CONFIGS_DIR}/equipment.csv}"

# Versions FIXES (no cercar mai l'última versió automàticament)
DEBIAN_VERSION="${DEBIAN_VERSION:-13.7.0}"
DEBIAN_ISO_FILENAME="${DEBIAN_ISO_FILENAME:-debian-${DEBIAN_VERSION}-amd64-netinst.iso}"
DEBIAN_ISO_URL="${DEBIAN_ISO_URL:-https://cdimage.debian.org/debian-cd/${DEBIAN_VERSION}/amd64/iso-cd/${DEBIAN_ISO_FILENAME}}"
DEBIAN_ISO_SHA256="${DEBIAN_ISO_SHA256:-a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355}"

PVE_VERSION="${PVE_VERSION:-9.2-1}"
PVE_ISO_FILENAME="${PVE_ISO_FILENAME:-proxmox-ve_${PVE_VERSION}.iso}"
PVE_ISO_URL="${PVE_ISO_URL:-https://enterprise.proxmox.com/iso/${PVE_ISO_FILENAME}}"
PVE_ISO_SHA256="${PVE_ISO_SHA256:-4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c}"

# Templates Debian
TPL_SERVER_NAME="${TPL_SERVER_NAME:-tpl-debian-server}"
TPL_DESKTOP_NAME="${TPL_DESKTOP_NAME:-tpl-debian-desktop}"
TPL_SNAPSHOT="${TPL_SNAPSHOT:-base}"
TPL_SERVER_DISK_GB="${TPL_SERVER_DISK_GB:-8}"
TPL_DESKTOP_DISK_GB="${TPL_DESKTOP_DISK_GB:-20}"
TPL_BUILD_RAM_MB="${TPL_BUILD_RAM_MB:-2048}"

# pve01 (adreçament segons el disseny de la delegació 17)
PVE_FQDN="${PVE_FQDN:-pve01.vcorp.local}"
PVE_CIDR="${PVE_CIDR:-10.17.0.133/26}"
PVE_GATEWAY="${PVE_GATEWAY:-10.17.0.129}"
PVE_DNS="${PVE_DNS:-1.1.1.1}"
PVE_MAC="${PVE_MAC:-080027A10001}"
PVE_DISK_GB="${PVE_DISK_GB:-64}"

# --- Funcions comunes ---
need() {
    command -v "$1" >/dev/null 2>&1 || { log_err "Falta l'ordre: $1"; exit 1; }
}

vm_exists() {
    "$VBOXMANAGE_BIN" list vms | grep -q "^\"$1\" "
}

vm_state() {
    "$VBOXMANAGE_BIN" showvminfo "$1" --machinereadable | sed -n 's/^VMState="\(.*\)"/\1/p'
}

wait_poweroff() {   # vm [timeout_segons]
    local vm="$1" timeout="${2:-3600}" waited=0
    while [[ "$(vm_state "$vm")" != "poweroff" ]]; do
        if (( waited >= timeout )); then
            log_err "Timeout esperant que '$vm' s'apagui. Reintenta amb VM_UI=gui per veure l'instal·lador."
            exit 1
        fi
        sleep 15
        waited=$((waited + 15))
    done
}

fetch_iso() {   # url fitxer sha256
    local url="$1" file="$2" sha="$3"
    if [[ -z "$sha" ]]; then
        log_err "Falta el SHA256 de $(basename "$file")"
        exit 1
    fi
    mkdir -p "$(dirname "$file")"
    if [[ ! -f "$file" ]]; then
        log_info "Descarregant $url"
        curl -fL --retry 3 -o "$file.part" "$url" && mv "$file.part" "$file" \
            || { log_err "Ha fallat la descàrrega de $url"; rm -f "$file.part"; exit 1; }
    fi
    if ! echo "$sha  $file" | sha256sum -c - >/dev/null 2>&1; then
        log_err "Checksum incorrecte: $file"
        exit 1
    fi
    log_ok "ISO verificada: $(basename "$file")"
}

render() {   # plantilla CLAU=valor ...   (substitueix __CLAU__)
    shopt -u patsub_replacement 2>/dev/null || true
    local content kv
    content="$(<"$1")"
    shift
    for kv in "$@"; do
        content="${content//"__${kv%%=*}__"/${kv#*=}}"
    done
    printf '%s\n' "$content"
}

all_keys() {   # claus públiques: professor + alumne
    [[ -f "$AUDIT_PUB_KEY_FILE" ]]    || { log_err "No existeix $AUDIT_PUB_KEY_FILE"; exit 1; }
    [[ -f "$SYSADMIN_PUB_KEY_FILE" ]] || { log_err "No existeix $SYSADMIN_PUB_KEY_FILE"; exit 1; }
    printf '%s\n%s\n' "$(<"$AUDIT_PUB_KEY_FILE")" "$(<"$SYSADMIN_PUB_KEY_FILE")"
}

# Contrasenya aleatòria només per a consola; SSH serà només per clau. No va a Git.
sysadmin_hash() {
    mkdir -p "$SECRETS_DIR"
    if [[ ! -f "$SECRETS_DIR/sysadmin.pass" ]]; then
        openssl rand -base64 18 > "$SECRETS_DIR/sysadmin.pass"
        chmod 600 "$SECRETS_DIR/sysadmin.pass"
    fi
    openssl passwd -6 "$(<"$SECRETS_DIR/sysadmin.pass")"
}
