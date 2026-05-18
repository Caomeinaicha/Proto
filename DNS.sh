#!/bin/bash
set -e

echo "=== 配置 systemd-resolved DNS ==="

sudo mkdir -p /etc/systemd/resolved.conf.d

sudo tee /etc/systemd/resolved.conf.d/custom.conf > /dev/null << 'CONFIG'
[Resolve]
DNS=8.8.8.8 1.1.1.1 2001:4860:4860::8888 2606:4700:4700::1111
CONFIG

echo "-> DNS 配置已写入完成"

echo "=== 重启 systemd-resolved DNS 服务 ==="

sudo systemctl restart systemd-resolved

echo "-> systemd-resolved 已重启完成"
echo "=== 当前 DNS 状态如下 ==="

resolvectl status

echo
echo "执行完成"
echo "建议：重启系统以确保配置完全生效"