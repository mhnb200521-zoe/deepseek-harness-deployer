#!/bin/bash
# DeepSeek Harness macOS 运行期启动器；由 install-macos.sh 复制到 installRoot/launcher。
set -u
umask 077

SOURCE_PATH="$0"
while [ -L "$SOURCE_PATH" ]; do
  TARGET_PATH="$(readlink "$SOURCE_PATH")"
  case "$TARGET_PATH" in
    /*) SOURCE_PATH="$TARGET_PATH" ;;
    *) SOURCE_PATH="$(dirname "$SOURCE_PATH")/$TARGET_PATH" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
INSTALL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$INSTALL_ROOT/config/deployer.json"
DSH_PACKAGE="@deepseek-ai/dsh"
if [ ! -f "$CONFIG" ]; then
  printf '[FAIL] 未找到 deployer.json，请先运行 install-macos.command。（DSH-E010）\n'
  exit 1
fi

json_string() {
  key="$1"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$CONFIG" | head -n 1
}
json_number() {
  key="$1"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$CONFIG" | head -n 1
}
NODE_PATH="$(json_string nodePath)"
NODE_MODE="$(json_string nodeMode)"
DSH_VERSION="$(json_string dshVersion)"
PORT="$(json_number port)"
WORKSPACE_DIR="$(json_string workspaceDir)"
LOG_DIR="$(json_string logDir)"
CACHE_DIR="$(json_string cacheDir)"
[ -n "$PORT" ] || PORT=3080
[ -n "$WORKSPACE_DIR" ] || WORKSPACE_DIR="$HOME/DeepSeekHarness/workspace"
[ -n "$LOG_DIR" ] || LOG_DIR="$HOME/Library/Logs/DeepSeekHarness"
[ -n "$CACHE_DIR" ] || CACHE_DIR="$INSTALL_ROOT/cache"
mkdir -p "$WORKSPACE_DIR" "$LOG_DIR" "$CACHE_DIR"
export NPM_CONFIG_CACHE="$CACHE_DIR/npm"
mkdir -p "$NPM_CONFIG_CACHE"

if [ "$NODE_MODE" = private ] && [ -x "$NODE_PATH" ]; then
  NPMX="$(dirname "$NODE_PATH")/npx"
else
  NPMX="$(command -v npx 2>/dev/null || true)"
fi
[ -x "$NPMX" ] || { printf '[FAIL] npx 不可用。（DSH-E003）\n'; exit 1; }

redact() {
  printf '%s\n' "$1" | sed -E \
    -e 's/([?&](token|TOKEN|api-key|api_key|authorization|cookie)=)[^&[:space:]]+/\1[REDACTED]/g' \
    -e 's/sk-[A-Za-z0-9]+/[REDACTED]/g'
}
RUN_LOG="$LOG_DIR/runtime-$(date '+%Y%m%d-%H%M%S').log"
run_log() {
  level="$1"; shift
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$(redact "$*")" >> "$RUN_LOG"
}
extract_url() {
  printf '%s\n' "$1" | grep -Eo 'https?://(127\.0\.0\.1|localhost):[0-9]+[^[:space:]<>"]*' | tail -n 1 | sed -E 's/[),.;}]$//'
}
url_has_token() { case "$1" in *\?token=*|*\&token=*) return 0 ;; *) return 1 ;; esac; }
verify_url() {
  status="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 8 "$1" 2>/dev/null || true)"
  case "$status" in 2??|3??) return 0 ;; 401|403) [ "$2" = fallback ] ;; *) return 1 ;; esac
}
open_url() {
  if command -v open >/dev/null 2>&1; then open "$1" >/dev/null 2>&1 || run_log WARN '无法调用 macOS open 打开浏览器。'; else run_log WARN '未找到 macOS open；请手动打开 Web UI。'; fi
}

run_log INFO "Starting DeepSeek Harness on configured fallback port $PORT"
if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then
  fallback_url="http://127.0.0.1:$PORT/"
  run_log WARN 'Harness 已在运行，本次没有新的启动输出；URL source=fallback。'
  if verify_url "$fallback_url" fallback; then
    run_log WARN 'URL verification reached fallback endpoint source=fallback tokenPresent=false'
    open_url "$fallback_url"; exit 0
  fi
  run_log FAIL 'fallback URL verification failed (DSH-E006)'; exit 1
fi

capture="$(mktemp "$CACHE_DIR/dsh-capture.XXXXXX")" || { run_log FAIL '无法创建临时输出捕获文件 (DSH-E010)'; exit 1; }
spec="$DSH_PACKAGE@$DSH_VERSION"
cd "$WORKSPACE_DIR" || { run_log FAIL '无法进入 workspace (DSH-E010)'; rm -f "$capture"; exit 1; }
"$NPMX" --yes "$spec" web --no-open > "$capture" 2>&1 &
DSH_PID=$!
deadline=$(( $(date +%s) + 120 ))
actual_url=""
url_source=fallback
while [ "$(date +%s)" -lt "$deadline" ]; do
  recent="$(tail -n 50 "$capture" 2>/dev/null || true)"
  while IFS= read -r line; do
    candidate="$(extract_url "$line")"
    [ -n "$candidate" ] && actual_url="$candidate" && url_source=detected
  done <<EOF
$recent
EOF
  if [ -n "$actual_url" ]; then
    actual_port="$(printf '%s' "$actual_url" | sed -E 's#https?://[^:]+:([0-9]+).*#\1#')"
    nc -z 127.0.0.1 "$actual_port" >/dev/null 2>&1 && break
  fi
  sleep 2
done

while IFS= read -r line; do [ -n "$line" ] && run_log DSH "$line"; done < "$capture"
rm -f "$capture"

if [ -z "$actual_url" ]; then
  if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then actual_url="http://127.0.0.1:$PORT/"; url_source=fallback; else run_log FAIL '启动超时或未捕获 Web URL (DSH-E006)'; exit 1; fi
fi
token_present=false
url_has_token "$actual_url" && token_present=true
run_log INFO "URL source=$url_source tokenPresent=$token_present port=$PORT"
if verify_url "$actual_url" "$url_source"; then
  if [ "$url_source" = detected ]; then run_log PASS "URL verification succeeded source=detected tokenPresent=$token_present status=2xx"; else run_log WARN 'URL verification reached fallback endpoint source=fallback tokenPresent=false'; fi
  open_url "$actual_url"
else
  run_log FAIL "URL verification failed source=$url_source tokenPresent=$token_present (DSH-E006)"; exit 1
fi

wait "$DSH_PID" 2>/dev/null || true
