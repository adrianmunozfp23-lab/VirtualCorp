# Actividad 2: templates Debian, clones enlazados y pve01 (delegación 17, 10.17.0.0/16)

## 1. Requisitos previos

- Ubuntu con VirtualBox 7.2.x (`VBoxManage`), GNU Make, `curl`, `xorriso`, `cpio`, `gzip` y `openssl`.
- `proxmox-auto-install-assistant`: se instala desde el repositorio de Proxmox (`pve-no-subscription`, trixie), descargando el `.deb` con `apt download` e instalándolo en local.
- Virtualización asistida por hardware (VT-x/AMD-V) activada en la BIOS.
- Claves SSH generadas (`make ssh-keys`) y routers desplegados (`make deploy-routers`).

## 2. Versiones fijas, URL y variables

Las versiones NO se buscan automáticamente. Están fijadas en `infrastructure/bash/common.sh` (valores por defecto `${VAR:-...}`, que se pueden sobrescribir con variables de entorno o con `.env`).

| Componente | Versión | Fichero | SHA256 |
|---|---|---|---|
| Debian (Trixie, amd64) | 13.7.0 | `debian-13.7.0-amd64-netinst.iso` | `a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355` |
| Proxmox VE | 9.2-1 | `proxmox-ve_9.2-1.iso` | `4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c` |

- URL de Debian: `https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/debian-13.7.0-amd64-netinst.iso`
- URL de Proxmox: `https://enterprise.proxmox.com/iso/proxmox-ve_9.2-1.iso` (ver incidencias: `download.proxmox.com` tiene un certificado que no cubre ese nombre).
- Las ISOs se guardan en `artifacts/images/iso/` y NO se versionan (`.gitignore`). La función `fetch_iso` verifica el SHA256 y reanuda las descargas interrumpidas.
- Otras variables de `common.sh`: nombres de los templates, tamaños de disco, parámetros de `pve01` (`PVE_*`) y rutas (`ISO_DIR`, `BUILD_DIR`, `SECRETS_DIR`, `EQUIPMENT_FILE`).
- Lista de equipos: `configs/equipment.csv` (`nombre;tipo;grupo;ram_mb;cpus;redes`).

Actualización de versiones: crear una rama Git específica, cambiar las variables (versión y SHA256), probar `create_templates` y el despliegue en un entorno de pruebas, y fusionar con `main` solo si las pruebas son satisfactorias.

## 3. Templates Debian (`make create_templates`)

Script: `automation/scripts/templates/create_templates.sh`, con las plantillas `preseed.cfg.tpl` y `late.sh.tpl`.

Procedimiento (totalmente desatendido):

1. Descarga la ISO fijada y verifica su SHA256.
2. Extrae la ISO, incrusta el `preseed.cfg` y un script final (`late.sh`) en el initrd, ajusta el menú de arranque y genera una ISO desatendida (`artifacts/build/<tipo>/auto.iso`).
3. Crea la VM del template (grupo `/VirtualCorp/templates`), la arranca y espera a que el instalador la apague.
4. Quita la ISO, elimina la NIC NAT (solo se usa durante la instalación) y crea el snapshot `base`.

| Característica | `tpl-debian-server` | `tpl-debian-desktop` |
|---|---|---|
| Uso | Servidores de CPD y DMZ, impresoras | PCs de plantas, consergería y expositores |
| Disco | 8 GB | 20 GB |
| Paquetes | `openssh-server`, `sudo`, `ca-certificates`, `iputils-ping` (sin entorno gráfico) | Los anteriores + `xorg`, `lxqt-core`, `sddm`, `falkon`; se purga `firefox-esr` |
| Usuario | `sysadmin` (sudo sin contraseña) | igual |
| Red | DHCP | DHCP |
| SSH | Solo por clave (`PasswordAuthentication no`, `PermitRootLogin no`) | igual |

