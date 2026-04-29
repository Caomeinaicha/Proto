#!/bin/bash

BIN_FILE="/usr/local/bin/snell-server"
CONFIG_FILE="/etc/snell.conf"
SERVICE_FILE="/etc/systemd/system/snell.service"

# 安装 Snell
install_snell() {
    echo "==> 开始安装 Snell ..."

    # 获取最新版本号
    VERSION=$(curl -s https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell | grep -oP 'snell-server-\Kv[\d.]+\w*' | head -n1)
    [ -z "$VERSION" ] && echo "获取版本号失败！" && exit 1
    echo "最新版本: $VERSION"
    # 下载并解压
    wget -O snell.zip https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip
    unzip -o snell.zip -d /usr/local/bin
    rm -f snell.zip

    # 写入配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
[snell-server]
listen = ::0:3313
psk = $(openssl rand -base64 16)
ipv6 = true
EOF
    fi

    # 写 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=${BIN_FILE} -c ${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable snell
    systemctl restart snell

    show_status
}

# 卸载 Snell
uninstall_snell() {
    echo "==> 卸载 Snell ..."
    systemctl stop snell
    systemctl disable snell
    rm -f "$SERVICE_FILE" "$BIN_FILE" /root/snell.log
    systemctl daemon-reload
    echo "Snell 已卸载完成"
}

# 显示状态 + IP:Port + PSK
show_status() {
    if [ -f "$CONFIG_FILE" ]; then
        IP=$(hostname -I | awk '{print $1}')
        PORT=$(grep -oP 'listen\s*=\s*.*:(\d+)$' "$CONFIG_FILE" | grep -oP '\d+$')
        PSK=$(grep -oP 'psk\s*=\s*\K.*' "$CONFIG_FILE")

        echo "======================================"
        echo "       Snell 状态信息"
        echo "--------------------------------------"
        SYSTEMD_PAGER="" systemctl status snell
        echo "IP:Port:  ${IP}: ${PORT}"
        echo "PSK:      ${PSK}"
        echo "======================================"
    else
        echo "Snell 未安装"
    fi
}

# 查看状态并下载日志
status_snell() {
    show_status
    journalctl -u snell -o cat > /root/snell.log
    echo "日志已保存到 /root/snell.log"
}

# 面板选择
echo "================ Snell 面板 ================"
echo "1) 安装 Snell"
echo "2) 卸载 Snell"
echo "3) 查看状态日志"
echo "============================================"
read -p "请输入选项 [1-3]: " choice

case "$choice" in
    1) install_snell ;;
    2) uninstall_snell ;;
    3) status_snell ;;
    *) echo "无效选项" ;;
esac