#!/bin/bash

BIN_FILE="/usr/local/bin/anytls-server"
CONFIG_FILE="/etc/anytls.json"
SERVICE_FILE="/etc/systemd/system/anytls.service"

# 安装 AnyTLS
install_anytls() {
    echo "==> 开始安装 AnyTLS ..."

    # 获取最新版本号并下载
    VERSION=$(curl -s https://api.github.com/repos/anytls/anytls-go/releases/latest \
        | jq -r '.tag_name')
    [ -z "$VERSION" ] && echo "获取版本号失败！" && exit 1
    echo "最新版本: $VERSION"
    DOWNLOAD_URL="https://github.com/anytls/anytls-go/releases/download/${VERSION}/anytls_${VERSION#v}_linux_amd64.zip"

    # 下载并安装
    curl -L -o /tmp/anytls.zip "$DOWNLOAD_URL" && unzip -p /tmp/anytls.zip anytls-server > "$BIN_FILE"
    chmod +x "$BIN_FILE"
    rm -f /tmp/anytls.zip

    # 写入配置文件
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
{
    "port": 6639,
    "password": "$(openssl rand -base64 16)"
}
EOF
    fi

    # 读取配置
    PORT=$(jq -r '.port' "$CONFIG_FILE")
    PASSWORD=$(jq -r '.password' "$CONFIG_FILE")

    # 写 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AnyTLS Proxy Service
After=network-online.target

[Service]
LimitNOFILE=51200
Type=simple
User=nobody
Group=nogroup
Restart=on-failure
RestartSec=5s
ExecStart=${BIN_FILE} -l 0.0.0.0:${PORT} -p "${PASSWORD}"

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable anytls
    systemctl restart anytls

    show_status
}

# 卸载 AnyTLS
uninstall_anytls() {
    echo "==> 卸载 AnyTLS ..."
    systemctl stop anytls
    systemctl disable anytls
    rm -f "$SERVICE_FILE" "$BIN_FILE" /root/anytls.log
    systemctl daemon-reload
    echo "AnyTLS 已卸载完成"
}

# 显示状态 + IP:Port + 密码
show_status() {
    if [ -f "$CONFIG_FILE" ]; then
        IP=$(hostname -I | awk '{print $1}')
        PORT=$(jq -r '.port' "$CONFIG_FILE")
        PASSWORD=$(jq -r '.password' "$CONFIG_FILE")

        echo "======================================"
        echo "            AnyTLS 状态信息"
        echo "--------------------------------------"
        SYSTEMD_PAGER="" systemctl status anytls
        echo "IP:Port:  ${IP}:${PORT}"
        echo "Password: ${PASSWORD}"
        echo "======================================"
    else
        echo "AnyTLS 未安装"
    fi
}

# 查看状态并下载日志
status_anytls() {
    show_status
    journalctl -u anytls -o cat > /root/anytls.log
    echo "日志已保存到 /root/anytls.log"
}

# 面板选择
echo "================ AnyTLS 面板 ================="
echo "1) 安装 AnyTLS"
echo "2) 卸载 AnyTLS"
echo "3) 查看状态日志"
echo "============================================"
read -p "请输入选项 [1-3]: " choice

case "$choice" in
    1) install_anytls ;;
    2) uninstall_anytls ;;
    3) status_anytls ;;
    *) echo "无效选项" ;;
esac