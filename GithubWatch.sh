#!/bin/bash
#chmod +x /root/github_watch.sh && /bin/bash /root/github_watch.sh && (crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash /root/github_watch.sh") | crontab -
#查看当前所有任务---crontab -l
#直接清空所有 cron---crontab -r

# ===== 配置 =====

URL="https://github.com/#########/#########/commits/master.atom"

CHAT_ID="#########"
BOT_TOKEN="#########"

STATE_FILE="/root/github.txt"

# ===== 确保文件存在 =====
touch "$STATE_FILE"

# ===== 获取 RSS =====
DATA=$(/usr/bin/curl -s "$URL")

# ===== 关键：只取 entry 里的 commit id（稳定）=====
NEW_ID=$(echo "$DATA" | grep -o '<id>tag:github.com,2008:Grit::Commit/[^<]*' | head -1)

OLD_ID=$(cat "$STATE_FILE" 2>/dev/null)

# ===== 调试保护 =====
if [ -z "$NEW_ID" ]; then
    exit 0
fi

# ===== 判断更新 =====
if [ "$NEW_ID" != "$OLD_ID" ]; then

    echo "$NEW_ID" > "$STATE_FILE"

    # commit 标题
    TITLE=$(echo "$DATA" | grep -oP '(?<=<title>)[^<]+' | head -1)

    # commit 链接
    LINK=$(echo "$DATA" | grep -oP 'https://github.com/[^<]*/commit/[^<]+' | head -1)

    # ===== 消息 =====
    MESSAGE="GitHub 更新
Repo: #########
$TITLE
$LINK
$(date '+%Y-%m-%d %H:%M:%S')"

    # ===== 推送 =====
    /usr/bin/curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="$MESSAGE" >/dev/null 2>&1
fi