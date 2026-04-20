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

# 3. 解析 URI
# 若 URI 結尾已包含資料庫名稱 (如 /claw-db1)，則直接使用
# 若無，則補上 /claw-db1

if [[ "$MONGODB_URI" == *"mongodb.net/claw-db1"* ]]; then
  URI_WITH_DB="$MONGODB_URI"
else
  # 移除 query string 取得 base
  BASE=$(echo "$MONGODB_URI" | sed 's/?.*//')
  # 移除結尾的 /
  BASE=${BASE%/}
  # 取得 query string
  QUERY="?${MONGODB_URI##*\?}"
  [ "$QUERY" == "?$MONGODB_URI" ] && QUERY=""
  
  URI_WITH_DB="${BASE}/claw-db1${QUERY}"
fi

echo "Connecting to MongoDB..."

# 4. 查詢 MongoDB
# 自動探測 mongosh 路徑
if command -v mongosh &> /dev/null; then
  MONGOSH_CMD="mongosh"
elif [ -f "/mnt/c/Users/user/.local/mongosh-2.2.5-win32-x64/bin/mongosh.exe" ]; then
  MONGOSH_CMD="/mnt/c/Users/user/.local/mongosh-2.2.5-win32-x64/bin/mongosh.exe"
elif [ -f "C:/Users/user/.local/mongosh-2.2.5-win32-x64/bin/mongosh.exe" ]; then
  MONGOSH_CMD="C:/Users/user/.local/mongosh-2.2.5-win32-x64/bin/mongosh.exe"
else
  echo "錯誤: 找不到 mongosh。請確保已安裝或路徑正確。"
  exit 1
fi
# 4. 查詢 MongoDB
STATS=$($MONGOSH_CMD "$URI_WITH_DB" --quiet --eval "
  var s = db.stats();
  var conn = db.serverStatus().connections;
  var slow = db.currentOp({ \"secs_running\": { \"$gt\": 1 } }).inprog.length;
  print('SZ:' + s.storageSize);
  print('COL:' + s.collections);
  print('CONN:' + conn.current);
  print('SLOW:' + slow);
")

echo "$STATS"

# 5. 解析輸出
SZ=$(echo "$STATS" | grep '^SZ:' | cut -d: -f2)
COLS=$(echo "$STATS" | grep '^COL:' | cut -d: -f2)
CONN=$(echo "$STATS" | grep '^CONN:' | cut -d: -f2)
SLOW=$(echo "$STATS" | grep '^SLOW:' | cut -d: -f2)

[ -z "$SZ" ] && SZ=0
[ -z "$CONN" ] && CONN=0
[ -z "$SLOW" ] && SLOW=0

STORAGE_MB=$(echo "scale=2; $SZ / 1024 / 1024" | bc)
PERCENT=$(echo "scale=2; ($SZ / 1024 / 1024) / 512 * 100" | bc)

echo "Storage: ${STORAGE_MB}MB (${PERCENT}%), Connections: ${CONN}, Slow Ops: ${SLOW}"

# 6. 發送通知 (合併多重警報)
ALERT_MSG=""
if (( $(echo "$PERCENT > 90" | bc -l) )); then
  ALERT_MSG="🚨 MongoDB 空間緊繃: ${STORAGE_MB}MB (${PERCENT}%)"
elif (( $(echo "$PERCENT > 80" | bc -l) )); then
  ALERT_MSG="⚠️ MongoDB 空間警告: ${STORAGE_MB}MB (${PERCENT}%)"
fi

if [ "$CONN" -gt 400 ]; then
  ALERT_MSG="${ALERT_MSG}\n🚨 連線數過高: ${CONN}/500"
fi

if [ "$SLOW" -gt 0 ]; then
  ALERT_MSG="${ALERT_MSG}\n⚠️ 偵測到 ${SLOW} 筆慢查詢 (>1s)"
fi

if [ -n "$ALERT_MSG" ]; then
  send_telegram "$ALERT_MSG"
else
  echo "--- 狀態正常，未觸發通知 ---"
fi

