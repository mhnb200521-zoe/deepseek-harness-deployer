#!/bin/bash
# DeepSeek Harness — macOS Repair / Diagnostic (M4)
set -u
umask 077

DSH_PACKAGE="@deepseek-ai/dsh"
INSTALL_ROOT=""
REPORT_PATH=""
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
REPORT_LINES=""

usage() {
  printf '%s\n' "DeepSeek Harness macOS Diagnostic"
  printf '%s\n' "./repair-macos.sh [--install-dir PATH] [--report PATH]"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir) [ "$#" -ge 2 ] || { usage; exit 2; }; INSTALL_ROOT="$2"; shift 2 ;;
    --report) [ "$#" -ge 2 ] || { usage; exit 2; }; REPORT_PATH="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

redact() {
  printf '%s\n' "$1" | sed -E \
    -e 's/([?&](token|TOKEN|api-key|api_key|authorization|cookie)=)[^&[:space:]]+/\1[REDACTED]/g' \
    -e 's/sk-[A-Za-z0-9]+/[REDACTED]/g'
}
json_string() {
  key="$1"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" | head -n 1
}
json_number() {
  key="$1"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$2" | head -n 1
}
node_compatible() {
  version="$(printf '%s' "$1" | sed 's/^v//')"
  major="$(printf '%s' "$version" | cut -d. -f1)"
  minor="$(printf '%s' "$version" | cut -d. -f2)"
  case "$major:$minor" in *[!0-9:]*|:) return 1 ;; esac
  { [ "$major" -eq 22 ] && [ "$minor" -ge 19 ]; } || [ "$major" -ge 24 ]
}
add_check() {
  status="$1"; item="$2"; detail="$(redact "${3:-}")"; error_id="${4:-}"
  case "$status" in PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;; WARN) WARN_COUNT=$((WARN_COUNT + 1)) ;; FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;; esac
  if [ -n "$error_id" ]; then
    line="[$status] $item - $detail ($error_id)"
  else
    line="[$status] $item - $detail"
  fi
  printf '  %s\n' "$line"
  REPORT_LINES="${REPORT_LINES}${line}\n"
}

if [ -z "$INSTALL_ROOT" ]; then
  for candidate in "$HOME/Library/Application Support/DeepSeekHarness" "$HOME/DeepSeekHarness/.dsh-install"; do
    if [ -f "$candidate/config/deployer.json" ]; then INSTALL_ROOT="$candidate"; break; fi
  done
fi
[ -n "$INSTALL_ROOT" ] || INSTALL_ROOT="$HOME/Library/Application Support/DeepSeekHarness"
CONFIG="$INSTALL_ROOT/config/deployer.json"
LOG_DIR="$HOME/Library/Logs/DeepSeekHarness"
WORKSPACE_DIR="$HOME/DeepSeekHarness/workspace"
NODE_PATH=""
NODE_MODE=""
PORT=3080

if [ -f "$CONFIG" ]; then
  LOG_DIR="$(json_string logDir "$CONFIG")"; [ -n "$LOG_DIR" ] || LOG_DIR="$HOME/Library/Logs/DeepSeekHarness"
  WORKSPACE_DIR="$(json_string workspaceDir "$CONFIG")"; [ -n "$WORKSPACE_DIR" ] || WORKSPACE_DIR="$HOME/DeepSeekHarness/workspace"
  NODE_PATH="$(json_string nodePath "$CONFIG")"
  NODE_MODE="$(json_string nodeMode "$CONFIG")"
  configured_port="$(json_number port "$CONFIG")"; [ -n "$configured_port" ] && PORT="$configured_port"
  add_check PASS 'Install config' "$INSTALL_ROOT"
else
  add_check WARN 'Install config' '未找到 deployer.json，将按默认路径诊断。' 'DSH-E010'
fi

mkdir -p "$LOG_DIR" 2>/dev/null || true
if [ -z "$REPORT_PATH" ]; then REPORT_PATH="$LOG_DIR/diagnostic-$(date '+%Y%m%d-%H%M%S').txt"; fi

if [ -n "$NODE_PATH" ] && [ -x "$NODE_PATH" ]; then
  node_cmd="$NODE_PATH"
else
  node_cmd="$(command -v node 2>/dev/null || true)"
fi
node_version=""; [ -n "$node_cmd" ] && node_version="$("$node_cmd" -v 2>/dev/null || true)"
if [ -n "$node_version" ] && node_compatible "$node_version"; then
  add_check PASS 'Node.js' "$node_version ($NODE_MODE)"
elif [ -n "$node_version" ]; then
  add_check WARN 'Node.js' "$node_version 不满足兼容基线" 'DSH-E003'
else
  add_check FAIL 'Node.js' 'node 不可用。' 'DSH-E003'
fi

