#!/usr/bin/env bash

set -e

# Carregar les funcions d'ajuda
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/router_base.sh"


check_prerequisites

# Crea el template pel router
# create_router_template

# Desplegament de mikrotik0 (CPD: DMZ + zona privada + sortida a Internet)
create_router "mikrotik0" 2200 \
  --intnets "rt0_1" "dmz" "privada" \
  --ips "10.17.0.225/30" "10.17.0.193/27" "10.17.0.129/26" \
  --nat

# Desplegament de mikrotik1
create_router "mikrotik1" 2201 \
  --intnets "rt0_1" "rt1_2" "pl0" \
  --ips "10.17.0.226/30" "10.17.0.229/30" "10.17.0.1/25" \
  --gateway "10.17.0.225"

# Desplegament de mikrotik2
create_router "mikrotik2" 2202 \
  --intnets "rt1_2" "rt2_3" "pl1" "pl2" \
  --ips "10.17.0.230/30" "10.17.0.233/30" "10.17.1.1/24" "10.17.2.1/24" \
  --gateway "10.17.0.229"

# Desplegament de mikrotik3
create_router "mikrotik3" 2203 \
  --intnets "rt2_3" "pl3" "pl3_direccio" \
  --ips "10.17.0.234/30" "10.17.3.1/25" "10.17.3.129/25" \
  --gateway "10.17.0.233"

log_info "=========================================="
log_info "[+] Routers desplegats correctament."
log_info "=========================================="
