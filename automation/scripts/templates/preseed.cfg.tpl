d-i debian-installer/language string en
d-i debian-installer/country string ES
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select es
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string __HOSTNAME__
d-i netcfg/get_domain string vcorp.local
d-i netcfg/wireless_wep string
d-i hw-detect/load_firmware boolean false

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/cdrom/set-next boolean false
d-i apt-setup/cdrom/set-failed boolean false
d-i apt-setup/non-free-firmware boolean false

d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string sysadmin
d-i passwd/username string sysadmin
d-i passwd/user-password-crypted password __PWHASH__

d-i clock-setup/utc boolean true
d-i time/zone string Europe/Madrid
d-i clock-setup/ntp boolean true

d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i base-installer/install-recommends boolean false
d-i pkgsel/run_tasksel boolean false
d-i pkgsel/include string __PKGS__
d-i pkgsel/install-recommends boolean false
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false

d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string /dev/sda

d-i preseed/late_command string cp -a /vcorp /target/root/vcorp-setup; in-target sh /root/vcorp-setup/late.sh; rm -rf /target/root/vcorp-setup

d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/poweroff boolean true
