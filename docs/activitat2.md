# Activitat 2: templates Debian, clons enllaçats i pve01 (delegació 17, 10.17.0.0/16)

## 1. Requisits previs

- Ubuntu amb VirtualBox 7.2.x (`VBoxManage`), GNU Make, `curl`, `xorriso`, `cpio`, `gzip`, `openssl`.
- `proxmox-auto-install-assistant`: s'instal·la des del repositori de Proxmox (`pve-no-subscription`, trixie) descarregant el `.deb` amb `apt download` i instal·lant-lo localment.
- Virtualització assistida per maquinari (VT-x/AMD-V) activada a la BIOS.
- Claus SSH generades (`make ssh-keys`) i routers desplegats (`make deploy-routers`).

## 2. Versions fixes, URL i variables

Les versions NO es cerquen automàticament. Estan fixades a `infrastructure/bash/common.sh` (valors per defecte `${VAR:-...}`, que es poden sobreescriure amb variables d'entorn o amb `.env`).

| Component | Versió | Fitxer | SHA256 |
|---|---|---|---|
| Debian (Trixie, amd64) | 13.7.0 | `debian-13.7.0-amd64-netinst.iso` | `a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355` |
| Proxmox VE | 9.2-1 | `proxmox-ve_9.2-1.iso` | `4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c` |

- URL Debian: `https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso`
- URL Proxmox: `https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso` (vegeu incidències: `download.proxmox.com` té un certificat que no cobreix aquest nom).
- Les ISOs es desen a `artifacts/images/iso/` i NO es versionen (`.gitignore`). `fetch_iso` verifica el SHA256 i reprèn descàrregues interrompudes.
- Altres variables a `common.sh`: noms dels templates, mides de disc, paràmetres de `pve01` (`PVE_*`), rutes (`ISO_DIR`, `BUILD_DIR`, `SECRETS_DIR`, `EQUIPMENT_FILE`).
- Llista d'equips: `configs/equipment.csv` (`nom;tipus;grup;ram_mb;cpus;xarxes`).

Actualització de versions: crear una branca Git específica, canviar les variables (versió i SHA256), provar `create_templates` i el desplegament en entorn de proves, i fusionar a `main` només si les proves són satisfactòries.

## 3. Templates Debian (`make create_templates`)

Script: `automation/scripts/templates/create_templates.sh`, amb les plantilles `preseed.cfg.tpl` i `late.sh.tpl`.

Procediment (totalment desatès):
1. Descarrega la ISO fixada i en verifica el SHA256.
2. Extreu la ISO, hi incrusta el `preseed.cfg` i un script final (`late.sh`) a l'initrd, ajusta el menú d'arrencada i genera una ISO desatesa (`artifacts/build/<tipus>/auto.iso`).
3. Crea la VM del template (grup `/VirtualCorp/templates`), l'arrenca i espera que l'instal·lador l'apagui.
4. Treu la ISO, elimina la NIC NAT (només s'usa durant la instal·lació), i crea el snapshot `base`.

| Característica | `tpl-debian-server` | `tpl-debian-desktop` |
|---|---|---|
| Ús | Servidors CPD/DMZ i impressores | PCs de plantes, consergeria i expositors |
| Disc | 8 GB | 20 GB |
| Paquets | `openssh-server`, `sudo`, `ca-certificates`, `iputils-ping` (sense entorn gràfic) | Els anteriors + `xorg`, `lxqt-core`, `sddm`, `falkon`; es purga `firefox-esr` |
| Usuari | `sysadmin` (sudo sense contrasenya) | idem |
| Xarxa | DHCP | DHCP |
| SSH | Només per clau (`PasswordAuthentication no`, `PermitRootLogin no`) | idem |

Claus autoritzades a `sysadmin` des del template: clau pública del professor (`configs/ssh/vcorp_auditor.pub`) i la clau personal (`configs/ssh/vcorp_sysadmin.pub`). La contrasenya de `sysadmin` és aleatòria, es genera a `artifacts/secrets/` i no es versiona.

Preparació per clonar: `machine-id` buit i claus de host SSH eliminades (es regeneren al primer arrencament amb `vcorp-sshkeys.service`). El hostname de cada clon es pren del "serial" DMI que fixa el desplegament (`vcorp-sethostname.service`).

## 4. Desplegament d'equipament (`make deploy_equipment`)

Script: `automation/scripts/deploy/deploy_equipment.sh`. Per cada línia de `configs/equipment.csv`:
- `server` / `desktop`: clon enllaçat del snapshot `base` del template corresponent (`--options link`), assigna RAM i CPUs, connecta les NICs a xarxes internes (mai NAT), fixa el serial DMI (hostname) i comprova que la màquina arrenca (25 s) abans d'apagar-la.
- `pve`: crida `install_pve.sh`.
- Les màquines que ja existeixen s'ometen (el desplegament es pot repetir).

Limitació: el disc d'un clon enllaçat és diferencial i no es pot redimensionar; la mida la fixa el template.

## 5. pve01 (Proxmox VE, instal·lació desatesa)

Script: `automation/scripts/deploy/install_pve.sh` i plantilla `answer.toml.tpl`.

1. Genera `answer.toml` amb: FQDN `pve01.vcorp.local`, xarxa estàtica `10.17.0.133/26`, passarel·la `10.17.0.129`, DNS `1.1.1.1`, teclat/zona horària, `root-ssh-keys` (professor + alumne), contrasenya de `root` aleatòria (hash), `reboot-mode = "power-off"`, i disc `ext4` (LVM + LVM-thin, sense ZFS).
2. Valida el fitxer amb `proxmox-auto-install-assistant validate-answer`.
3. Prepara la ISO amb `prepare-iso --fetch-from iso`.
4. Crea la VM, l'arrenca i espera que s'apagui en acabar la instal·lació.

Recursos de la VM `pve01`:

| Recurs | Valor |
|---|---|
| vCPU | 4 |
| RAM | 6144 MB (inferior als 8 GB orientatius: l'equip físic té 14 GiB i cal deixar marge per als 4 routers) |
| Disc | 64 GB |
| Xarxa | 1 NIC interna `privada`, MAC fixa `08:00:27:A1:00:01` |
| Virtualització anidada | `VBoxManage modifyvm pve01 --nested-hw-virt on` (dins l'script) |

## 6. Xarxes internes i màquines

| Xarxa | Subxarxa | Router i passarel·la | Màquines |
|---|---|---|---|
| `privada` | 10.17.0.128/26 | mikrotik0 10.17.0.129 | pve01 (.133), dbsrv (.134), infosrv (.135) |
| `dmz` | 10.17.0.192/27 | mikrotik0 10.17.0.193 | websrv (.197) |
| `pl0` | 10.17.0.0/25 | mikrotik1 10.17.0.1 | printer0 (.65), expo1-4 (.33-.36), conserge1-2 |
| `pl1` | 10.17.1.0/24 | mikrotik2 10.17.1.1 | printer1 (.65), pc1-01 |
| `pl2` | 10.17.2.0/24 | mikrotik2 10.17.2.1 | printer2 (.65), pc2-01 |
| `pl3` | 10.17.3.0/25 | mikrotik3 10.17.3.1 | printer3 (.65), pc3-01 |
| `pl3_direccio` | 10.17.3.128/25 | mikrotik3 10.17.3.129 | direccio1-3 |
| `rt0_1` | 10.17.0.224/30 | mikrotik0 .225, mikrotik1 .226 | enllaç entre routers |
| `rt1_2` | 10.17.0.228/30 | mikrotik1 .229, mikrotik2 .230 | enllaç entre routers |
| `rt2_3` | 10.17.0.232/30 | mikrotik2 .233, mikrotik3 .234 | enllaç entre routers |

Només `mikrotik0` té una NIC en mode NAT (sortida a Internet). Excepte `pve01`, les màquines obtindran la IP per DHCP quan el servei estigui desplegat; les IP indicades són les previstes.

## 7. Accés SSH

- Professor: `configs/ssh/vcorp_auditor.pub` autoritzada a `sysadmin` (Debian), a `vcorp_auditor` (routers) i a `root` (pve01).
- Alumne: `configs/ssh/vcorp_sysadmin.pub` autoritzada als mateixos sistemes.
- No s'ha versionat cap clau privada ni contrasenya.

## 8. Comprovacions realitzades

- Templates: 2 templates amb snapshot `base`, NIC eliminada. Un clon temporal amb NAT de proves va permetre entrar per SSH amb la clau personal, confirmar les dues claus a `authorized_keys`, el hostname del clon, que el desktop porta `falkon` i `lxqt-core` sense `firefox`, i que `sddm` està actiu. Els clons de prova es van eliminar.
- Desplegament: `bash automation/scripts/deploy/check_equipment.sh` (sortida a `docs/evidencies/check_equipment.txt`): 20 màquines, clons enllaçats excepte `pve01`, xarxes correctes i cap NAT excepte `mikrotik0`.
- Routers: ping entre routers i a Internet; SSH amb clau.
- pve01: `pve-manager/9.2.2`; mòduls `kvm_intel` i `kvm` carregats, `/dev/kvm` present, `nproc` = 4; IP `10.17.0.133/26` a `vmbr0`; dues claus autoritzades; ping als quatre routers (`10.17.0.225`, `.226`, `.230`, `.234`) i a `1.1.1.1` amb 0 % de pèrdua.

## 9. Incidències i decisions

1. **Clau del professor sobreescrita.** `create_ssh_keys.sh` generava un parell `vcorp_auditor` propi i en copiava la pública a `configs/ssh/`. Es va restaurar la clau original des de `upstream/main`, es va eliminar la generació d'aquesta clau de l'script i es van recrear els routers.
2. **Noms de xarxa.** Els routers usaven `r0-r1`, `r1-r2`, `r2-r3` i `pl3-direccio`. Es van canviar als noms de l'enunciat (`rt0_1`, `rt1_2`, `rt2_3`, `pl3_direccio`) i s'hi va afegir la xarxa `privada` a `mikrotik0` (`10.17.0.129/26`) perquè `pve01` tingui passarel·la.
3. **Certificat de `download.proxmox.com`.** Cobreix `enterprise.proxmox.com` i els seus nodes però no aquest nom (diagnosticat amb `openssl s_client`). S'ha fixat `enterprise.proxmox.com`; versió i SHA256 no canvien.
4. **`log_error` no existia** (només `log_err`). S'ha afegit un àlies a `common.sh`.
5. **`ARTIFACTS_DIR` inconsistent** entre `.env.example` i `common.sh`: les rutes noves parteixen de `PROJECT_ROOT`.
6. **RAM de pve01:** 6 GB en lloc de 8 GB, pel marge amb els routers.
7. **Consergeria:** es desplega amb el template Debian Desktop (l'enunciat de l'activitat 2 l'hi assigna), tot i que l'enunciat general parla d'equips Windows.
8. **Nombre de PCs d'usuari:** l'enunciat diu "diversos"; s'ha desplegat un PC per planta i tres de direcció.
9. **Contrasenyes dels routers:** `router_base.sh` fixa una contrasenya de laboratori heredada de l'activitat 1 (millora pendent: eliminar-la).

## 10. Disseny de xarxa

El disseny lògic i físic actualitzat és a `docs/disseny_xarxa.pdf`.
