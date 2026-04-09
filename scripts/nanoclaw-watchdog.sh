#!/bin/bash
# NanoClaw Health Check — only alerts on problems via Telegram
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$SCRIPT_DIR/.env" 2>/dev/null; set +a
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN not set in .env}"
CHAT_ID="${WATCHDOG_CHAT_ID:-8172023665}"
LOG="$SCRIPT_DIR/logs/nanoclaw.log"

send_alert() {
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" -d text="$1" > /dev/null 2>&1
}

ISSUES=""

# 1. NanoClaw process
if ! pgrep -f "nanoclaw/dist/index.js" > /dev/null 2>&1; then
  ISSUES="${ISSUES}• NanoClaw process is DOWN\n"
fi

# 2. Docker daemon
if ! /usr/local/bin/docker info > /dev/null 2>&1; then
  ISSUES="${ISSUES}• Docker daemon is not running\n"
fi

# 3. Container errors in recent log
ERRORS=$(tail -20 "$LOG" 2>/dev/null | grep -c -i "container.*error\|spawn error\|exited with error")
if [ "$ERRORS" -gt 0 ]; then
  LAST_ERR=$(tail -20 "$LOG" 2>/dev/null | grep -i "container.*error\|spawn error\|exited with error" | tail -1 | sed 's/\x1b\[[0-9;]*m//g')
  ISSUES="${ISSUES}• Container error: ${LAST_ERR}\n"
fi

# 4. Chatbot LLM server health
HEALTH=$(curl -s --max-time 5 http://localhost:8000/api/health 2>/dev/null)
if [ -z "$HEALTH" ]; then
  ISSUES="${ISSUES}• Chatbot API server is unreachable (port 8000)\n"
else
  STATUS=$(echo "$HEALTH" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  if [ "$STATUS" = "offline" ]; then
    ISSUES="${ISSUES}• Chatbot LLM is offline (MLX model server down)\n"
  elif [ "$STATUS" = "degraded" ]; then
    LATENCY=$(echo "$HEALTH" | grep -o '"latency_ms":[0-9.]*' | cut -d: -f2)
    ISSUES="${ISSUES}• Chatbot LLM is degraded (latency: ${LATENCY}ms)\n"
  fi
fi


# Only send if there are issues
if [ -n "$ISSUES" ]; then
  MSG=$(printf "⚠️ NanoClaw Health Check:\n%b" "$ISSUES")
  send_alert "$MSG"
fi
