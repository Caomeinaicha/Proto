#!/bin/bash

BBR_CONF="/etc/sysctl.d/99-bbr.conf"

# 更新系统并安装依赖
apt update && apt upgrade -y && apt install -y systemd-timesyncd curl openssl jq unzip xz-utils

# 设置时区
timedatectl set-timezone Asia/Singapore

# 开启 BBR 并设置网络缓冲区
tee "$BBR_CONF" >/dev/null <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.ip_local_port_range=1024 65535
EOF

sysctl --system >/dev/null

# 设置 IPv4 优先
sed -i 's/^#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf

# 显示信息
echo "==> VPS 信息汇总："
echo "队列调度: $(sysctl -n net.core.default_qdisc)"
echo "拥塞算法: $(sysctl -n net.ipv4.tcp_congestion_control)"