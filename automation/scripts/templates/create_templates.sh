#!/usr/bin/env bash
# Crea els templates Debian (server i desktop) amb instal·lació desatesa.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/infrastructure/bash/common.sh"

for c in xorriso cpio gzip openssl curl; do need "$c"; done

DEBIAN_ISO="$ISO_DIR/$DEBIAN_ISO_FILENAME"
fetch_iso "$DEBIAN_ISO_URL" "$DEBIAN_ISO" "$DEBIAN_ISO_SHA256"

# build_iso <tipus> <hostname> <paquets> <extra_late>
build_iso() {
    local type="$1" host="$2" pkgs="$3" extra="$4"
    local w="$BUILD_DIR/$type"
    chmod -R u+w "$w" 2>/dev/null || true
    rm -rf "$w"
    mkdir -p "$w/extra/vcorp"

    log_info "[$type] Extraient la ISO"
    xorriso -osirrox on -indev "$DEBIAN_ISO" -extract / "$w/iso" >/dev/null 2>&1
    chmod -R u+w "$w/iso"

    render "$SCRIPT_DIR/preseed.cfg.tpl" "HOSTNAME=$host" "PKGS=$pkgs" "PWHASH=$(sysadmin_hash)" > "$w/extra/preseed.cfg"
    render "$SCRIPT_DIR/late.sh.tpl" "KEYS=$(all_keys)" "EXTRA=$extra" > "$w/extra/vcorp/late.sh"

    # El preseed i el script final s'incrusten dins l'initrd de l'instal·lador
    (cd "$w/extra" && find . | cpio -o -H newc --quiet | gzip -9) > "$w/extra.gz"
    cat "$w/iso/install.amd/initrd.gz" "$w/extra.gz" > "$w/initrd.new"
    mv "$w/initrd.new" "$w/iso/install.amd/initrd.gz"

    cat > "$w/iso/isolinux/isolinux.cfg" <<'EOF'
default vcorp
prompt 0
timeout 1
label vcorp
  kernel /install.amd/vmlinuz
  append auto=true priority=critical file=/preseed.cfg initrd=/install.amd/initrd.gz --- quiet
EOF

    xorriso -as mkisofs -r -V "VCORP_$type" -J -joliet-long -o "$w/auto.iso" \
        -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot \
        -boot-load-size 4 -boot-info-table "$w/iso" >/dev/null 2>&1
    log_ok "[$type] ISO desatesa creada: $w/auto.iso"
}

# make_template <nom> <disc_gb> <iso>
make_template() {
    local name="$1" disk="$2" iso="$3"

    if vm_exists "$name"; then
        log_warn "Esborrant el template anterior '$name'"
        "$VBOXMANAGE_BIN" unregistervm "$name" --delete >/dev/null
    fi

    log_info "[$name] Creant la VM"
    "$VBOXMANAGE_BIN" createvm --name "$name" --ostype Debian_64 --register \
        --groups "$VM_TEMPLATES_GROUP" >/dev/null
    # NAT només durant la instal·lació (per descarregar paquets); després s'elimina
    "$VBOXMANAGE_BIN" modifyvm "$name" --memory "$TPL_BUILD_RAM_MB" --cpus 2 --ioapic on \
        --graphicscontroller vmsvga --vram 16 \
        --nic1 nat --nictype1 82540EM --boot1 dvd --boot2 disk

    local dir
    dir="$(dirname "$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable | sed -n 's/^CfgFile="\(.*\)"/\1/p')")"
    "$VBOXMANAGE_BIN" createmedium disk --filename "$dir/$name.vdi" --size $((disk * 1024)) --variant Standard >/dev/null
    "$VBOXMANAGE_BIN" storagectl "$name" --name SATA --add sata --controller IntelAhci
    "$VBOXMANAGE_BIN" storageattach "$name" --storagectl SATA --port 0 --device 0 --type hdd --medium "$dir/$name.vdi"
    "$VBOXMANAGE_BIN" storageattach "$name" --storagectl SATA --port 1 --device 0 --type dvddrive --medium "$iso"

    log_info "[$name] Instal·lant (desatès, 10-25 min). Per veure'l: VM_UI=gui"
    "$VBOXMANAGE_BIN" startvm "$name" --type "${VM_UI:-headless}" >/dev/null
    wait_poweroff "$name" 3600

    "$VBOXMANAGE_BIN" storageattach "$name" --storagectl SATA --port 1 --device 0 --type dvddrive --medium none
    "$VBOXMANAGE_BIN" modifyvm "$name" --nic1 none --boot1 disk --boot2 none
    "$VBOXMANAGE_BIN" snapshot "$name" take "$TPL_SNAPSHOT" >/dev/null
    log_ok "[$name] Template llest (snapshot '$TPL_SNAPSHOT')"
}

build_iso server debian-server "openssh-server sudo ca-certificates iputils-ping" ""
build_iso desktop debian-desktop "openssh-server sudo ca-certificates iputils-ping xorg lxqt-core sddm falkon" \
    "apt-get purge -y firefox-esr 2>/dev/null || true"

if [[ "${TPL_ISO_ONLY:-0}" == 1 ]]; then
    log_ok "TPL_ISO_ONLY=1: només s'han creat les ISOs (sense VMs)."
    exit 0
fi

make_template "$TPL_SERVER_NAME"  "$TPL_SERVER_DISK_GB"  "$BUILD_DIR/server/auto.iso"
make_template "$TPL_DESKTOP_NAME" "$TPL_DESKTOP_DISK_GB" "$BUILD_DIR/desktop/auto.iso"
log_ok "Templates creats."
