#!/bin/bash

## Debian 13 网络重装脚本
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

# 2. 智能提取网络参数
echo "正在提取网络参数..."
interface=$(ip route show default | grep "^default" | awk '{print $5}' | head -n1)
[ -z "$interface" ] && interface=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n1)

# 提取 IPv4 核心参数
iAddr=$(ip -4 addr show dev $interface scope global | grep -w "inet" | head -n1 | awk '{print $2}')
if [ -z "$iAddr" ]; then
    echo "错误: 无法获取物理网卡的 IPv4 地址！"
    exit 1
fi
ipAddr=$(echo "${iAddr}" | cut -d'/' -f1)
ipMaskNum=$(echo "${iAddr}" | cut -d'/' -f2)
ipGate=$(ip route show default dev $interface | grep "^default" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)
[ -z "$ipGate" ] && ipGate=$(ip route show default | grep "^default" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)

# 提取 IPv6 核心参数
rawIp6=$(ip -6 addr show dev $interface scope global | grep -w "inet6" | head -n1 | awk '{print $2}')
if [ -n "$rawIp6" ]; then
    ip6Addr=$(echo "$rawIp6" | cut -d'/' -f1)
    ip6Prefix=$(echo "$rawIp6" | cut -d'/' -f2)
    ip6Gate=$(ip -6 route show default dev $interface | grep "^default" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)
    [ -z "$ip6Gate" ] && ip6Gate=$(ip -6 route show default | grep "^default" | awk '{for(i=1;i<=NF;i++) if($i=="via") print $(i+1)}' | head -n1)
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

# 【核心逻辑：智能判断是否为 NAT 内网环境】
is_nat=false
case "$ipAddr" in
    10.*|172.16.*|172.17.*|172.18.*|172.19.*|172.20.*|172.21.*|172.22.*|172.23.*|172.24.*|172.25.*|172.26.*|172.27.*|172.28.*|172.29.*|172.30.*|172.31.*|192.168.*)
        is_nat=true
        echo "检测到当前为 NAT 架构，将使用 DHCP 模式安装。"
        ;;
    *)
        echo "检测到当前为传统公网 IP 架构，将使用 Static 静态注入模式安装。"
        ;;
esac

# 3. 准备内核与 initrd
mkdir -p /boot/newinstall
wget --no-check-certificate -qO '/boot/newinstall/initrd.gz' "http://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
wget --no-check-certificate -qO '/boot/newinstall/vmlinuz' "http://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"

# 4. 注入配置逻辑
echo "正在打包自定义 initrd..."
mkdir -p /tmp/rebuild; cd /tmp/rebuild
gzip -d < /boot/newinstall/initrd.gz | cpio -idm --no-absolute-filenames >/dev/null 2>&1

# 写入处理脚本 (使用单引号封闭 LATESCRIPT，防止当前 shell 变量污染破坏)
cat > /tmp/rebuild/net-fix.sh << 'LATESCRIPT'
#!/bin/sh
REAL_IFACE=$(ip -4 route show default | awk '{print $5}' | head -n1)
[ -z "$REAL_IFACE" ] && REAL_IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo' | head -n1)

# 修正 SSH 配置
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
if grep -q "^Port" /etc/ssh/sshd_config; then
    sed -i "s/^Port.*/Port __SSH_PORT__/" /etc/ssh/sshd_config
else
    echo "Port __SSH_PORT__" >> /etc/ssh/sshd_config
fi

# IPv6 配置
if [ -n "__IP6_ADDR__" ] && [ "__IP6_ADDR__" != " " ]; then
    if ! grep -q "inet6" /etc/network/interfaces; then
        echo "" >> /etc/network/interfaces
        echo "auto $REAL_IFACE" >> /etc/network/interfaces
        echo "iface $REAL_IFACE inet6 static" >> /etc/network/interfaces
        echo "    address __IP6_ADDR__/__IP6_PREFIX__" >> /etc/network/interfaces
        echo "    gateway __IP6_GATE__" >> /etc/network/interfaces
        echo "    accept_ra 0" >> /etc/network/interfaces
    fi
fi

# DNS 修复
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 2001:4860:4860::8888
EOF

echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
LATESCRIPT

# 精准替换模板变量
sed -i "s/__SSH_PORT__/${sshPORT}/g" /tmp/rebuild/net-fix.sh
sed -i "s/__IP6_ADDR__/${ip6Addr}/g" /tmp/rebuild/net-fix.sh
sed -i "s/__IP6_PREFIX__/${ip6Prefix}/g" /tmp/rebuild/net-fix.sh
sed -i "s/__IP6_GATE__/${ip6Gate}/g" /tmp/rebuild/net-fix.sh

chmod +x /tmp/rebuild/net-fix.sh

# 生成基础 preseed.cfg 头
cat >/tmp/rebuild/preseed.cfg <<EOF
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap string us
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i netcfg/choose_interface select auto
EOF

# 根据环境动态追加网络配置到 preseed.cfg
if [ "$is_nat" = true ]; then
    # NAT/Lightsail 专用：无脑自动化获取内网 IP
    cat >>/tmp/rebuild/preseed.cfg <<EOF
d-i netcfg/disable_autoconfig boolean false
d-i netcfg/get_nameservers string 8.8.8.8 1.1.1.1
EOF
else
    # 传统静态公网 IP 专用：强制注入静态 IP
    cat >>/tmp/rebuild/preseed.cfg <<EOF
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/get_ipaddress string $ipAddr
d-i netcfg/get_netmask string $ipMask
d-i netcfg/get_gateway string $ipGate
d-i netcfg/get_nameservers string 8.8.8.8 1.1.1.1
d-i netcfg/confirm_static boolean true
EOF
fi

# 追加剩余的通用 preseed 配置
cat >>/tmp/rebuild/preseed.cfg <<EOF
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

# 5. 写入引导 (兼容独立 /boot 分区)
boot_dir="/boot"
[ -d /boot/grub ] || [ -d /boot/grub2 ] || boot_dir=""

cat > /etc/grub.d/40_custom <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry 'Automatic Install Debian 13 (Universal Dual-Stack)' {
    insmod part_gpt
    insmod part_msdos
    insmod ext2
    search --no-floppy --set=root --file ${boot_dir}/newinstall/vmlinuz
    linux ${boot_dir}/newinstall/vmlinuz auto=true priority=critical file=/preseed.cfg --- quiet
    initrd ${boot_dir}/newinstall/initrd.img
}
EOF

chmod +x /etc/grub.d/40_custom
update-grub || grub2-mkconfig -o /boot/grub2/grub.cfg
grub-reboot 'Automatic Install Debian 13 (Universal Dual-Stack)'

echo "------------------------------------------------"
echo "SSH  端口: $sshPORT"
echo "IPv4 地址: $ipAddr (注:若是NAT机，请使用对应外网IP登录)"
echo "IPv6 地址: ${ip6Addr:-无}"
echo "Root 密码: $tmpWORD"
echo "------------------------------------------------"
echo "系统将在 5 秒后重启，重装大约需要 3~8 分钟，请耐心等待。"
sleep 5
reboot -f