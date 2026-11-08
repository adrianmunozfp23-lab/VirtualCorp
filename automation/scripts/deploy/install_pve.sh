#!/usr/bin/env bash
# Instal·lació desatesa de Proxmox VE a la VM pve01.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/infrastructure/bash/common.sh"

for c in proxmox-auto-install-assistant xorriso openssl curl; do need "$c"; done

name="${1:-pve01}"; ram="${2:-6144}"; cpus="${3:-4}"; nets="${4:-privada}"; group="${5:-CPD}"

PVE_ISO="$ISO_DIR/$PVE_ISO_FILENAME"
fetch_iso "$PVE_ISO_URL" "$PVE_ISO" "$PVE_ISO_SHA256"

w="$BUILD_DIR/pve"
rm -rf "$w"
mkdir -p "$w"

keylist="$(all_keys | sed 's/.*/    "&",/')"
mac_lower="$(printf '%s' "$PVE_MAC" | tr 'A-F' 'a-f')"
render "$SCRIPT_DIR/answer.toml.tpl" \
    "FQDN=$PVE_FQDN" "PWHASH=$(sysadmin_hash)" "KEYLIST=$keylist" \
    "CIDR=$PVE_CIDR" "DNS=$PVE_DNS" "GATEWAY=$PVE_GATEWAY" "MACLOWER=$mac_lower" \
    > "$w/answer.toml"
chmod 600 "$w/answer.toml"

log_info "Validant answer.toml"
proxmox-auto-install-assistant validate-answer "$w/answer.toml"
log_info "Preparant la ISO desatesa"
proxmox-auto-install-assistant prepare-iso "$PVE_ISO" --fetch-from iso \
    --answer-file "$w/answer.toml" --output "$w/pve-auto.iso"
log_ok "ISO de Proxmox desatesa creada: $w/pve-auto.iso"

if [[ "${PVE_ISO_ONLY:-0}" == 1 ]]; then
    log_ok "PVE_ISO_ONLY=1: només s'ha creat la ISO (sense VM)."
    exit 0
fi

if vm_exists "$name"; then
    log_warn "$name ja existeix, s'omet"
    exit 0
fi

log_info "Creant la VM $name"
"$VBOXMANAGE_BIN" createvm --name "$name" --ostype Debian_64 --register \
    --groups "$VBOX_ROOT_GROUP/$group" >/dev/null
"$VBOXMANAGE_BIN" modifyvm "$name" --memory "$ram" --cpus "$cpus" --ioapic on \
    --graphicscontroller vmsvga --vram 16 --boot1 disk --boot2 dvd
"$VBOXMANAGE_BIN" modifyvm "$name" --nested-hw-virt on \
    || { log_err "Aquest VirtualBox/CPU no permet --nested-hw-virt"; exit 1; }
"$VBOXMANAGE_BIN" modifyvm "$name" --nic1 intnet --intnet1 "${nets%%,*}" \
    --nictype1 82540EM --macaddress1 "$PVE_MAC"

dir="$(dirname "$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable | sed -n 's/^CfgFile="\(.*\)"/\1/p')")"
"$VBOXMANAGE_BIN" createmedium disk --filename "$dir/$name.vdi" --size $((PVE_DISK_GB * 1024)) --variant Standard >/dev/null
"$VBOXMANAGE_BIN" storagectl "$name" --name SATA --add sata --controller IntelAhci
"$VBOXMANAGE_BIN" storageattach "$name" --storagectl SATA --port 0 --device 0 --type hdd --medium "$dir/$name.vdi"
"$VBOXMANAGE_BIN" storageattach "$name" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$w/pve-auto.iso"

log_info "Instal·lant Proxmox (desatès). Per veure'l: VM_UI=gui"
"$VBOXMANAGE_BIN" startvm "$name" --type "${VM_UI:-headless}" >/dev/null
wait_poweroff "$name" 3600

"$VBOXMANAGE_BIN" storageattach "$name" --storagectl SATA --port 1 --device 0 --type dvddrive --medium none
log_ok "$name instal·lat. Arrenca'l amb: VBoxManage startvm $name --type headless"
