#!/bin/bash
set -euo pipefail
umask 077
PURGE=0
case "${1:-}" in
    '') ;;
    --purge) PURGE=1;;
    --help) printf 'Usage: uninstall-desktop-macos.sh [--purge]\n'; exit 0;;
    *) printf '[FAIL] DSH-D010: 未知参数。\n' >&2; exit 1;;
esac
[[ "$(uname -s)" == Darwin ]] || { printf '[FAIL] DSH-D009: 此卸载器只能在 macOS 上运行。\n' >&2; exit 1; }

APP_HOME="$(cd -P "$HOME" && pwd)"
APP_DIR="$APP_HOME/Applications"
APP_PATH="$APP_DIR/DeepSeek Harness.app"
BASE_DIR="$APP_HOME/Library/Application Support/DeepSeekHarnessDesktopDeployer"
RECEIPT="$BASE_DIR/receipts/desktop-macos.json"
RECEIPT_DIR="$BASE_DIR/receipts"
CACHE_DIR="$BASE_DIR/cache"
STATE_DIR="$BASE_DIR/state"
LOG_DIR="$APP_HOME/Library/Logs/DeepSeekHarnessDesktopDeployer"
LAUNCHER="$APP_HOME/Desktop/DeepSeek Harness Desktop.command"
BUNDLE_ID='com.deepseek.dsh'
TEAM_ID='NAN929V4UM'

fail() { printf '[FAIL] %s: %s\n' "$1" "$2" >&2; exit 1; }
[[ ! -L "$APP_HOME/Library" && ! -L "$APP_HOME/Library/Application Support" && ! -L "$APP_HOME/Library/Logs" && ! -L "$BASE_DIR" && ! -L "$RECEIPT_DIR" && ! -L "$APP_DIR" && ! -L "$APP_PATH" ]] || fail 'DSH-D007' '应用或部署器数据路径包含符号链接；没有删除任何内容。'
[[ -d "$APP_PATH" && -f "$RECEIPT" && ! -L "$RECEIPT" ]] || fail 'DSH-D004' '没有找到本部署器登记的桌面应用；不会删除同名或未知应用。'
/usr/bin/plutil -lint "$RECEIPT" >/dev/null 2>&1 || fail 'DSH-D007' '安装凭据损坏；不会删除应用。'
receipt_path="$(/usr/bin/plutil -extract path raw -o - "$RECEIPT" 2>/dev/null)" || fail 'DSH-D007' '无法读取安装凭据。'
receipt_bundle="$(/usr/bin/plutil -extract bundle_id raw -o - "$RECEIPT" 2>/dev/null)" || fail 'DSH-D007' '无法读取 Bundle ID。'
receipt_team="$(/usr/bin/plutil -extract team_id raw -o - "$RECEIPT" 2>/dev/null)" || fail 'DSH-D007' '无法读取 Team ID。'
[[ "$receipt_path" == "$APP_PATH" && "$receipt_bundle" == "$BUNDLE_ID" && "$receipt_team" == "$TEAM_ID" ]] || fail 'DSH-D007' '安装凭据与目标 App 不匹配；没有删除任何内容。'
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist" 2>/dev/null)" || fail 'DSH-D004' '无法读取应用 Bundle ID。'
[[ "$bundle_id" == "$BUNDLE_ID" ]] || fail 'DSH-D004' 'Bundle ID 不匹配；没有删除任何内容。'
/usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1 || fail 'DSH-D004' '应用签名验证失败；为安全起见没有自动删除。'
team_text="$(/usr/bin/codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
team_id="$(printf '%s\n' "$team_text" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ "$team_id" == "$TEAM_ID" ]] || fail 'DSH-D004' 'Team ID 不匹配；没有删除任何内容。'
/usr/sbin/spctl --assess --type execute "$APP_PATH" >/dev/null 2>&1 || fail 'DSH-D004' 'Gatekeeper 校验失败；没有删除任何内容。'

printf '将把已验证的 DeepSeek Harness Desktop 移到废纸篓：\n%s\n' "$APP_PATH"
printf '应用自身的数据和用户文件不由本卸载器删除。\n'
read -r -p '输入 REMOVE 确认卸载：' answer || answer=''
[[ "$answer" == REMOVE ]] || { printf '[WARN] 已取消；未删除任何内容。\n'; exit 2; }
if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
    [[ ! -L "$LAUNCHER" ]] || { printf '[WARN] 启动器是符号链接，保留不动。\n'; }
fi
/usr/bin/osascript -e 'on run argv' -e 'tell application "Finder" to delete POSIX file (item 1 of argv)' -e 'end run' "$APP_PATH" || fail 'DSH-D005' 'macOS 无法将应用移入废纸篓；请在 Finder 中手动拖到废纸篓，部署器数据保持不变。'
[[ ! -e "$APP_PATH" ]] || fail 'DSH-D005' '应用仍在原位置；没有清理凭据或日志。'
if [[ -f "$LAUNCHER" && ! -L "$LAUNCHER" ]]; then
    expected="$(printf '#!/bin/bash\n# Managed by DeepSeek Harness Desktop Deployer\nopen %q\n' "$APP_PATH")"
    if [[ "$(/usr/bin/cat "$LAUNCHER")" == "$expected" ]]; then /bin/rm -f "$LAUNCHER"; else printf '[WARN] 桌面启动器内容与本部署器记录不同，予以保留。\n'; fi
fi
/bin/rm -f "$RECEIPT"
printf '[PASS] 官方桌面应用已移到废纸篓；workspace、用户数据、旧 Web runtime、备份与日志均保留。\n'
if [[ "$PURGE" == 1 ]]; then
    [[ ! -e "$STATE_DIR/transaction.json" ]] || fail 'DSH-D007' '存在未完成事务，拒绝清理部署器缓存。'
    read -r -p '继续删除本部署器 cache 和日志？此操作不可从废纸篓恢复。输入 PURGE：' purge_answer || purge_answer=''
    [[ "$purge_answer" == PURGE ]] || { printf '[WARN] 已保留 cache 与日志。\n'; exit 0; }
    [[ ! -L "$BASE_DIR" && ! -L "$CACHE_DIR" && ! -L "$LOG_DIR" ]] || fail 'DSH-D007' '部署器数据目录包含符号链接；没有清理。'
    [[ "$CACHE_DIR" == "$BASE_DIR/cache" && "$LOG_DIR" == "$APP_HOME/Library/Logs/DeepSeekHarnessDesktopDeployer" ]] || fail 'DSH-D007' '清理路径校验失败。'
    [[ ! -e "$CACHE_DIR" ]] || /bin/rm -R "$CACHE_DIR"
    [[ ! -e "$BASE_DIR" ]] || /bin/rm -R "$BASE_DIR"
    [[ ! -e "$LOG_DIR" ]] || /bin/rm -R "$LOG_DIR"
    printf '[PASS] 本部署器缓存与日志已删除；备份 App 和用户数据仍保留。\n'
else
    printf '日志保留于：%s\n' "$LOG_DIR"
fi
