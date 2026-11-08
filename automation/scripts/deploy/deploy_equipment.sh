#!/usr/bin/env bash
# Desplega servidors, impressores i equips d'escriptori com a clons enllaçats.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/infrastructure/bash/common.sh"

[[ -f "$EQUIPMENT_FILE" ]] || { log_err "No existeix $EQUIPMENT_FILE"; exit 1; }
for t in "$TPL_SERVER_NAME" "$TPL_DESKTOP_NAME"; do
    vm_exists "$t" || { log_err "No existeix el template '$t'. Executa abans: make create_templates"; exit 1; }
done

# set_nets <vm> <xarxes separades per coma>   (sempre xarxa interna, mai NAT)
set_nets() {
    local vm="$1" i=1 n
    local -a nets
    IFS=',' read -ra nets <<< "$2"
    for n in "${nets[@]}"; do
        "$VBOXMANAGE_BIN" modifyvm "$vm" "--nic$i" intnet "--intnet$i" "$n" \
            "--nictype$i" 82540EM "--cableconnected$i" on
        i=$((i + 1))
    done
}

while IFS=';' read -r name type group ram cpus nets; do
    [[ -z "${name// }" || "$name" == \#* ]] && continue

    if vm_exists "$name"; then
        log_warn "$name ja existeix, s'omet"
        continue
    fi

    case "$type" in
        server|desktop)
            tpl="$TPL_SERVER_NAME"
            [[ "$type" == desktop ]] && tpl="$TPL_DESKTOP_NAME"
            log_info "Clon enllaçat $name  <-  $tpl"
            "$VBOXMANAGE_BIN" clonevm "$tpl" --snapshot "$TPL_SNAPSHOT" --options link \
                --name "$name" --register --groups "$VBOX_ROOT_GROUP/$group" >/dev/null
            "$VBOXMANAGE_BIN" modifyvm "$name" --memory "$ram" --cpus "$cpus"
            set_nets "$name" "$nets"
            # El hostname del clon es llegeix d'aquest valor (servei vcorp-sethostname)
            "$VBOXMANAGE_BIN" setextradata "$name" \
                "VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial" "$name"

            if [[ "${VERIFY_BOOT:-1}" == 1 ]]; then
                "$VBOXMANAGE_BIN" startvm "$name" --type headless >/dev/null
                sleep 25
                if [[ "$(vm_state "$name")" == running ]]; then
                    log_ok "$name arrenca correctament"
                else
                    log_warn "$name NO està en execució després de l'arrencada"
                fi
                "$VBOXMANAGE_BIN" controlvm "$name" poweroff 2>/dev/null || true
                sleep 3
            fi
            ;;
        pve)
            if [[ -x "$SCRIPT_DIR/install_pve.sh" ]]; then
                bash "$SCRIPT_DIR/install_pve.sh" "$name" "$ram" "$cpus" "$nets" "$group"
            else
                log_warn "$name pendent: encara no existeix install_pve.sh"
            fi
            ;;
        *)
            log_err "Tipus desconegut '$type' per a $name"
            exit 1
            ;;
    esac
done < "$EQUIPMENT_FILE"

log_ok "Desplegament completat."
