#!/bin/bash

BBR_CONF="/etc/sysctl.d/99-bbr.conf"

# 更新系统并安装依赖
apt update && apt upgrade -y && apt install -y curl openssl jq unzip xz-utils

# 设置时区为台北
timedatectl set-timezone Asia/Taipei

# 开启 BBR 并设置网络缓冲区
tee "$BBR_CONF" >/dev/null <<EOF
net.core.rmem_max=26214400
net.core.rmem_default=26214400
net.core.wmem_max=26214400
net.core.wmem_default=26214400
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null

# 显示信息
echo "==> VPS 信息汇总："
echo "队列调度: $(sysctl -n net.core.default_qdisc)"
echo "拥塞算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
echo "SSH登录端口: $(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')"