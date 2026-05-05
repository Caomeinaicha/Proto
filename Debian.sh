#!/bin/bash

## 重装脚本
## Debian 13


[[ "$EUID" -ne '0' ]] && echo "错误: 必须以 root 权限运行!" && exit 1;

# --- 配置区 ---
tmpWORD=$(openssl rand -base64 12)
sshPORT='1366'
# --------------

# 1. 基础依赖安装
echo "正在检查必要依赖..."
for cmd in wget awk grep sed cut lsblk cpio gzip find openssl; do
    if ! command -v $cmd >/dev/null 2>&1; then
        apt-get update && apt-get install -y $cmd || yum install -y $cmd
    fi
done

# 2. 自动提取网络参数
echo "正在提取网络参数..."
interface=$(ip route show default | grep "^default" | awk '{print $5}' | head -n1)
iAddr=$(ip addr show dev $interface | grep "inet " | head -n1 | awk '{print $2}')
ipAddr=$(echo ${iAddr} | cut -d'/' -f1)
ipMaskNum=$(echo ${iAddr} | cut -d'/' -f2)
ipGate=$(ip route show default | grep "^default" | awk '{print $3}' | head -n1)

# 提取 IPv6
rawIp6=$(ip -6 addr show dev $interface | grep "scope global" | head -n1 | awk '{print $2}')
if [ -n "$rawIp6" ]; then
    ip6Addr=$(echo $rawIp6 | cut -d'/' -f1)
    ip6Prefix=$(echo $rawIp6 | cut -d'/' -f2)
    ip6Gate=$(ip -6 route show default | grep "^default" | awk '{print $3}' | head -n1)
fi

function calc_mask() {
    local bits=$1
    [[ ! "$bits" =~ ^[0-9]+$ ]] && bits=24
    local full_octets=$(( bits / 8 )); local partial_bits=$(( bits % 8 )); local mask=""
    for ((i=0; i<4; i++)); do
        if [ $i -lt $full_octets ]; then mask+="255";
        elif [ $i -eq $full_octets ]; then mask+=$((256 - 2**(8-partial_bits)));
        else mask+="0"; fi
        [ $i -lt 3 ] && mask+="."
    done
    echo $mask
}
ipMask=$(calc_mask $ipMaskNum)

# 3. 准备内核与 initrd
mkdir -p /boot/newinstall
wget --no-check-certificate -qO '/boot/newinstall/initrd.gz' "http://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
wget --no-check-certificate -qO '/boot/newinstall/vmlinuz' "http://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"

# 4. 注入配置逻辑
echo "正在打包自定义 initrd..."
mkdir -p /tmp/rebuild; cd /tmp/rebuild
gzip -d < /boot/newinstall/initrd.gz | cpio -idm --no-absolute-filenames >/dev/null 2>&1

# 写入处理脚本
cat > /tmp/rebuild/net-fix.sh <<LATESCRIPT
#!/bin/sh
REAL_IFACE=\$(ip -4 route show default | awk '{print \$5}' | head -n1)
[ -z "\$REAL_IFACE" ] && REAL_IFACE=\$(ip -o link show | awk -F': ' '{print \$2}' | grep -v 'lo' | head -n1)

# 修正 SSH 配置：确保 Port 和 Login 权限正确写入
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if grep -q "^Port" /etc/ssh/sshd_config; then
    sed -i "s/^Port.*/Port ${sshPORT}/" /etc/ssh/sshd_config
else
    echo "Port ${sshPORT}" >> /etc/ssh/sshd_config
fi

# 只有在主脚本检测到 IPv6 时，才向 net-fix.sh 写入 IPv6 配置逻辑
$( [ -n "$ip6Addr" ] && cat <<EOF
if ! grep -q "inet6" /etc/network/interfaces; then
    echo "" >> /etc/network/interfaces
    echo "auto \$REAL_IFACE" >> /etc/network/interfaces
    echo "iface \$REAL_IFACE inet6 static" >> /etc/network/interfaces
    echo "    address $ip6Addr/$ip6Prefix" >> /etc/network/interfaces
    echo "    gateway $ip6Gate" >> /etc/network/interfaces
    echo "    dns-nameservers 2606:4700:4700::1111 2001:4860:4860::8888" >> /etc/network/interfaces
fi
EOF
)

# DNS解析
cat > /etc/resolv.conf <<EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
LATESCRIPT

chmod +x /tmp/rebuild/net-fix.sh

# 生成 preseed.cfg
cat >/tmp/rebuild/preseed.cfg <<EOF
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap string us
d-i clock-setup/utc boolean true
d-i time/zone string UTC

d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/get_ipaddress string $ipAddr
d-i netcfg/get_netmask string $ipMask
d-i netcfg/get_gateway string $ipGate
d-i netcfg/get_nameservers string 1.1.1.1 8.8.8.8
d-i netcfg/confirm_static boolean true

$( [[ -n "$ip6Addr" ]] && echo "
d-i netcfg/disable_dhcpv6 boolean true
d-i netcfg/get_ip6address string ${ip6Addr}/${ip6Prefix}
d-i netcfg/get_ip6gateway string $ip6Gate
d-i netcfg/get_ip6nameservers string 2606:4700:4700::1111 2001:4860:4860::8888" )

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password $(openssl passwd -1 "$tmpWORD")

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

find . | cpio -H newc -o | gzip -9 > /boot/newinstall/initrd.img
cd /root; rm -rf /tmp/rebuild

# 5. 写入引导
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

echo "------------------------------------------------"
echo "IPv4 地址: $ipAddr"
echo "IPv6 地址: ${ip6Addr:-未检测到}"
echo "SSH 端口: $sshPORT"
echo "Root 密码: $tmpWORD"
echo "------------------------------------------------"
echo "系统将在 5 秒后重启，安装完成后请使用上述信息登录。"
sleep 5
reboot -f