Claves autorizadas en `sysadmin` desde el template: la clave pública del profesor (`configs/ssh/vcorp_auditor.pub`) y la clave personal (`configs/ssh/vcorp_sysadmin.pub`). La contraseña de `sysadmin` es aleatoria, se genera en `artifacts/secrets/` y no se versiona.

Preparación para clonar: `machine-id` vacío y claves de host SSH eliminadas (se regeneran en el primer arranque con `vcorp-sshkeys.service`). El hostname de cada clon se toma del "serial" DMI que fija el despliegue (`vcorp-sethostname.service`).

## 4. Despliegue de equipamiento (`make deploy_equipment`)

Script: `automation/scripts/deploy/deploy_equipment.sh`. Para cada línea de `configs/equipment.csv`:

- `server` / `desktop`: clon enlazado del snapshot `base` del template correspondiente (`--options link`), asigna RAM y CPUs, conecta las NICs a redes internas (nunca NAT), fija el serial DMI (hostname) y comprueba que la máquina arranca (25 s) antes de apagarla.
- `pve`: llama a `install_pve.sh`.
- Las máquinas que ya existen se omiten, de modo que el despliegue se puede repetir.

Limitación: el disco de un clon enlazado es diferencial y no se puede redimensionar; su tamaño lo fija el template.

## 5. pve01 (Proxmox VE, instalación desatendida)

Script: `automation/scripts/deploy/install_pve.sh` y plantilla `answer.toml.tpl`.

1. Genera `answer.toml` con: FQDN `pve01.vcorp.local`, red estática `10.17.0.133/26`, puerta de enlace `10.17.0.129`, DNS `1.1.1.1`, teclado y zona horaria, `root-ssh-keys` (profesor + alumno), contraseña de `root` aleatoria (hash), `reboot-mode = "power-off"` y disco `ext4` (LVM + LVM-thin, sin ZFS).
2. Valida el fichero con `proxmox-auto-install-assistant validate-answer`.
3. Prepara la ISO con `prepare-iso --fetch-from iso`.
4. Crea la VM, la arranca y espera a que se apague al terminar la instalación.

Recursos de la VM `pve01`:

| Recurso | Valor |
|---|---|
| vCPU | 4 |
| RAM | 6144 MB (inferior a los 8 GB orientativos: el equipo físico tiene 14 GiB y hay que dejar margen para los 4 routers) |
| Disco | 64 GB |
| Red | 1 NIC interna `privada`, MAC fija `08:00:27:A1:00:01` |
| Virtualización anidada | `VBoxManage modifyvm pve01 --nested-hw-virt on` (dentro del script) |

## 6. Redes internas y máquinas

| Red | Subred | Router y puerta de enlace | Máquinas |
|---|---|---|---|
| `privada` | 10.17.0.128/26 | mikrotik0 10.17.0.129 | pve01 (.133), dbsrv (.134), infosrv (.135) |
| `dmz` | 10.17.0.192/27 | mikrotik0 10.17.0.193 | websrv (.197) |
| `pl0` | 10.17.0.0/25 | mikrotik1 10.17.0.1 | printer0 (.65), expo1-4 (.33-.36), conserge1-2 |
| `pl1` | 10.17.1.0/24 | mikrotik2 10.17.1.1 | printer1 (.65), pc1-01 |
| `pl2` | 10.17.2.0/24 | mikrotik2 10.17.2.1 | printer2 (.65), pc2-01 |
| `pl3` | 10.17.3.0/25 | mikrotik3 10.17.3.1 | printer3 (.65), pc3-01 |
| `pl3_direccio` | 10.17.3.128/25 | mikrotik3 10.17.3.129 | direccio1-3 |
| `rt0_1` | 10.17.0.224/30 | mikrotik0 .225, mikrotik1 .226 | enlace entre routers |
| `rt1_2` | 10.17.0.228/30 | mikrotik1 .229, mikrotik2 .230 | enlace entre routers |
| `rt2_3` | 10.17.0.232/30 | mikrotik2 .233, mikrotik3 .234 | enlace entre routers |

