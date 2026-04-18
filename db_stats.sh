#!/bin/bash

# 1. 優先從環境變數讀取，若無則嘗試載入 .env 檔案
if [ -z "$MONGODB_URI" ]; then
  if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
  else
    echo "錯誤: 找不到 .env 檔案且未設定環境變數，請確認配置。"
    exit 1
  fi
fi

# 2. 設定 mongosh 路徑
export PATH=$PATH:/home/vxbaal0127/.hermes/node/bin
MONGOSH_PATH=$(which mongosh)

if [ -z "$MONGOSH_PATH" ]; then
  MONGOSH_PATH="/home/vxbaal0127/.hermes/node/bin/mongosh"
fi

# 3. 定義發送 Telegram 通知的函式
send_telegram() {
  local message=$1
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="${message}" \
    -d parse_mode="HTML" > /dev/null
}

# 4. 執行 MongoDB 狀態查詢
STATS_OUTPUT=$($MONGOSH_PATH "$MONGODB_URI" --quiet --eval "
const stats = db.stats();
const storageSizeMB = (stats.storageSize / 1024 / 1024).toFixed(2);
const dataSizeMB = (stats.dataSize / 1024 / 1024).toFixed(2);
const indexSizeMB = (stats.indexSize / 1024 / 1024).toFixed(2);

print('Database: ' + stats.db);
print('Storage_Size: ' + storageSizeMB);
print('Collections: ' + stats.collections);
")

# 顯示在終端機
echo "$STATS_OUTPUT"

# 5. 解析儲存空間數值
STORAGE_SIZE=$(echo "$STATS_OUTPUT" | grep "Storage_Size:" | cut -d' ' -f2)

# --- 配置門檻 ---
MAX_CAPACITY=512.0
THRESHOLD_MB=200.0
THRESHOLD_80=80.0
THRESHOLD_90=90.0

# 計算使用百分比
USAGE_PERCENT=$(awk "BEGIN {printf \"%.2f\", ($STORAGE_SIZE / $MAX_CAPACITY) * 100}")

# --- 6. 判斷警報邏輯 ---
SHOULD_NOTIFY=0
ALERT_LEVEL=""

if [ $(awk "BEGIN {print ($USAGE_PERCENT >= $THRESHOLD_90)}") -eq 1 ]; then
  ALERT_LEVEL="🚨 <b>【緊急】資料庫即將滿額 (90%+)</b>"
  SHOULD_NOTIFY=1
elif [ $(awk "BEGIN {print ($USAGE_PERCENT >= $THRESHOLD_80)}") -eq 1 ]; then
  ALERT_LEVEL="⚠️ <b>【警告】資料庫使用率過高 (80%+)</b>"
  SHOULD_NOTIFY=1
elif [ $(awk "BEGIN {print ($STORAGE_SIZE >= $THRESHOLD_MB)}") -eq 1 ]; then
  ALERT_LEVEL="📊 <b>【通知】資料庫儲存超過 200MB</b>"
  SHOULD_NOTIFY=1
fi

# 7. 發送通知
if [ $SHOULD_NOTIFY -eq 1 ]; then
  MESSAGE="${ALERT_LEVEL}%0A%0A"
  MESSAGE="${MESSAGE}📍 標的: <code>claw-db1</code>%0A"
  MESSAGE="${MESSAGE}📈 當前用量: <b>${STORAGE_SIZE} MB</b>%0A"
  MESSAGE="${MESSAGE}🏁 使用佔比: <b>${USAGE_PERCENT}%</b>%0A"
  MESSAGE="${MESSAGE}🕒 檢查時間: $(date '+%Y-%m-%d %H:%M:%S')"

  send_telegram "$MESSAGE"
  echo "--- 已達成通知門檻，Telegram 訊息已送出 ---"
else
  echo "--- 目前用量正常 (${STORAGE_SIZE}MB, ${USAGE_PERCENT}%)，未觸發通知 ---"
fi
