# VirtualCorp

VirtualCorp is a virtual networking lab for designing and deploying a branch office network. It uses MikroTik RouterOS CHR virtual machines on VirtualBox and automates their setup with shell scripts and Make.

Read the [full project statement](docs/statement.html) for the scenario, requirements, and detailed assignment.

## Getting started

### 1. Install prerequisites

Install GNU Make, VirtualBox with `VBoxManage`, `curl`, `unzip`, and the OpenSSH client. Make sure hardware virtualization is enabled on the host.

### 2. Adapt the environment

From the project root, create the local Make configuration and edit it for your machine:

```bash
cp .env.example .env
```

Update paths such as `PROJECT_ROOT`, `ARTIFACTS_DIR`, `CONFIGS_DIR`, and the SSH key directories as needed. The `.env` file uses GNU Make assignments and is ignored by Git.

### 3. Create the routers

Run `make` to display the available targets. Generate the SSH keys, then deploy the routers:

```bash
make ssh-keys
make deploy-routers
```

The deployment downloads the RouterOS CHR disk image when it is missing and creates `mikrotik0` through `mikrotik3` in VirtualBox.

### 4. Check the lab

Confirm that all four VMs appear in VirtualBox, under the `/VirtualCorp/Routers` group. Open each router's console and check that it can reach the other routers' transit addresses:

| Router | Transit address |
| --- | --- |
| `mikrotik0` | `10.1.0.225` |
| `mikrotik1` | `10.1.0.226` |
| `mikrotik2` | `10.1.0.230` |
| `mikrotik3` | `10.1.0.234` |

From each router, ping the other three addresses. For example:

```text
ping 10.1.0.226 count=4
```

Then check internet connectivity from each router:

```text
ping 1.1.1.1 count=4
```

The lab is ready when all four routers can reach one another and each can reach the internet.

## Activitat 3: Ansible i VPN WireGuard

Tot el codi és a `automation/ansible/` (executeu les ordres des d'aquest directori). Cal `ansible`, `wireguard-tools` i les col·leccions `ansible.netcommon` i `community.routeros`.

```bash
ansible-playbook playbooks/start_routers.yml      # inicia mikrotik0..3 (idempotent)
ansible-playbook playbooks/stop_routers.yml       # atura els routers de manera ordenada
ansible-playbook playbooks/configure_wireguard.yml  # servidor WireGuard + fitxer del client
```

### Adreçament i variables (`inventories/group_vars/all.yml`)

| Variable | Valor |
| --- | --- |
| Túnel (`wg_tunnel_prefix`) | `10.17.10.0/24` |
| Servidor (`wg_server_address`) | `10.17.10.1/24` a `wg-vcorp` (mikrotik0) |
| Client `client1` | `10.17.10.2` |
| Port UDP (`wg_listen_port`) | `51820` |
| AllowedIPs del client | `10.17.0.0/22` (xarxes VirtualCorp) + `10.17.10.0/24` (túnel); túnel dividit, sense `0.0.0.0/0` |
| Endpoint (`wg_endpoint_host`) | `127.0.0.1` a la documentació (valor fictici; el real no es publica) |

Les claus i el fitxer del client es desen amb permisos restrictius a `artifacts/vpn/` (ignorat per Git); les tasques que les manegen porten `no_log: true`.

### Reenviament UDP de VirtualBox

Una regla NAT de la VM mikrotik0 (`wg-vcorp,udp,127.0.0.1,51820,,51820`) porta el port UDP 51820 del node de control al port 51820 de mikrotik0. Es crea amb `VBoxManage` en una tasca local, només si no existeix. L'adreça d'escolta `127.0.0.1` només permet clients al mateix ordinador.

### Regles de tallafoc afegides a mikrotik0

1. `input`: accept UDP 51820 (abans de qualsevol regla que descarti).
2. `forward`: accept `in-interface=wg-vcorp` cap a `10.17.0.0/22`.
3. `forward`: drop de la resta del trànsit que entra per `wg-vcorp`.

Sense NAT entre el túnel i les xarxes internes: els altres routers coneixen la ruta de retorn cap a `10.17.10.0/24` via RIP (mikrotik0 la redistribueix des de la interfície connectada).

### Proves realitzades

Evidències a `docs/evidencies/ansible_start_stop.txt` i `docs/evidencies/vpn_validacio.txt`: segona execució dels playbooks sense canvis, handshake del peer, ping al túnel i a cada xarxa autoritzada, SSH a `10.17.10.1` pel túnel, Internet directe (túnel dividit), desactivar/reactivar el túnel i persistència després de reiniciar mikrotik0.
