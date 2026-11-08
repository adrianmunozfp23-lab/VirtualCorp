#!/bin/sh
set -e
U=sysadmin

# --- SSH: claves del profesor y del alumno ---
install -d -m 700 -o $U -g $U /home/$U/.ssh
cat > /home/$U/.ssh/authorized_keys <<'EOF'
__KEYS__
EOF
chown $U:$U /home/$U/.ssh/authorized_keys
chmod 600 /home/$U/.ssh/authorized_keys

echo "$U ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-sysadmin
chmod 440 /etc/sudoers.d/90-sysadmin

mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/10-vcorp.conf

# --- Preparar el disco para clonar: sin machine-id ni claves de host ---
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id /etc/ssh/ssh_host_*

cat > /etc/systemd/system/vcorp-sshkeys.service <<'EOF'
[Unit]
Description=Generate SSH host keys if missing
Before=ssh.service
ConditionPathExists=!/etc/ssh/ssh_host_ed25519_key
[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A
[Install]
WantedBy=multi-user.target
EOF

# --- Hostname por clon: se lee del "serial" DMI que fija el despliegue ---
cat > /usr/local/sbin/vcorp-sethostname <<'EOF'
#!/bin/sh
n=$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)
case "$n" in ""|*[!a-z0-9-]*) exit 0;; esac
[ "$(cat /etc/hostname)" = "$n" ] && exit 0
hostname "$n"; echo "$n" > /etc/hostname
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$n/" /etc/hosts
EOF
chmod 755 /usr/local/sbin/vcorp-sethostname

cat > /etc/systemd/system/vcorp-sethostname.service <<'EOF'
[Unit]
Description=Set hostname from VM DMI serial
DefaultDependencies=no
Before=network-pre.target sysinit.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vcorp-sethostname
[Install]
WantedBy=sysinit.target
EOF

systemctl enable vcorp-sshkeys.service vcorp-sethostname.service
__EXTRA__