node_dir=""; [ -n "$node_cmd" ] && node_dir="$(dirname "$node_cmd")"
if [ -n "$node_dir" ] && [ -x "$node_dir/npm" ]; then npm_cmd="$node_dir/npm"; else npm_cmd="$(command -v npm 2>/dev/null || true)"; fi
if [ -n "$node_dir" ] && [ -x "$node_dir/npx" ]; then npx_cmd="$node_dir/npx"; else npx_cmd="$(command -v npx 2>/dev/null || true)"; fi
npm_version=""; [ -n "$npm_cmd" ] && npm_version="$("$npm_cmd" -v 2>/dev/null || true)"
[ -n "$npm_version" ] && add_check PASS 'npm' "$npm_version" || add_check FAIL 'npm' 'npm 不可用。' 'DSH-E003'
[ -n "$npx_cmd" ] && [ -x "$npx_cmd" ] && add_check PASS 'npx' "$npx_cmd" || add_check FAIL 'npx' 'npx 不可用。' 'DSH-E003'

if [ -n "$npm_cmd" ] && [ -x "$npm_cmd" ]; then
  dsh_output="$("$npm_cmd" view "$DSH_PACKAGE" version 2>&1 || true)"
  dsh_version="$(printf '%s\n' "$dsh_output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?' | head -n 1 || true)"
  if [ -n "$dsh_version" ]; then
    add_check PASS 'npm registry / @deepseek-ai/dsh' "reachable, version=$dsh_version"
  else
    add_check FAIL 'npm registry / @deepseek-ai/dsh' '软件源或包不可达。' 'DSH-E004'
  fi
else
  add_check WARN 'npm registry / @deepseek-ai/dsh' '因 npm 不可用，跳过网络检查。' 'DSH-E004'
fi

launcher="$INSTALL_ROOT/launcher/start-dsh.command"
[ -x "$launcher" ] && add_check PASS 'Launcher' "$launcher" || add_check WARN 'Launcher' '启动器缺失或不可执行，重跑安装器可重建。' 'DSH-E010'
shortcut="$HOME/DeepSeekHarness/DeepSeek Harness.command"
if [ -L "$shortcut" ] && [ "$(readlink "$shortcut" 2>/dev/null || true)" = "$launcher" ]; then
  add_check PASS 'Double-click launcher' "$shortcut"
elif [ -e "$shortcut" ] || [ -L "$shortcut" ]; then
  add_check WARN 'Double-click launcher' '同名文件不是本产品创建，未判断为可用。' 'DSH-E008'
else
  add_check WARN 'Double-click launcher' '用户可见启动方式缺失，重跑安装器可重建。' 'DSH-E008'
fi

if command -v nc >/dev/null 2>&1; then
  if nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1; then add_check PASS "Port $PORT" '本机端口正在监听。'; else add_check WARN "Port $PORT" 'Harness 当前未监听。'; fi
else
  add_check WARN "Port $PORT" '未找到 nc，跳过端口检查。'
fi

latest_runtime="$(ls -t "$LOG_DIR"/runtime-*.log 2>/dev/null | head -n 1 || true)"
if [ -n "$latest_runtime" ] && grep -q 'URL verification succeeded' "$latest_runtime" 2>/dev/null; then
  token_state='false'; grep -q 'tokenPresent=true' "$latest_runtime" 2>/dev/null && token_state='true'
  add_check PASS 'Latest Web verification' "source=detected tokenPresent=$token_state"
elif [ -n "$latest_runtime" ] && grep -q 'URL verification reached fallback endpoint' "$latest_runtime" 2>/dev/null; then
  add_check WARN 'Latest Web verification' 'source=fallback tokenPresent=false'
elif [ -n "$latest_runtime" ] && grep -q 'URL verification failed' "$latest_runtime" 2>/dev/null; then
  add_check FAIL 'Latest Web verification' 'runtime log reports URL verification failure。' 'DSH-E006'
else
  add_check WARN 'Latest Web verification' '没有可确认的成功运行日志。'
fi

{
  printf '%s\n' 'DeepSeek Harness Diagnostic Report'
  printf 'Generated: %s\nInstallRoot: %s\nWorkspace: %s\n\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$INSTALL_ROOT" "$WORKSPACE_DIR"
  printf '%b' "$REPORT_LINES"
  printf '\nSummary: PASS=%s WARN=%s FAIL=%s\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
} > "$REPORT_PATH" 2>/dev/null || { printf '  [WARN] Diagnostic Report - 无法写入 %s (DSH-E010)\n' "$REPORT_PATH"; WARN_COUNT=$((WARN_COUNT + 1)); }
printf '\nSummary: PASS=%s WARN=%s FAIL=%s\n' "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"
printf 'Diagnostic Report: %s\n' "$REPORT_PATH"
[ "$FAIL_COUNT" -eq 0 ]
