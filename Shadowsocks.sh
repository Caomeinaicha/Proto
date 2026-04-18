#!/bin/bash

BIN_FILE="/usr/local/bin/shadowsocks-server"
CONFIG_FILE="/etc/shadowsocks.json"
SERVICE_FILE="/etc/systemd/system/shadowsocks.service"

# 安装 Shadowsocks
install_shadowsocks() {
    echo "==> 开始安装 Shadowsocks ..."

    # 获取最新版本号并下载
    VERSION=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest \
        | jq -r '.tag_name')
    [ -z "$VERSION" ] && echo "获取版本号失败！" && exit 1
    echo "最新版本: $VERSION"

    DOWNLOAD_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${VERSION}/shadowsocks-${VERSION}.x86_64-unknown-linux-gnu.tar.xz"

    # 下载并安装
    curl -L "$DOWNLOAD_URL" | tar -xJ -O ssserver > "$BIN_FILE"
    chmod +x "$BIN_FILE"

    # 写入配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
{
    "server": "::",
    "server_port": 2323,
    "password": "$(openssl rand -base64 16)",
    "method": "2022-blake3-aes-128-gcm",
    "fast_open": false,
    "mode": "tcp_and_udp"
}
EOF
    fi

    # 写 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadowsocks Proxy Service
After=network.target

[Service]
LimitNOFILE=51200
Type=simple
User=nobody
Group=nogroup
Restart=on-failure
RestartSec=5s
ExecStart=${BIN_FILE} -c ${CONFIG_FILE}

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable shadowsocks
    systemctl restart shadowsocks

    show_status
}

# 卸载 Shadowsocks
uninstall_shadowsocks() {
    echo "==> 卸载 Shadowsocks ..."
    systemctl stop shadowsocks
    systemctl disable shadowsocks
    rm -f "$SERVICE_FILE" "$BIN_FILE" /root/shadowsocks.log
    systemctl daemon-reload
    echo "Shadowsocks 已卸载完成"
}

# 显示状态 + IP:Port + 密码
show_status() {
    if [ -f "$CONFIG_FILE" ]; then
        IP=$(hostname -I | awk '{print $1}')
        PORT=$(jq -r '.server_port' "$CONFIG_FILE")
        PASSWORD=$(jq -r '.password' "$CONFIG_FILE")

        echo "======================================"
        echo "       Shadowsocks 状态信息"
        echo "--------------------------------------"
        SYSTEMD_PAGER="" systemctl status shadowsocks
        echo "IP:Port:  ${IP}: ${PORT}"
        echo "Password: ${PASSWORD}"
        echo "======================================"
    else
        echo "Shadowsocks 未安装"
    fi
}

# 查看状态并下载日志
status_shadowsocks() {
    show_status
    journalctl -u shadowsocks -o cat > /root/shadowsocks.log
    echo "日志已保存到 /root/shadowsocks.log"
}

# 面板选择
echo "================ Shadowsocks 面板 ================"
echo "1) 安装 Shadowsocks"
echo "2) 卸载 Shadowsocks"
echo "3) 查看状态日志"
echo "================================================="
read -p "请输入选项 [1-3]: " choice

case "$choice" in
    1) install_shadowsocks ;;
    2) uninstall_shadowsocks ;;
    3) status_shadowsocks ;;
    *) echo "无效选项" ;;
esac