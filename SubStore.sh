#!/bin/bash

NodePath="/opt/node"
SubStorePath="/opt/sub-store"
SubStoreConfig="/opt/sub-store_apikey"

set -e

install_substore() {
    echo "==> 开始安装 Sub-Store ..."

    # 安装 LTS Node.js
    mkdir -p "$NodePath"
    NodeVersion=$(curl -s https://nodejs.org/dist/index.json | jq -r '[.[] | select(.lts)][0].version')
    [ -z "$NodeVersion" ] && echo "获取 Node.js 版本失败！" && exit 1
    echo "最新 LTS 版本: $NodeVersion"
    curl -L "https://nodejs.org/dist/${NodeVersion}/node-${NodeVersion}-linux-x64.tar.xz" \
        | tar -xJ -C "$NodePath" --strip-components=1

    # 下载并解压
    mkdir -p "$SubStorePath" && cd "$SubStorePath"
    curl -L https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js -o sub-store.bundle.js
    curl -L https://github.com/sub-store-org/Sub-Store-Front-End/releases/latest/download/dist.zip -o dist.zip
    unzip -o dist.zip && mv dist frontend
    rm -f dist.zip

    # 生成 API Key 并写入配置文件
    ApiKey=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 20)
    echo "$ApiKey" > "$SubStoreConfig"

    # 写 systemd 服务
    cat > /etc/systemd/system/sub-store.service <<EOF
[Unit]
Description=Sub-Store Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
LimitNOFILE=32767
Type=simple
Environment="SUB_STORE_FRONTEND_BACKEND_PATH=/${ApiKey}"
Environment="SUB_STORE_FRONTEND_PATH=${SubStorePath}/frontend"
Environment="SUB_STORE_FRONTEND_HOST=0.0.0.0"
Environment="SUB_STORE_FRONTEND_PORT=33333"
Environment="SUB_STORE_DATA_BASE_PATH=${SubStorePath}"
Environment="SUB_STORE_BACKEND_API_HOST=127.0.0.1"
Environment="SUB_STORE_BACKEND_API_PORT=33133"
ExecStart=${NodePath}/bin/node ${SubStorePath}/sub-store.bundle.js
User=root
Group=root
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    # 启动服务
    systemctl daemon-reload
    systemctl enable sub-store.service
    systemctl restart sub-store.service

    show_status
}

uninstall_substore() {
    echo "==> 卸载 Sub-Store ..."
    systemctl stop sub-store.service
    systemctl disable sub-store.service
    rm -f /etc/systemd/system/sub-store.service
    rm -rf "$SubStorePath" "$SubStoreConfig" "$NodePath" /var/log/substore.log
    systemctl daemon-reload
    echo "Sub-Store 已彻底卸载完成。"
}

show_status() {
    IP=$(hostname -I | awk '{print $1}')
    ApiKey="[未安装]"
    [ -f "$SubStoreConfig" ] && ApiKey=$(cat "$SubStoreConfig")
    echo "======================================"
    echo "       Sub-Store 状态信息"
    echo "--------------------------------------"
    SYSTEMD_PAGER="" systemctl status sub-store.service
    echo "IP:       ${IP}:33333"
    echo "API Key:  http://${IP}:33333/?api=http://${IP}:33333/${ApiKey}"
    echo "======================================"
}

status_substore() {
    show_status
    journalctl -u sub-store.service > /var/log/substore.log
    echo "日志已保存到 /var/log/substore.log"
}

echo "================ Sub-Store 面板 ================"
echo "1) 安装 Sub-Store"
echo "2) 卸载 Sub-Store"
echo "3) 查看状态 + 日志"
echo "==============================================="
read -p "请输入选项 [1-3]: " choice

case "$choice" in
    1) install_substore ;;
    2) uninstall_substore ;;
    3) status_substore ;;
    *) echo "无效选项" ;;
esac