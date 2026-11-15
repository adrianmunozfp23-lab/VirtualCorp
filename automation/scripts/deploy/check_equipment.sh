#!/usr/bin/env bash
# Valida el desplegament: templates, màquines, clons enllaçats i NAT.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$PROJECT_ROOT/infrastructure/bash/common.sh"

echo "== Templates =="
for t in "$TPL_SERVER_NAME" "$TPL_DESKTOP_NAME"; do
    if vm_exists "$t"; then
        s="$("$VBOXMANAGE_BIN" snapshot "$t" list --machinereadable 2>/dev/null | grep -c '^SnapshotName')"
        echo "OK     $t (snapshots: $s)"
    else
        echo "FALTA  $t"
    fi
done

echo "== Equipament (configs/equipment.csv) =="
printf '%-11s %-9s %-15s %-14s %s\n' NOM TIPUS DISC XARXES NAT
while IFS=';' read -r name type group ram cpus nets; do
    [[ -z "${name// }" || "$name" == \#* ]] && continue
    if ! vm_exists "$name"; then echo "FALTA  $name"; continue; fi
    info="$("$VBOXMANAGE_BIN" showvminfo "$name" --machinereadable)"
    disk="$(grep -E '^"SATA-0-0"=' <<<"$info" | cut -d'"' -f4)"
    kind="disc-propi"; [[ "$disk" == */Snapshots/* ]] && kind="clon-enllacat"
    nat="$(grep -c -E '^nic[0-9]+="nat"' <<<"$info")"
    ints="$(grep -E '^intnet[0-9]+=' <<<"$info" | cut -d'"' -f2 | grep -v '^unused' | paste -sd, -)"
    printf '%-11s %-9s %-15s %-14s %s\n' "$name" "$type" "$kind" "$ints" "$nat"
done < "$EQUIPMENT_FILE"

echo "== Routers =="
for r in mikrotik0 mikrotik1 mikrotik2 mikrotik3; do
    info="$("$VBOXMANAGE_BIN" showvminfo "$r" --machinereadable 2>/dev/null)" || { echo "FALTA  $r"; continue; }
    nat="$(grep -c -E '^nic[0-9]+="nat"' <<<"$info")"
    ints="$(grep -E '^intnet[0-9]+=' <<<"$info" | cut -d'"' -f2 | grep -v '^unused' | paste -sd, -)"
    printf '%-11s xarxes=%-26s nat=%s\n' "$r" "$ints" "$nat"
done

echo "== Màquines amb NAT (només mikrotik0 hauria de sortir) =="
"$VBOXMANAGE_BIN" list vms | sed 's/^"\(.*\)" {.*/\1/' | while read -r vm; do
    n="$("$VBOXMANAGE_BIN" showvminfo "$vm" --machinereadable | grep -c -E '^nic[0-9]+="nat"')"
    [[ "$n" -gt 0 ]] && echo "$vm"
done
