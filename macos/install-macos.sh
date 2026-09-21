#!/bin/bash
# DeepSeek Harness macOS MVP installer (M3)
set -u
umask 077

DEPLOYER_VERSION="0.1.0-M3"
DSH_PACKAGE="@deepseek-ai/dsh"
DSH_FALLBACK_VER="0.1.5-rc.2"
NODE_DIST_INDEX="https://nodejs.org/dist/index.json"
HEALTH_TIMEOUT_S=120

INSTALL_DIR_OVERRIDE=""
NO_LAUNCH=0
PORT=3080
VERBOSE_DIAG=0
ARCH=""
INSTALL_ROOT=""
WORKSPACE_DIR=""
LOG_DIR=""
CACHE_DIR=""
NODE_PATH=""
NODE_MODE=""
NODE_VERSION=""
NPM_VERSION=""
DSH_VERSION=""
WEB_VERIFIED=false
PORT_CONFIGURABLE=false
HARNESS_PID=""
INSTALL_LOG=""
SHORTCUT_PATH="$HOME/DeepSeekHarness/DeepSeek Harness.command"

usage() {
  printf '%s\n' "DeepSeek Harness macOS Installer"
  printf '%s\n' "./install-macos.command [--install-dir PATH] [--no-launch] [--port PORT]"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir) [ "$#" -ge 2 ] || { usage; exit 2; }; INSTALL_DIR_OVERRIDE="$2"; shift 2 ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --port) [ "$#" -ge 2 ] || { usage; exit 2; }; PORT="$2"; shift 2 ;;
    --verbose) VERBOSE_DIAG=1; shift ;;
    --non-interactive) shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

case "$PORT" in
  ''|*[!0-9]*) printf '端口必须是 1-65535 之间的数字。（DSH-E010）\n' >&2; exit 2 ;;
esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || { printf '端口必须是 1-65535 之间的数字。（DSH-E010）\n' >&2; exit 2; }

