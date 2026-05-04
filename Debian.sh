#!/bin/bash
## 重装脚本 - Debian 13

[[ "$EUID" -ne 0 ]] && echo "错误: 必须以 root 权限运行!" && exit 1

# --- 配置 ---
tmpPASS=$(openssl rand -base64 12)
sshPORT=1366
# ----------------

# 1. 安装必要依赖
for cmd in wget awk grep sed cut lsblk cpio gzip find openssl iproute2; do
    command -v $cmd >/dev/null 2>&1 || (apt-get update && apt-get install -y $cmd || yum install -y $cmd)
done

# 2. 网络信息函数
get_net_info() {
    proto=$1       # ipv4 或 ipv6
    iface=$(ip route show default | awk '/^default/ {print $5}' | head -n1)
    [ -z "$iface" ] && iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)

    if [ "$proto" = "ipv4" ]; then
        addr=$(ip -4 addr show dev "$iface" | awk '/inet /{print $2}' | head -n1)
        ip=${addr%%/*}
        mask_bits=${addr#*/}
        mask=$(for i in {1..4}; do
            if [ $i -le $((mask_bits/8)) ]; then echo -n 255; 
            elif [ $i -eq $((mask_bits/8+1)) ]; then echo -n $((256 - 2**(8-(mask_bits%8)))); 
            else echo -n 0; fi
            [ $i -lt 4 ] && echo -n "."
        done)
        gate=$(ip route show default | awk '/^default/ {print $3}' | head -n1)
        echo "$iface $ip $mask $gate"
    else
        addr=$(ip -6 addr show dev "$iface" | awk '/scope global/ {print $2}' | head -n1)
        [ -z "$addr" ] && return
        ip=${addr%%/*}
        prefix=${addr#*/}
        gate=$(ip -6 route show default | awk '/^default/ {print $3}' | head -n1)
        echo "$iface $ip $prefix $gate"
    fi
}

read IFACE IPV4_ADDR IPV4_MASK IPV4_GATE <<< $(get_net_info ipv4)
read _ IPV6_ADDR IPV6_PREFIX IPV6_GATE <<< $(get_net_info ipv6 || echo "")

# 3. 准备内核 & initrd
mkdir -p /boot/newinstall
wget -qO /boot/newinstall/initrd.gz "http://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
wget -qO /boot/newinstall/vmlinuz "http://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"

# 4. 打包自定义 initrd
mkdir -p /tmp/rebuild && cd /tmp/rebuild
gzip -d < /boot/newinstall/initrd.gz | cpio -idm --no-absolute-filenames >/dev/null 2>&1

# 写入网络 & SSH fix 脚本
cat > net-fix.sh <<EOF
#!/bin/sh
IFACE=$IFACE

# SSH 配置
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
grep -q "^Port" /etc/ssh/sshd_config && sed -i "s/^Port.*/Port $sshPORT/" /etc/ssh/sshd_config || echo "Port $sshPORT" >> /etc/ssh/sshd_config

# IPv4 配置
cat > /etc/network/interfaces <<IPV4
auto \$IFACE
iface \$IFACE inet static
    address $IPV4_ADDR
    netmask $IPV4_MASK
    gateway $IPV4_GATE
    dns-nameservers 1.1.1.1 8.8.8.8
IPV4

# IPv6 配置
EOF

if [ -n "$IPV6_ADDR" ]; then
cat >> net-fix.sh <<IPV6
echo "" >> /etc/network/interfaces
echo "iface \$IFACE inet6 static" >> /etc/network/interfaces
echo "    address $IPV6_ADDR/$IPV6_PREFIX" >> /etc/network/interfaces
echo "    gateway $IPV6_GATE" >> /etc/network/interfaces
echo "    accept_ra 2" >> /etc/network/interfaces
echo "    dns-nameservers 2606:4700:4700::1111 2001:4860:4860::8888" >> /etc/network/interfaces
IPV6
fi

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
chmod +x net-fix.sh

# 5. preseed.cfg
cat > preseed.cfg <<EOF
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap string us
d-i clock-setup/utc boolean true
d-i time/zone string UTC

d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/get_ipaddress string $IPV4_ADDR
d-i netcfg/get_netmask string $IPV4_MASK
d-i netcfg/get_gateway string $IPV4_GATE
d-i netcfg/get_nameservers string 1.1.1.1 8.8.8.8
d-i netcfg/confirm_static boolean true

$( [ -n "$IPV6_ADDR" ] && echo "
d-i netcfg/disable_dhcpv6 boolean true
d-i netcfg/get_ip6address string $IPV6_ADDR/$IPV6_PREFIX
d-i netcfg/get_ip6gateway string $IPV6_GATE
d-i netcfg/get_ip6nameservers string 2606:4700:4700::1111 2001:4860:4860::8888" )

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password $(openssl passwd -1 "$tmpPASS")

d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

tasksel tasksel/first multiselect minimal
d-i pkgsel/include string openssh-server wget curl net-tools
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default
d-i finish-install/reboot_in_progress note

d-i preseed/late_command string cp /net-fix.sh /target/tmp/net-fix.sh; in-target sh /tmp/net-fix.sh
EOF

# 打包 initrd
find . | cpio -H newc -o | gzip -9 > /boot/newinstall/initrd.img
cd /root && rm -rf /tmp/rebuild

# GRUB
cat > /etc/grub.d/40_custom <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry 'Automatic Install Debian 13 (Dual-Stack Fixed)' {
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    search --no-floppy --set=root --file /boot/newinstall/vmlinuz
    linux /boot/newinstall/vmlinuz auto=true priority=critical file=/preseed.cfg --- quiet
    initrd /boot/newinstall/initrd.img
}
EOF
chmod +x /etc/grub.d/40_custom
update-grub || grub2-mkconfig -o /boot/grub2/grub.cfg
grub-reboot 'Automatic Install Debian 13 (Dual-Stack Fixed)'

echo "IPv4: $IPV4_ADDR"
echo "IPv6: ${IPV6_ADDR:-未检测到}"
echo "SSH: $sshPORT"
echo "Root: $tmpPASS"
sleep 5
reboot -f