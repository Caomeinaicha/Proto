#!/bin/bash
# 文件位置: /usr/local/bin/VpsNotify.sh   --- chmod +x /usr/local/bin/VpsNotify.sh（给文件权限）
# 配置位置：/etc/pam.d/sshd   --- session optional pam_exec.so type=open_session quiet /usr/local/bin/VpsNotify.sh（放在最下面）
# -------------------------
# Telegram 配置
# 请替换为您的实际 Bot 信息
CHAT_ID="ID"
BOT_TOKEN="TOKEN"
# -------------------------

# --- 1. 获取登录 IP ---
LOGIN_IP="$PAM_RHOST" 
[ -z "$LOGIN_IP" ] && LOGIN_IP="未知IP"

# --- 2. 查询 IP 地区信息 ---
IP_REGION="未知地区"
if [ "$LOGIN_IP" != "未知IP" ]; then
    IP_JSON=$(/usr/bin/curl -s --connect-timeout 5 "http://ip-api.com/json/$LOGIN_IP?lang=zh-CN")    
    if [ $? -eq 0 ] && [ -n "$IP_JSON" ]; then
        COUNTRY=$(echo "$IP_JSON" | jq -r '.country // "未知国家"')
        CITY=$(echo "$IP_JSON" | jq -r '.city // "未知城市"')
        IP_REGION="${COUNTRY} ${CITY}"
    fi
fi

# --- 3. 构建消息 ---
MESSAGE="📢 VPS登录
🌐 IP: $LOGIN_IP - $IP_REGION
⏰ 时间: $(TZ=UTC-8 date '+%Y-%m-%d %H:%M:%S')"

# --- 4. 发送 Telegram 消息 ---
/usr/bin/curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
      -d chat_id="$CHAT_ID" \
      -d text="$MESSAGE" >/dev/null 2>&1

exit 0