redact() {
  printf '%s\n' "$1" | sed -E \
    -e 's/([?&](token|TOKEN|api-key|api_key|authorization|cookie)=)[^&[:space:]]+/\1[REDACTED]/g' \
    -e 's/sk-[A-Za-z0-9]+/[REDACTED]/g'
}
log() {
  level="$1"; stage="$2"; shift 2
  message="$(redact "$*")"
  [ -n "$INSTALL_LOG" ] && printf '%s [%s] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$stage" "$message" >> "$INSTALL_LOG"
  [ "$VERBOSE_DIAG" -eq 1 ] && printf '%s [%s] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$stage" "$message"
}
result() {
  status="$1"; message="$2"; error_id="$3"
  if [ -n "$error_id" ]; then printf '  [%s] %s (%s)\n' "$status" "$message" "$error_id"; else printf '  [%s] %s\n' "$status" "$message"; fi
  log "$status" STAGE "$message $error_id"
}
fail() {
  error_id="$1"; human="$2"; tech="$3"
  result FAIL "$human" "$error_id"
  log ERROR FATAL "$tech $error_id"
  printf '\n安装未完成。请把下面这一行发给技术支持:\n  Error ID: %s   Log: %s\n' "$error_id" "$INSTALL_LOG" >&2
  exit 1
}
node_compatible() {
  version="$(printf '%s' "$1" | sed 's/^v//')"
  major="$(printf '%s' "$version" | cut -d. -f1)"
  minor="$(printf '%s' "$version" | cut -d. -f2)"
  case "$major:$minor" in *[!0-9:]*|:) return 1 ;; esac
  { [ "$major" -eq 22 ] && [ "$minor" -ge 19 ]; } || [ "$major" -ge 24 ]
}
arch_name() {
  case "$(uname -m)" in arm64) printf 'arm64\n' ;; x86_64) printf 'x64\n' ;; *) return 1 ;; esac
}
port_listening() { nc -z 127.0.0.1 "$1" >/dev/null 2>&1; }
extract_url() {
  printf '%s\n' "$1" | grep -Eo 'https?://(127\.0\.0\.1|localhost):[0-9]+[^[:space:]<>"]*' | tail -n 1 | sed -E 's/[),.;}]$//'
}
url_has_token() { case "$1" in *\?token=*|*\&token=*) return 0 ;; *) return 1 ;; esac; }
verify_url() {
  status="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 8 "$1" 2>/dev/null || true)"
  case "$status" in 2??|3??) return 0 ;; 401|403) [ "$2" = fallback ] ;; *) return 1 ;; esac
}
json_escape() {
  value="$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf '%s' "$value"
}
write_config() {
  cat > "$INSTALL_ROOT/config/deployer.json" <<EOF
{
  "os": "macos",
  "arch": "$(json_escape "$ARCH")",
  "installRoot": "$(json_escape "$INSTALL_ROOT")",
  "workspaceDir": "$(json_escape "$WORKSPACE_DIR")",
  "logDir": "$(json_escape "$LOG_DIR")",
  "cacheDir": "$(json_escape "$CACHE_DIR")",
  "nodePath": "$(json_escape "$NODE_PATH")",
  "nodeMode": "$(json_escape "$NODE_MODE")",
  "nodeVersion": "$(json_escape "$NODE_VERSION")",
  "dshVersion": "$(json_escape "$DSH_VERSION")",
  "port": $PORT,
  "webCommand": "web",
  "portConfigurable": $PORT_CONFIGURABLE,
  "pid": $(if [ -n "$HARNESS_PID" ]; then printf '%s' "$HARNESS_PID"; else printf 'null'; fi),
  "installedAt": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "deployerVersion": "$(json_escape "$DEPLOYER_VERSION")",
  "webVerified": $WEB_VERIFIED
}
EOF
}
select_node_version() {
  index=""
  if ! index="$(curl -fsSL --max-time 30 "$NODE_DIST_INDEX" 2>/dev/null)"; then
    selected_version="v24.21.0"; selected_fallback=true; return 0
  fi
  entry="$(printf '%s' "$index" | tr '{' '\n' | grep '"version":"v24\.' | grep '"lts":"' | head -n 1 || true)"
  selected_version="$(printf '%s' "$entry" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  if [ -z "$selected_version" ]; then
    entry="$(printf '%s' "$index" | tr '{' '\n' | grep '"version":"v22\.' | grep '"lts":"' | head -n 1 || true)"
    selected_version="$(printf '%s' "$entry" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  fi
  if [ -z "$selected_version" ]; then selected_version="v24.21.0"; selected_fallback=true; else selected_fallback=false; fi
}
install_private_node() {
  node_root="$INSTALL_ROOT/runtime/node"
  private_node="$node_root/bin/node"
  if [ -x "$private_node" ]; then
    private_version="$("$private_node" -v 2>/dev/null || true)"
    if node_compatible "$private_version"; then
      NODE_MODE=private; NODE_PATH="$private_node"; NODE_VERSION="$private_version"; result PASS "复用已安装私有 Node: $private_version" ""; return
    fi
  fi
  select_node_version
  package="node-$selected_version-darwin-$ARCH.tar.gz"
  base="https://nodejs.org/dist/$selected_version"
  archive="$CACHE_DIR/$package"
  checksums="$CACHE_DIR/SHASUMS256-$selected_version.txt"
  extract_dir="$CACHE_DIR/extract-$selected_version"
  printf '  下载 Node %s (%s) ...\n' "$selected_version" "$ARCH"
  curl -fsSL --max-time 180 "$base/$package" -o "$archive" || fail DSH-E001 'Node.js 下载失败。请更换网络后重试。' "url=$base/$package"
  curl -fsSL --max-time 60 "$base/SHASUMS256.txt" -o "$checksums" || fail DSH-E011 'Node.js 校验信息获取失败。' "url=$base/SHASUMS256.txt"
  expected="$(grep "  $package$" "$checksums" | awk '{print $1}' | head -n 1 || true)"
  actual="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [ -n "$expected" ] && [ "$expected" = "$actual" ] || fail DSH-E002 'Node.js SHA256 校验失败，已停止安装。' "expected=$expected actual=$actual"
  result PASS 'Node 安装包 SHA256 校验通过' ""
  rm -rf "$extract_dir"; mkdir -p "$extract_dir"
  tar -xzf "$archive" -C "$extract_dir" || fail DSH-E001 'Node.js 解压失败。' "archive=$archive"
  inner="$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [ -x "$inner/bin/node" ] || fail DSH-E001 'Node.js 解压后未找到 node。' "extract=$extract_dir"
  rm -rf "$node_root"; mkdir -p "$(dirname "$node_root")"; mv "$inner" "$node_root"
  NODE_MODE=private; NODE_PATH="$node_root/bin/node"; NODE_VERSION="$("$NODE_PATH" -v 2>/dev/null || true)"
  node_compatible "$NODE_VERSION" || fail DSH-E001 '私有 Node 安装后版本校验失败。' "version=$NODE_VERSION"
  result PASS "私有 Node 安装完成: $NODE_VERSION" ""
}
stage_s1() {
  printf 'Stage 1/7  System Check\n'
  [ "$(uname -s)" = Darwin ] || fail DSH-E009 '此脚本只能在 macOS 上运行。' "uname=$(uname -s)"
  ARCH="$(arch_name)" || fail DSH-E009 '不支持的 macOS CPU 架构，仅支持 Intel 和 Apple Silicon。' "uname=$(uname -m)"
  if [ -n "$INSTALL_DIR_OVERRIDE" ]; then INSTALL_ROOT="$INSTALL_DIR_OVERRIDE"; else INSTALL_ROOT="$HOME/Library/Application Support/DeepSeekHarness"; fi
  WORKSPACE_DIR="$HOME/DeepSeekHarness/workspace"; LOG_DIR="$HOME/Library/Logs/DeepSeekHarness"; CACHE_DIR="$INSTALL_ROOT/cache"
  mkdir -p "$INSTALL_ROOT/runtime/node" "$INSTALL_ROOT/launcher" "$INSTALL_ROOT/config" "$CACHE_DIR/npm" "$WORKSPACE_DIR" "$LOG_DIR" || fail DSH-E010 '无法创建安装目录，请检查权限。' "installRoot=$INSTALL_ROOT"
  INSTALL_LOG="$LOG_DIR/install-$(date '+%Y%m%d-%H%M%S').log"
  result PASS "macOS $(sw_vers -productVersion 2>/dev/null || printf unknown) / $ARCH" ""
  result PASS "安装目录: $INSTALL_ROOT" ""
  log INFO S1 "os=macos arch=$ARCH installRoot=$INSTALL_ROOT"
}
stage_s2() {
  printf 'Stage 2/7  Node.js\n'
  existing_node="$(command -v node 2>/dev/null || true)"
  existing_version=""; [ -n "$existing_node" ] && existing_version="$("$existing_node" -v 2>/dev/null || true)"
  if [ -n "$existing_version" ] && node_compatible "$existing_version"; then
    NODE_MODE=reuse; NODE_PATH="$existing_node"; NODE_VERSION="$existing_version"; result PASS "检测到兼容 Node.js: $NODE_VERSION（复用，不修改）" ""
  else
    [ -n "$existing_version" ] && result WARN "现有 Node.js $existing_version 不兼容，将安装私有 Runtime。" "" || result WARN '未检测到 Node.js，将安装私有 Runtime。' ""
    install_private_node
  fi
  log INFO S2 "nodeMode=$NODE_MODE nodePath=$NODE_PATH nodeVersion=$NODE_VERSION"
}
stage_s3() {
  printf 'Stage 3/7  npm\n'
  export NPM_CONFIG_CACHE="$CACHE_DIR/npm"
  node_dir="$(dirname "$NODE_PATH")"
  if [ "$NODE_MODE" = private ]; then npm_cmd="$node_dir/npm"; npx_cmd="$node_dir/npx"; else npm_cmd="$(command -v npm 2>/dev/null || true)"; npx_cmd="$(command -v npx 2>/dev/null || true)"; fi
  [ -x "$npm_cmd" ] || fail DSH-E003 'npm 不可用。请检查 Node.js 安装。' "npm=$npm_cmd"
  [ -x "$npx_cmd" ] || fail DSH-E003 'npx 不可用。请检查 Node.js 安装。' "npx=$npx_cmd"
  NPM_VERSION="$("$npm_cmd" -v 2>/dev/null || true)"; [ -n "$NPM_VERSION" ] || fail DSH-E003 'npm 版本检测失败。' 'npm -v failed'
  result PASS "npm: $NPM_VERSION" ""
  dsh_output="$("$npm_cmd" view "$DSH_PACKAGE" version 2>&1 || true)"
  DSH_VERSION="$(printf '%s\n' "$dsh_output" | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?' | head -n 1 || true)"
  [ -n "$DSH_VERSION" ] || fail DSH-E004 '无法连接 npm 软件源或获取 DeepSeek Harness 包信息。' 'npm view failed'
  result PASS 'npm 软件源可达' ""; result PASS "$DSH_PACKAGE 可达，版本: $DSH_VERSION" ""
  log INFO S3 "npmVersion=$NPM_VERSION dshVersion=$DSH_VERSION"
}
stage_s0() {
  printf 'Stage 4/7  Harness（S0 能力探测）\n'
  spec="$DSH_PACKAGE@$DSH_VERSION"; probe="$CACHE_DIR/dsh-help-$$.txt"
  "$npx_cmd" --yes "$spec" --help > "$probe" 2>&1 & probe_pid=$!
  waited=0; while kill -0 "$probe_pid" >/dev/null 2>&1 && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited + 1)); done
  if kill -0 "$probe_pid" >/dev/null 2>&1; then kill "$probe_pid" >/dev/null 2>&1 || true; fi
  wait "$probe_pid" >/dev/null 2>&1 || true
  if grep -qi web "$probe" 2>/dev/null; then WEB_VERIFIED=true; grep -qi -- --port "$probe" 2>/dev/null && PORT_CONFIGURABLE=true; result PASS 'dsh 命令面已探测确认（webVerified=true）' ""; else WEB_VERIFIED=false; PORT_CONFIGURABLE=false; result WARN 'dsh CLI 未返回可解析帮助，采用保守默认 web/3080，并标记 unverified。' ""; fi
  log INFO S0 "webVerified=$WEB_VERIFIED portConfigurable=$PORT_CONFIGURABLE"; rm -f "$probe"
}
stage_s5() {
  printf 'Stage 5/7  Launcher\n'
  source_launcher="$(cd "$(dirname "$0")" && pwd)/start-dsh.command"; launcher="$INSTALL_ROOT/launcher/start-dsh.command"
  [ -f "$source_launcher" ] || fail DSH-E010 '缺少 macOS 启动器模板。' "missing=$source_launcher"
  cp "$source_launcher" "$launcher" || fail DSH-E010 '启动器写入失败。' "launcher=$launcher"
  chmod +x "$launcher" || fail DSH-E010 '无法设置启动器可执行权限。' "launcher=$launcher"
  result PASS "启动器已生成: $launcher" ""
}
create_user_launcher() {
  launcher="$INSTALL_ROOT/launcher/start-dsh.command"
  shortcut="$SHORTCUT_PATH"
  mkdir -p "$(dirname "$shortcut")" || { result WARN '无法创建用户可见启动目录，已保留内部启动器。' 'DSH-E008'; return 0; }
  if [ -L "$shortcut" ]; then
    current_target="$(readlink "$shortcut" 2>/dev/null || true)"
    if [ "$current_target" = "$launcher" ]; then result PASS '用户可见启动方式已存在（reused）。' ""; return 0; fi
    result WARN '用户可见启动文件已存在且不是本产品创建，未覆盖。' 'DSH-E008'; return 0
  fi
  if [ -e "$shortcut" ]; then
    result WARN '用户可见启动文件已存在且不是本产品创建，未覆盖。' 'DSH-E008'; return 0
  fi
  ln -s "$launcher" "$shortcut" || { result WARN '无法创建用户可见启动方式，已保留内部启动器。' 'DSH-E008'; return 0; }
  result PASS "可双击启动方式已创建: $shortcut" ""
}
stage_s6() {
  printf 'Stage 6/7  Configuration, Workspace and Shortcut\n'
  if ! write_config; then fail DSH-E010 '配置文件写入失败。' "config=$INSTALL_ROOT/config/deployer.json"; fi
  result PASS '配置文件与默认 workspace 已准备。' ""
  log INFO S6 "config=$INSTALL_ROOT/config/deployer.json workspace=$WORKSPACE_DIR"
  create_user_launcher
}
stage_s7() {
  printf 'Stage 7/7  Verification\n'
  write_config
  if [ "$NO_LAUNCH" -eq 1 ]; then result WARN '（--no-launch）跳过实际启动，仅完成准备。' ""; return; fi
  launcher="$INSTALL_ROOT/launcher/start-dsh.command"; "$launcher" >/dev/null 2>&1 & launcher_pid=$!; HARNESS_PID="$launcher_pid"; write_config
  deadline=$(( $(date +%s) + HEALTH_TIMEOUT_S )); verified_log=""
  while [ "$(date +%s)" -lt "$deadline" ]; do
    verified_log="$(ls -t "$LOG_DIR"/runtime-*.log 2>/dev/null | head -n 1 || true)"
    if [ -n "$verified_log" ] && grep -q 'URL verification succeeded' "$verified_log" 2>/dev/null; then result PASS 'DeepSeek Harness is running and Web URL verified.' ""; log PASS S7 'launcher verification succeeded'; return; fi
    if [ -n "$verified_log" ] && grep -q 'URL verification reached fallback endpoint' "$verified_log" 2>/dev/null; then result WARN 'Harness 已在运行，使用明确标记的 fallback URL 完成验证。' ""; log WARN S7 'launcher verification reached fallback endpoint'; return; fi
    if [ -n "$verified_log" ] && grep -q 'URL verification failed' "$verified_log" 2>/dev/null; then fail DSH-E006 'Harness Web URL 验证失败。' "runtimeLog=$verified_log"; fi
    sleep 2
  done
  fail DSH-E006 "在 $HEALTH_TIMEOUT_S 秒内未确认 Harness 启动成功。" "runtimeLog=$verified_log"
}

printf '==================================================\n DeepSeek Harness One-Click Installer\n==================================================\n'
stage_s1; stage_s2; stage_s3; stage_s0; stage_s5; stage_s6; stage_s7
printf '\n==================================================\n Installation Complete\n==================================================\n'
printf 'Node.js:            %s (%s)\n' "$NODE_VERSION" "$NODE_MODE"
printf 'npm / registry:     PASS\nDeepSeek Harness:   %s\nLauncher:           PASS\nWeb UI:             %s\n' "$DSH_VERSION" "$(if [ "$NO_LAUNCH" -eq 1 ]; then printf WARN; else printf PASS; fi)"
printf '\n安全提示：请勿在终端输入 API Key。\n安装完成后，请在 Harness Web UI 的 Settings -> Models 中自行配置模型/API。\n启动方式：%s\n工作目录：%s\n日志：    %s\n==================================================\n' "$INSTALL_ROOT/launcher/start-dsh.command" "$WORKSPACE_DIR" "$INSTALL_LOG"
