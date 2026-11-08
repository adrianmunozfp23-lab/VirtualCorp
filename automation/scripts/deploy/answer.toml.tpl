[global]
keyboard = "es"
country = "es"
fqdn = "__FQDN__"
mailto = "root@localhost"
timezone = "Europe/Madrid"
root-password-hashed = "__PWHASH__"
root-ssh-keys = [
__KEYLIST__
]
reboot-mode = "power-off"

[network]
source = "from-answer"
cidr = "__CIDR__"
dns = "__DNS__"
gateway = "__GATEWAY__"
filter.ID_NET_NAME_MAC = "enx__MACLOWER__"

[disk-setup]
filesystem = "ext4"
disk-list = ["sda"]