Solo `mikrotik0` tiene una NIC en modo NAT (salida a Internet). Salvo `pve01`, las máquinas obtendrán la IP por DHCP cuando el servicio esté desplegado; las IP indicadas son las previstas.

## 7. Acceso SSH

- Profesor: `configs/ssh/vcorp_auditor.pub` autorizada en `sysadmin` (Debian), en `vcorp_auditor` (routers) y en `root` (pve01).
- Alumno: `configs/ssh/vcorp_sysadmin.pub` autorizada en los mismos sistemas.
- No se ha versionado ninguna clave privada ni contraseña.

## 8. Comprobaciones realizadas

- **Templates:** 2 templates con snapshot `base` y sin NIC. Un clon temporal con NAT de pruebas permitió entrar por SSH con la clave personal, confirmar las dos claves en `authorized_keys`, el hostname del clon, que el desktop lleva `falkon` y `lxqt-core` sin `firefox`, y que `sddm` está activo. Los clones de prueba se eliminaron.
- **Despliegue:** `bash automation/scripts/deploy/check_equipment.sh` (salida en `docs/evidencies/check_equipment.txt`): 20 máquinas, clones enlazados salvo `pve01`, redes correctas y sin NAT salvo `mikrotik0`.
- **Routers:** acceso SSH por clave a `mikrotik0` (usuario `sysadmin`, con las claves de `sysadmin` y `vcorp_auditor` instaladas) y ping de `mikrotik0` a `pve01`. La conectividad hacia el resto de routers y hacia Internet se comprobó desde `pve01`.
- **pve01:** `pve-manager/9.2.2`; módulos `kvm_intel` y `kvm` cargados, `/dev/kvm` presente y `nproc` = 4; IP `10.17.0.133/26` en `vmbr0`; dos claves autorizadas; ping a los cuatro routers (`10.17.0.225`, `.226`, `.230`, `.234`) y a `1.1.1.1` con 0 % de pérdida.

## 9. Incidencias y decisiones

1. **Clave del profesor sobrescrita.** `create_ssh_keys.sh` generaba un par `vcorp_auditor` propio y copiaba su pública a `configs/ssh/`. Se restauró la clave original desde `upstream/main`, se eliminó del script la generación de esa clave y se recrearon los routers.
2. **Nombres de red.** Los routers usaban `r0-r1`, `r1-r2`, `r2-r3` y `pl3-direccio`. Se cambiaron a los nombres del enunciado (`rt0_1`, `rt1_2`, `rt2_3`, `pl3_direccio`) y se añadió la red `privada` a `mikrotik0` (`10.17.0.129/26`) para que `pve01` tenga puerta de enlace.
3. **Certificado de `download.proxmox.com`.** Cubre `enterprise.proxmox.com` y sus nodos pero no ese nombre (diagnosticado con `openssl s_client`). Se fijó `enterprise.proxmox.com`; la versión y el SHA256 no cambian.
4. **`log_error` no existía** (solo `log_err`). Se añadió un alias en `common.sh`.
5. **`ARTIFACTS_DIR` inconsistente** entre `.env.example` y `common.sh`: las rutas nuevas parten de `PROJECT_ROOT`.
6. **RAM de pve01:** 6 GB en lugar de 8 GB, para dejar margen a los routers.
7. **Consergería:** se despliega con el template Debian Desktop (el enunciado de la actividad 2 se lo asigna), aunque el enunciado general habla de equipos Windows.
8. **Número de PCs de usuario:** el enunciado dice "diversos"; se ha desplegado un PC por planta y tres de dirección.
9. **Contraseñas de los routers:** `router_base.sh` fija una contraseña de laboratorio heredada de la actividad 1 (mejora pendiente: eliminarla).
10. **Redes duplicadas en los routers.** `router_base.sh` conecta la NIC 1 y la NIC 2 a la misma red en los routers sin NAT. Es un comportamiento heredado de la actividad 1 que no afecta al funcionamiento.

## 10. Diseño de red

El diseño lógico y físico actualizado está en `docs/disseny_xarxa.pdf`.
