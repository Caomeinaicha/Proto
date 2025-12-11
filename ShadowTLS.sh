#!/bin/bash

BIN_FILE="/usr/local/bin/shadow-tls"
CONFIG_FILE="/etc/shadow-tls.conf"
SERVICE_FILE="/etc/systemd/system/shadow-tls.service"

# 安装 Shadow-TLS
install_shadowtls() {
    echo "==> 开始安装 Shadow-TLS ..."

    # 获取最新版本
    VERSION=$(curl -s https://api.github.com/repos/ihciah/shadow-tls/releases \
        | grep '"tag_name":' | grep -v 'draft' | grep -v 'prerelease' | head -n1 | awk -F '"' '{print $4}')
    [ -z "$VERSION" ] && echo "获取版本号失败！" && exit 1
    echo "最新版本: $VERSION"
    DOWNLOAD_URL="https://github.com/ihciah/shadow-tls/releases/download/${VERSION}/shadow-tls-x86_64-unknown-linux-musl"

    # 下载 Shadow-TLS
    curl -L "$DOWNLOAD_URL" -o "$BIN_FILE"
    chmod +x "$BIN_FILE"

    # 随机密码
    local password=$(openssl rand -base64 16)

    # 保存配置
    cat > "$CONFIG_FILE" <<EOF
Password: ${password}
Listen: 0.0.0.0:6136
TLS: gateway.icloud.com
EOF

    # 写 systemd 服务
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Shadow-TLS Server Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_FILE} --v3 server --listen 0.0.0.0:6136 --server 127.0.0.1:2323 --tls gateway.icloud.com --password ${password}
Restart=on-failure
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable shadow-tls
    systemctl restart shadow-tls

    show_status
}

# 卸载 Shadow-TLS
uninstall_shadowtls() {
    echo "==> 卸载 Shadow-TLS ..."
    systemctl stop shadow-tls
    systemctl disable shadow-tls
    rm -f "$SERVICE_FILE" "$BIN_FILE" "$CONFIG_FILE" /var/log/shadow-tls.log
    systemctl daemon-reload
    echo "Shadow-TLS 已彻底卸载完成。"
}

# 显示状态
show_status() {
    if [ -f "$CONFIG_FILE" ]; then
        PASSWORD=$(grep 'Password' "$CONFIG_FILE" | awk '{print $2}')
        PORT=$(grep 'Listen' "$CONFIG_FILE" | awk -F: '{print $NF}')
        TLS=$(grep 'TLS' "$CONFIG_FILE" | awk '{print $2}')
    else
        PASSWORD="[未安装]"
        PORT="[未安装]"
        TLS="[未安装]"
    fi

    echo "======================================"
    echo "          Shadow-TLS 状态信息"
    echo "--------------------------------------"
    SYSTEMD_PAGER="" systemctl status shadow-tls
    echo "Port:     ${PORT}"
    echo "Password: ${PASSWORD}"
    echo "TLS:      ${TLS}"
    echo "======================================"
}

# 查看状态并导出日志
status_shadowtls() {
    show_status
    journalctl -u shadow-tls > /var/log/shadow-tls.log
    echo "日志已保存到 /var/log/shadow-tls.log"
}

# 面板
echo "================ Shadow-TLS 面板 ================"
echo "1) 安装 Shadow-TLS"
echo "2) 卸载 Shadow-TLS"
echo "3) 查看状态日志"
echo "================================================"
read -p "请输入选项 [1-3]: " choice

case "$choice" in
    1) install_shadowtls ;;
    2) uninstall_shadowtls ;;
    3) status_shadowtls ;;
    *) echo "无效选项" ;;
esac