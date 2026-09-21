#!/bin/bash
# macOS M4 静态/运行环境自检。
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
pass=0
warn=0
fail=0
check_file() {
  name="$1"; path="$2"
  if [ -f "$path" ]; then printf '[PASS] %s\n' "$name"; pass=$((pass + 1)); else printf '[FAIL] %s\n' "$name"; fail=$((fail + 1)); fi
}
printf '==================================================\n'
printf ' DeepSeek Harness — macOS Productization Check\n'
printf '==================================================\n'
printf 'OS: %s\n' "$(uname -s 2>/dev/null || printf non-macOS)"
printf 'Architecture: %s\n' "$(uname -m 2>/dev/null || printf unknown)"
check_file install-macos.command "$ROOT/macos/install-macos.command"
check_file install-macos.sh "$ROOT/macos/install-macos.sh"
check_file start-dsh.command "$ROOT/macos/start-dsh.command"
check_file repair-macos.sh "$ROOT/macos/repair-macos.sh"
check_file uninstall-macos.sh "$ROOT/macos/uninstall-macos.sh"
for file in "$ROOT/macos/install-macos.sh" "$ROOT/macos/start-dsh.command" "$ROOT/macos/repair-macos.sh" "$ROOT/macos/uninstall-macos.sh"; do
  if bash -n "$file"; then printf '[PASS] bash syntax: %s\n' "$file"; pass=$((pass + 1)); else printf '[FAIL] bash syntax: %s\n' "$file"; fail=$((fail + 1)); fi
done
if [ "$(uname -s 2>/dev/null || true)" != Darwin ]; then
  printf '[WARN] 当前不是 macOS；未执行 Node 下载、npx、port、open 真机验证。\n'
  warn=$((warn + 1))
fi
printf 'Summary: PASS=%s WARN=%s FAIL=%s\n' "$pass" "$warn" "$fail"
[ "$fail" -eq 0 ]
