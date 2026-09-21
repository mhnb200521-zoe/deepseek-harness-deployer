#!/bin/bash
# DeepSeek Harness — macOS Uninstall (M4)
set -u
umask 077

INSTALL_ROOT=""
PURGE=0
YES=0
usage() {
  printf '%s\n' "DeepSeek Harness macOS Uninstall"
  printf '%s\n' "./uninstall-macos.sh [--install-dir PATH] [--purge] [--yes]"
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --install-dir) [ "$#" -ge 2 ] || { usage; exit 2; }; INSTALL_ROOT="$2"; shift 2 ;;
    --purge) PURGE=1; shift ;;
    --yes) YES=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$INSTALL_ROOT" ]; then
  for candidate in "$HOME/Library/Application Support/DeepSeekHarness" "$HOME/DeepSeekHarness/.dsh-install"; do
    if [ -f "$candidate/config/deployer.json" ]; then INSTALL_ROOT="$candidate"; break; fi
  done
fi
if [ -z "$INSTALL_ROOT" ]; then
  printf '未找到 DeepSeek Harness 安装目录；未删除任何内容。\n'
  exit 0
fi
if [ ! -d "$INSTALL_ROOT" ]; then
  printf '安装目录不存在；未删除任何内容: %s\n' "$INSTALL_ROOT"
  exit 0
fi

json_string() {
  key="$1"
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$2" | head -n 1
}
CONFIG="$INSTALL_ROOT/config/deployer.json"
WORKSPACE_DIR="$HOME/DeepSeekHarness/workspace"
LOG_DIR="$HOME/Library/Logs/DeepSeekHarness"
NODE_MODE=""
NODE_PATH=""
if [ ! -f "$CONFIG" ]; then
  printf '未找到本产品的 deployer.json，无法确认目录归属；为安全起见拒绝删除。（DSH-E010）\n'
  exit 1
fi
if [ -f "$CONFIG" ]; then
  configured_workspace="$(json_string workspaceDir "$CONFIG")"; [ -n "$configured_workspace" ] && WORKSPACE_DIR="$configured_workspace"
  configured_log_dir="$(json_string logDir "$CONFIG")"; [ -n "$configured_log_dir" ] && LOG_DIR="$configured_log_dir"
  NODE_MODE="$(json_string nodeMode "$CONFIG")"
  NODE_PATH="$(json_string nodePath "$CONFIG")"
fi

printf '==================================================\n DeepSeek Harness — Uninstall\n==================================================\n'
printf '安装目录: %s\n' "$INSTALL_ROOT"
if [ "$NODE_MODE" = reuse ]; then printf '系统 Node (%s) 不属于本产品，不会删除。\n' "$NODE_PATH"; else printf '仅删除本安装目录内的私有 Runtime。\n'; fi

if [ "$PURGE" -eq 1 ] && [ "$YES" -eq 0 ]; then
  printf '即将删除 workspace 与日志，这是不可逆的。确认请输入 yes: '
  read -r answer || answer=''
  case "$answer" in yes|YES|Yes) ;; *) printf '已取消，未删除任何内容。\n'; exit 0 ;; esac
fi

remove_failures=0
remove_path() {
  path="$1"; label="$2"
  if [ -e "$path" ] || [ -L "$path" ]; then
    if rm -rf "$path" 2>/dev/null; then printf '  [删除] %s\n' "$label"; else printf '  [FAIL] %s（DSH-E010）\n' "$label"; remove_failures=$((remove_failures + 1)); fi
  fi
}

stop_owned_processes() {
  all_processes="$(ps -axo pid=,ppid=,command= 2>/dev/null || true)"
  owned_pids=""
  while IFS= read -r record; do
    [ -n "$record" ] || continue
    pid="$(printf '%s\n' "$record" | awk '{print $1}')"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    [ "$pid" -eq "$$" ] && continue
    case "$record" in
      *"$INSTALL_ROOT"*"@deepseek-ai/dsh"*|*"$INSTALL_ROOT"*"start-dsh.command"*) owned_pids="$owned_pids $pid" ;;
    esac
  done <<EOF
$all_processes
EOF
  # Include children of an identified launcher so npx/node descendants are stopped too.
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0
    for parent in $owned_pids; do
      children="$(printf '%s\n' "$all_processes" | awk -v p="$parent" '$2 == p {print $1}')"
      for child in $children; do
        case " $owned_pids " in *" $child "*) ;; *) owned_pids="$owned_pids $child"; changed=1 ;; esac
      done
    done
  done
  for pid in $owned_pids; do
    if kill -0 "$pid" 2>/dev/null; then kill -TERM "$pid" 2>/dev/null || true; printf '  [停止] Harness 进程 PID %s\n' "$pid"; fi
  done
  [ -n "$owned_pids" ] && sleep 1
  for pid in $owned_pids; do
    if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
  done
}
stop_owned_processes

shortcut="$HOME/DeepSeekHarness/DeepSeek Harness.command"
launcher="$INSTALL_ROOT/launcher/start-dsh.command"
if [ -L "$shortcut" ] && [ "$(readlink "$shortcut" 2>/dev/null || true)" = "$launcher" ]; then
  remove_path "$shortcut" '用户可见启动方式'
fi
remove_path "$INSTALL_ROOT/runtime" '私有 Node Runtime'
remove_path "$INSTALL_ROOT/launcher" '启动器'
remove_path "$INSTALL_ROOT/cache" '缓存'
remove_path "$INSTALL_ROOT/config" '配置'

if [ "$PURGE" -eq 1 ]; then
  remove_path "$WORKSPACE_DIR" 'workspace'
  remove_path "$LOG_DIR" '日志'
else
  [ -d "$WORKSPACE_DIR" ] && printf '  [保留] workspace（用户数据）\n'
  [ -d "$LOG_DIR" ] && printf '  [保留] logs（如需彻底清除请加 --purge --yes）\n'
fi

rmdir "$INSTALL_ROOT" 2>/dev/null || true

if [ "$remove_failures" -gt 0 ]; then
  printf '\n卸载未完全完成，仍有 %s 项无法删除。请关闭相关程序后重试。\n' "$remove_failures"
  exit 1
fi
printf '\n卸载完成。用户已有 Node、workspace/logs（默认）未被删除。\n'
exit 0
