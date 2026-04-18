#!/bin/bash

# 1. 讀取環境變數或 .env
if [ -z "$MONGODB_URI" ]; then
  if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
  else
    echo "錯誤: 找不到 .env 檔案且未設定環境變數"
    exit 1
  fi
fi

# 2. 發送 Telegram 通知
send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="$1" \
    -d parse_mode="HTML" > /dev/null
}

# 3. 解析 URI 並指定資料庫
# MONGODB_URI = mongodb+srv://user:pass@host/?appName=xxx
# 需要改成: mongodb+srv://user:pass@host/claw-db1?appName=xxx
BASE_URI="${MONGODB_URI%%\?*}"  # 移除 query string
QUERY="${MONGODB_URI##*\?}"     # 取得 query string
URI_WITH_DB="${BASE_URI}/claw-db1?${QUERY}"

echo "Connecting to: claw-db1"

# 4. 查詢 MongoDB
STATS=$(mongosh "$URI_WITH_DB" --quiet --eval "
var s = db.stats();
print('SZ:' + s.storageSize);
print('COL:' + s.collections);
print('DB:' + s.db);
")

echo "$STATS"

# 5. 解析輸出
SZ=$(echo "$STATS" | grep '^SZ:' | cut -d: -f2)
COLS=$(echo "$STATS" | grep '^COL:' | cut -d: -f2)

# 預設值
[ -z "$SZ" ] && SZ=0
[ -z "$COLS" ] && COLS=0

STORAGE_MB=$(echo "scale=2; $SZ / 1024 / 1024" | bc)
PERCENT=$(echo "scale=2; ($SZ / 1024 / 1024) / 512 * 100" | bc)

echo "Storage: ${STORAGE_MB}MB, Percent: ${PERCENT}%"

# 6. 發送通知
if (( $(echo "$PERCENT > 90" | bc -l) )); then
  send_telegram "🚨 MongoDB 緊急: ${STORAGE_MB}MB (${PERCENT}%)"
elif (( $(echo "$PERCENT > 80" | bc -l) )); then
  send_telegram "⚠️ MongoDB 警告: ${STORAGE_MB}MB (${PERCENT}%)"
else
  echo "--- 用量正常: ${STORAGE_MB}MB (${PERCENT}%)，未觸發通知 ---"
fi
