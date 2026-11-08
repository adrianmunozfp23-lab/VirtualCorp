#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Configuració
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../../../" && pwd)}"

PUBLIC_KEY_DIR="${SSH_PUBLIC_KEY_DIR:-${CONFIGS_DIR:-${PROJECT_ROOT}/configs}/ssh}"
PRIVATE_KEY_DIR="${SSH_PRIVATE_KEY_DIR:-${HOME}/.ssh}"

FORCE=false

###############################################################################
# Funcions
###############################################################################

usage() {
    cat <<EOF
VirtualCorp SSH Key Generator

Genera les claus SSH del laboratori VirtualCorp:
  - vcorp_auditor
  - sysadmin

Opcions:
  -f    Força regeneració (esborra claus existents)
  -h    Mostra ajuda

Exemples:
  $(basename "$0")
  $(basename "$0") -f
EOF
}

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

###############################################################################
# SEGURETAT: evitar secrets al repositori
###############################################################################

check_repo_for_private_keys() {
    log_info "Comprovant que no hi ha claus privades al repositori..."

    local found
    found=$(find "${PROJECT_ROOT}" -type f \( -name "*.key" -o -name "id_*" -o -name "*.pem" \) 2>/dev/null || true)

    if [[ -n "${found}" ]]; then
        echo
        log_err "S'han detectat possibles claus privades dins del repositori!"
        echo "${found}"
        echo
        log_err "Refusa continuar per seguretat."
        exit 1
    fi

    log_ok "No s'han detectat secrets al repositori."
}

###############################################################################
# Generació de claus
###############################################################################

generate_key() {
    local key_name="$1"

    local private_key="${PRIVATE_KEY_DIR}/${key_name}"
    local public_key_repo="${PUBLIC_KEY_DIR}/${key_name}.pub"

    if [[ -f "${private_key}" || -f "${private_key}.pub" ]]; then
        if [[ "${FORCE}" != "true" ]]; then
            log_warn "La clau '${key_name}' ja existeix. S'omet (usa -f per regenerar)."
            return
        fi

        log_warn "Regenerant '${key_name}' (FORÇAT)"

        rm -f \
            "${private_key}" \
            "${private_key}.pub" \
            "${public_key_repo}"
    fi

    log_info "Generant clau '${key_name}'..."

    ssh-keygen \
        -q \
        -t ed25519 \
        -a 100 \
        -N "" \
        -C "${key_name}@virtualcorp" \
        -f "${private_key}"

    cp "${private_key}.pub" "${public_key_repo}"

    chmod 600 "${private_key}"
    chmod 644 "${private_key}.pub"
    chmod 644 "${public_key_repo}"

    log_ok "Clau '${key_name}' creada"
}

generate_mikrotik_key() {
    # Mikrotik is not compatible with modern ssh keys $ algorithms
    # Generate a ssh pair key specific to Mikrotik
    local key_name=vcorp_mikrotik

    local private_key="${PRIVATE_KEY_DIR}/${key_name}"
    local public_key_repo="${PUBLIC_KEY_DIR}/${key_name}.pub"

    if [[ -f "${private_key}" || -f "${private_key}.pub" ]]; then
        if [[ "${FORCE}" != "true" ]]; then
            log_warn "La clau '${key_name}' ja existeix. S'omet (usa -f per regenerar)."
            return
        fi

        log_warn "Regenerant '${key_name}' (FORÇAT)"

        rm -f \
            "${private_key}" \
            "${private_key}.pub" \
            "${public_key_repo}"
    fi

    log_info "Generant clau '${key_name}'..."

    ssh-keygen \
        -q \
        -t rsa \
        -m pem \
        -b 2048 \
        -N "" \
        -C "${key_name}@virtualcorp" \
        -f "${private_key}"

    cp "${private_key}.pub" "${public_key_repo}"

    chmod 600 "${private_key}"
    chmod 644 "${private_key}.pub"
    chmod 644 "${public_key_repo}"

    log_ok "Clau '${key_name}' creada"
}



###############################################################################
# CLI
###############################################################################

while getopts ":fh" opt; do
    case "${opt}" in
        f)
            FORCE=true
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            log_err "Opció invàlida: -${OPTARG}"
            usage
            exit 1
            ;;
    esac
done

###############################################################################
# Execució
###############################################################################

if ! command -v ssh-keygen >/dev/null 2>&1; then
    log_err "ssh-keygen no està instal·lat"
    exit 1
fi

mkdir -p "${PRIVATE_KEY_DIR}"
mkdir -p "${PUBLIC_KEY_DIR}"

check_repo_for_private_keys

generate_key "vcorp_sysadmin"
generate_mikrotik_key

###############################################################################
# Resum final
###############################################################################

cat <<EOF

==================================================
VirtualCorp SSH Keys generades correctament
==================================================

Privades (LOCAL):
  ${PRIVATE_KEY_DIR}/vcorp_auditor
  ${PRIVATE_KEY_DIR}/sysadmin

Públiques (REPO):
  ${PUBLIC_KEY_DIR}/vcorp_auditor.pub
  ${PUBLIC_KEY_DIR}/sysadmin.pub

Regles del laboratori:
  - NO pujar mai claus privades a GitHub
  - sysadmin → administració + Ansible
  - vcorp_auditor → accés professor / auditoria

==================================================
EOF
