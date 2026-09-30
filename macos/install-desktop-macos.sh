#!/bin/bash
set -Eeuo pipefail
umask 077

readonly APP_NAME='DeepSeek Harness.app'
readonly BUNDLE_ID='com.deepseek.dsh'
readonly TEAM_ID='NAN929V4UM'
readonly ORIGIN='https://download.deepseek.com'
readonly PUBLISHER='DeepSeek Harness Desktop'
readonly ERROR_PREFIX='DSH-D'
readonly SELF_TEST="${1:-}"

STAGE='Init'
LOG_FILE=''
ARCH_TARGET=''
FEED_NAME=''
RELEASE_VERSION=''
RELEASE_URL=''
RELEASE_SIZE=''
RELEASE_SHA512=''
APP_HOME=''
APP_DIR=''
APP_PATH=''
BASE_DIR=''
CACHE_DIR=''
RECEIPT_DIR=''
RECEIPT=''
STATE_DIR=''
JOURNAL=''
DESKTOP_DIR=''
LAUNCHER=''

event() {
    local level="$1" message="$2"
    message="$(printf '%s' "$message" | sed -E 's/((token|api[_-]?key|password|cookie|authorization)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED]/g; s/sk-[A-Za-z0-9_-]+/[REDACTED]/g')"
    printf '[%s] %s\n' "$level" "$message"
    if [[ -n "$LOG_FILE" ]]; then
        printf '%s [%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$STAGE" "$message" >> "$LOG_FILE"
    fi
}

fail() {
    local id="$1"; shift
    event FAIL "${id}: $*"
    if [[ -n "$LOG_FILE" ]]; then printf '日志：%s\n' "$LOG_FILE"; fi
    exit 1
}

unexpected_error() {
    local rc="$1" line="$2"
    trap - ERR
    fail 'DSH-D999' "遇到未预期错误（exit=${rc}, line=${line}）。请提供错误编号和日志。"
}
trap 'unexpected_error $? $LINENO' ERR

json_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '"%s"' "$value"
}

write_journal() {
    local phase="$1" existed="$2" version="$3" old_version="$4" stage_root="$5" backup="$6"
    local tmp
    # macOS/BSD mktemp requires the template to end with X characters; the
    # temporary file contains JSON, so it does not need a .json filename suffix.
    tmp="$(mktemp "$STATE_DIR/.transaction.XXXXXX")" || fail 'DSH-D007' '无法安全创建事务记录临时文件。'
    {
        printf '{"target":%s,' "$(json_quote "$APP_PATH")"
        printf '"stage_root":%s,' "$(json_quote "$stage_root")"
        printf '"backup":%s,' "$(json_quote "$backup")"
        printf '"phase":%s,' "$(json_quote "$phase")"
        printf '"target_existed":%s,' "$existed"
        printf '"version":%s,' "$(json_quote "$version")"
        printf '"old_version":%s}\n' "$(json_quote "$old_version")"
    } > "$tmp"
    /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || fail 'DSH-D007' '事务记录格式校验失败，未继续替换应用。'
    mv -f "$tmp" "$JOURNAL"
}

read_journal() {
    /usr/bin/plutil -extract "$1" raw -o - "$JOURNAL" 2>/dev/null
}

assert_no_symlink() {
    local path="$1" label="$2"
    [[ ! -L "$path" ]] || fail 'DSH-D007' "$label 是符号链接；为避免操作路径外文件，已停止。"
}

ensure_dir() {
    local path="$1" label="$2"
    assert_no_symlink "$path" "$label"
    mkdir -p "$path" || fail 'DSH-D010' "$label 无法创建，请检查当前用户目录权限。"
    assert_no_symlink "$path" "$label"
    [[ -d "$path" ]] || fail 'DSH-D010' "$label 不是目录。"
}

version_valid() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]
}

parse_feed() {
    local body="$1" target="$2"
    RELEASE_VERSION="$(printf '%s\n' "$body" | awk -F': ' '$1 == "version" {print $2; exit}')"
    RELEASE_URL="$(printf '%s\n' "$body" | awk '/^path: >-/{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')"
    local first_url first_sha
    first_url="$(printf '%s\n' "$body" | awk '/^[[:space:]]+- url: >-/{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')"
    RELEASE_SHA512="$(printf '%s\n' "$body" | awk '/^sha512: >-/{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')"
    first_sha="$(printf '%s\n' "$body" | awk '/^[[:space:]]+sha512: >-/{getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}')"
    RELEASE_SIZE="$(printf '%s\n' "$body" | awk '/^[[:space:]]+size:/{print $2; exit}')"
    [[ -n "$RELEASE_VERSION" && -n "$RELEASE_URL" && "$RELEASE_URL" == "$first_url" && -n "$RELEASE_SHA512" && "$RELEASE_SHA512" == "$first_sha" && "$RELEASE_SIZE" =~ ^[0-9]+$ ]] || return 1
    version_valid "$RELEASE_VERSION" || return 1
    [[ "$RELEASE_SHA512" =~ ^[A-Za-z0-9+/]{86}==$ ]] || return 1
    awk -v size="$RELEASE_SIZE" 'BEGIN { exit !(size >= 1000000) }' || return 1
    local expected_url="${ORIGIN}/dsh-desk/bin/${target}/deepseek-harness-${RELEASE_VERSION}-${target}.zip"
    [[ "$RELEASE_URL" == "$expected_url" ]]
}

read_feed() {
    local channel="$1" feed_path="$2" http_status body_file
    body_file="$(mktemp "$CACHE_DIR/.feed-${ARCH_TARGET}-${channel}.XXXXXX")" || fail 'DSH-D010' '无法安全创建 feed 暂存文件。'
    if [[ "$channel" == stable ]]; then
        FEED_NAME='latest-mac.yml'
    else
        FEED_NAME='nightly-mac.yml'
    fi
    STAGE='Feed'
    http_status="$(curl --silent --show-error --max-redirs 0 --connect-timeout 20 --max-time 45 \
        --output "$body_file" --write-out '%{http_code}' "$feed_path" 2>>"$LOG_FILE")" || {
        rm -f "$body_file"
        fail 'DSH-D001' '无法读取 DeepSeek 官方版本清单。请检查网络、DNS 或代理后重试。'
    }
    if [[ "$http_status" == 404 && "$channel" == stable ]]; then
        rm -f "$body_file"
        return 3
    fi
    [[ "$http_status" == 200 ]] || { rm -f "$body_file"; fail 'DSH-D001' "官方版本清单返回 HTTP ${http_status}；没有切换到其他来源。"; }
    local body
    body="$(/usr/bin/sed -n '1,80p' "$body_file")"
    rm -f "$body_file"
    parse_feed "$body" "$ARCH_TARGET" || fail 'DSH-D002' '官方版本清单字段、版本、架构或下载地址不符合预期。'
    event PASS "官方 ${channel} 清单有效；目标架构 ${ARCH_TARGET}，版本 ${RELEASE_VERSION}。"
    return 0
}

sha512_base64() {
    /usr/bin/shasum -a 512 "$1" | /usr/bin/awk '{print $1}' | /usr/bin/xxd -r -p | /usr/bin/base64 | /usr/bin/tr -d '\n'
}

app_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null
}

verify_app() {
    local candidate="$1" expected_version="${2:-}" bundle_id version team_data team_id
    [[ -d "$candidate" && ! -L "$candidate" && -f "$candidate/Contents/Info.plist" ]] || return 1
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null)" || return 1
    version="$(app_version "$candidate")" || return 1
    [[ "$bundle_id" == "$BUNDLE_ID" ]] || return 1
    version_valid "$version" || return 1
    [[ -z "$expected_version" || "$version" == "$expected_version" ]] || return 1
    /usr/bin/codesign --verify --deep --strict "$candidate" >/dev/null 2>>"$LOG_FILE" || return 1
    team_data="$(/usr/bin/codesign -dv --verbose=4 "$candidate" 2>&1 || true)"
    team_id="$(printf '%s\n' "$team_data" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    [[ "$team_id" == "$TEAM_ID" ]] || return 1
    /usr/sbin/spctl --assess --type execute --verbose=2 "$candidate" >/dev/null 2>>"$LOG_FILE" || return 1
    return 0
}

receipt_matches() {
    [[ -f "$RECEIPT" && ! -L "$RECEIPT" ]] || return 1
    local path bundle_id team_id
    path="$(/usr/bin/plutil -extract path raw -o - "$RECEIPT" 2>/dev/null)" || return 1
    bundle_id="$(/usr/bin/plutil -extract bundle_id raw -o - "$RECEIPT" 2>/dev/null)" || return 1
    team_id="$(/usr/bin/plutil -extract team_id raw -o - "$RECEIPT" 2>/dev/null)" || return 1
    [[ "$path" == "$APP_PATH" && "$bundle_id" == "$BUNDLE_ID" && "$team_id" == "$TEAM_ID" ]]
}

write_receipt() {
    local version="$1" tmp
    tmp="$(mktemp "$RECEIPT_DIR/.desktop-macos.XXXXXX")" || fail 'DSH-D007' '无法安全创建安装凭据临时文件。'
    {
        printf '{"path":%s,' "$(json_quote "$APP_PATH")"
        printf '"bundle_id":%s,' "$(json_quote "$BUNDLE_ID")"
        printf '"team_id":%s,' "$(json_quote "$TEAM_ID")"
        printf '"version":%s}\n' "$(json_quote "$version")"
    } > "$tmp"
    /usr/bin/plutil -lint "$tmp" >/dev/null 2>&1 || fail 'DSH-D007' '安装凭据格式校验失败。'
    mv -f "$tmp" "$RECEIPT"
}

valid_transaction_paths() {
    local target="$1" stage_root="$2" backup="$3"
    [[ "$target" == "$APP_PATH" ]] || return 1
    [[ "$stage_root" == "$APP_DIR"/.DeepSeekHarness-staging-* ]] || return 1
    [[ "$backup" == "$APP_DIR"/.DeepSeekHarness-backup-*.app ]] || return 1
    [[ "$(dirname "$stage_root")" == "$APP_DIR" && "$(dirname "$backup")" == "$APP_DIR" ]]
}

recover_transaction() {
    [[ -e "$JOURNAL" ]] || return 0
    assert_no_symlink "$JOURNAL" '事务记录'
    /usr/bin/plutil -lint "$JOURNAL" >/dev/null 2>&1 || fail 'DSH-D007' '发现损坏的安装事务记录；请勿手动删除应用，需人工检查。'
    local target stage_root backup phase existed version old_version staged_app
    target="$(read_journal target)" || fail 'DSH-D007' '无法读取事务目标路径。'
    stage_root="$(read_journal stage_root)" || fail 'DSH-D007' '无法读取事务暂存路径。'
    backup="$(read_journal backup)" || fail 'DSH-D007' '无法读取事务备份路径。'
    phase="$(read_journal phase)" || fail 'DSH-D007' '无法读取事务阶段。'
    existed="$(read_journal target_existed)" || fail 'DSH-D007' '无法读取事务旧版本状态。'
    version="$(read_journal version)" || fail 'DSH-D007' '无法读取事务版本。'
    old_version="$(read_journal old_version)" || fail 'DSH-D007' '无法读取旧版本号。'
    valid_transaction_paths "$target" "$stage_root" "$backup" || fail 'DSH-D007' '事务记录包含非预期路径；为保护文件已停止。'
    assert_no_symlink "$stage_root" '暂存目录'
    assert_no_symlink "$backup" '备份应用'
    staged_app="$stage_root/$APP_NAME"
    if [[ -e "$APP_PATH" ]] && verify_app "$APP_PATH" "$version"; then
        write_receipt "$version"
        rm -f "$JOURNAL"
        event WARN "发现未完成事务并确认目标版本有效；已保留备份（如存在）：${backup}。"
        return 0
    fi
    if [[ ! -e "$APP_PATH" && -e "$backup" ]] && verify_app "$backup" "$old_version"; then
        mv "$backup" "$APP_PATH" || fail 'DSH-D007' '旧应用回滚失败；备份仍保留在事务记录路径。'
        rm -f "$JOURNAL"
        event WARN "发现中断升级；已恢复原版本 ${old_version}。暂存文件（如存在）保留于 ${stage_root}。"
        return 0
    fi
    if [[ -e "$APP_PATH" && ! -e "$backup" && -n "$old_version" ]] && verify_app "$APP_PATH" "$old_version"; then
        rm -f "$JOURNAL"
        event WARN "发现升级尚未移动旧 App，或旧版已恢复；保留原版本 ${old_version}，暂存内容不自动删除。"
        return 0
    fi
    if [[ "$existed" == false && ! -e "$APP_PATH" && -e "$staged_app" ]] && verify_app "$staged_app" "$version"; then
        mv "$staged_app" "$APP_PATH" || fail 'DSH-D007' '首次安装恢复失败；暂存应用仍保留。'
        verify_app "$APP_PATH" "$version" || fail 'DSH-D007' '恢复后的应用校验失败；请人工检查事务路径。'
        write_receipt "$version"
        rm -f "$JOURNAL"
        event WARN "已恢复中断的首次安装版本 ${version}。"
        return 0
    fi
    fail 'DSH-D007' "安装事务状态无法安全自动恢复。目标=${APP_PATH}; 备份=${backup}; 暂存=${stage_root}。"
}

assert_no_unresolved_transactions() {
    local candidate
    for candidate in "$APP_DIR"/.DeepSeekHarness-backup-*.app "$APP_DIR"/.DeepSeekHarness-staging-* "$APP_DIR"/.DeepSeekHarness-failed-*.app; do
        if [[ -e "$candidate" || -L "$candidate" ]]; then
            fail 'DSH-D007' "发现未处理的应用备份或暂存目录：${candidate}。为避免删除旧版本，本次不会继续替换。"
        fi
    done
}

compare_versions() {
    local left="$1" right="$2" lm ln lp ls lr rm rn rp rs rr
    [[ "$left" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta|rc)\.([0-9]+))?$ ]] || return 2
    lm="${BASH_REMATCH[1]}"; ln="${BASH_REMATCH[2]}"; lp="${BASH_REMATCH[3]}"; ls="${BASH_REMATCH[5]:-stable}"; lr="${BASH_REMATCH[6]:-0}"
    [[ "$right" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta|rc)\.([0-9]+))?$ ]] || return 2
    rm="${BASH_REMATCH[1]}"; rn="${BASH_REMATCH[2]}"; rp="${BASH_REMATCH[3]}"; rs="${BASH_REMATCH[5]:-stable}"; rr="${BASH_REMATCH[6]:-0}"
    for pair in "$lm:$rm" "$ln:$rn" "$lp:$rp"; do
        local a="${pair%%:*}" b="${pair#*:}"
        ((10#$a > 10#$b)) && { printf '1'; return 0; }
        ((10#$a < 10#$b)) && { printf '%s' '-1'; return 0; }
    done
    local rank_left rank_right
    case "$ls" in alpha) rank_left=0;; beta) rank_left=1;; rc) rank_left=2;; stable) rank_left=3;; esac
    case "$rs" in alpha) rank_right=0;; beta) rank_right=1;; rc) rank_right=2;; stable) rank_right=3;; esac
    ((rank_left > rank_right)) && { printf '1'; return 0; }
    ((rank_left < rank_right)) && { printf '%s' '-1'; return 0; }
    ((10#$lr > 10#$rr)) && { printf '1'; return 0; }
    ((10#$lr < 10#$rr)) && { printf '%s' '-1'; return 0; }
    printf '0'
}

launcher_expected_content() {
    local marker='# Managed by DeepSeek Harness Desktop Deployer'
    printf '#!/bin/bash\n%s\nopen %q\n' "$marker" "$APP_PATH"
}

validate_launcher_destination() {
    local expected
    expected="$(launcher_expected_content)"
    assert_no_symlink "$DESKTOP_DIR" '桌面目录'
    ensure_dir "$DESKTOP_DIR" '桌面目录'
    if [[ -e "$LAUNCHER" ]]; then
        assert_no_symlink "$LAUNCHER" '桌面启动器'
        if [[ "$(/usr/bin/cat "$LAUNCHER")" != "$expected" ]]; then
            fail 'DSH-D008' '桌面已存在同名但不属于本部署器的启动文件；没有覆盖。'
        fi
    fi
}

create_launcher() {
    local expected tmp
    validate_launcher_destination
    expected="$(launcher_expected_content)"
    tmp="$(mktemp "$DESKTOP_DIR/.DeepSeekHarnessDesktop.XXXXXX")" || fail 'DSH-D008' '无法安全创建桌面启动器临时文件。'
    printf '%s\n' "$expected" > "$tmp"
    chmod 700 "$tmp"
    mv -f "$tmp" "$LAUNCHER"
    [[ -x "$LAUNCHER" ]] || fail 'DSH-D008' '创建桌面启动器失败。'
    event PASS '桌面启动器已创建：DeepSeek Harness Desktop.command。'
}

launch_and_confirm() {
    STAGE='Verification'
    open "$APP_PATH" || fail 'DSH-D006' 'macOS 未能打开已验证的桌面应用。'
    event WARN '已请求 macOS 从目标安装路径启动应用；UI 就绪需要本机用户确认。'
    printf '请确认 DeepSeek Harness 桌面窗口已打开且欢迎页/工作区可操作。\n'
    read -r -p '桌面 UI 可正常使用？ [y/N] ' answer || answer=''
    [[ "$answer" =~ ^[yY]$ ]] || fail 'DSH-D006' '桌面 UI 未经用户确认，部署不能标记完成。'
    event PASS '用户确认桌面 UI 可操作。'
}

run_selftest() {
    local sample bad x64sample result
    sample="$(cat <<'FEED'
version: 0.2.0-rc.2
files:
  - url: >-
      https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-0.2.0-rc.2-mac-arm64.zip
    sha512: >-
      BIC7PMWuEEzM7OuK8tMXQR0AdtVlYrSP1usHGWSAOhbxeXOzq2s1i71jZphMQSoQ/8tUQr55a158JW8xScseuA==
    size: 374053565
path: >-
  https://download.deepseek.com/dsh-desk/bin/mac-arm64/deepseek-harness-0.2.0-rc.2-mac-arm64.zip
sha512: >-
  BIC7PMWuEEzM7OuK8tMXQR0AdtVlYrSP1usHGWSAOhbxeXOzq2s1i71jZphMQSoQ/8tUQr55a158JW8xScseuA==
FEED
)"
    parse_feed "$sample" mac-arm64 || { printf 'desktop-macos selftest: FAIL (valid feed rejected)\n' >&2; return 1; }
    [[ "$RELEASE_VERSION" == '0.2.0-rc.2' && "$RELEASE_SIZE" == '374053565' ]] || return 1
    x64sample="${sample//mac-arm64/mac-x64}"
    parse_feed "$x64sample" mac-x64 || { printf 'desktop-macos selftest: FAIL (Intel target rejected)\n' >&2; return 1; }
    bad="${sample/https:\/\/download.deepseek.com/https:\/\/attacker.example}"
    if parse_feed "$bad" mac-arm64; then printf 'desktop-macos selftest: FAIL (foreign host accepted)\n' >&2; return 1; fi
    [[ "$(compare_versions '0.2.0-rc.3' '0.2.0-rc.2')" == 1 ]] || return 1
    [[ "$(compare_versions '0.2.0-rc.2' '0.2.0')" == '-1' ]] || return 1
    printf 'desktop-macos selftest: PASS (arm64, x86_64, official host, version order)\n'
}

main() {
    if [[ "$SELF_TEST" == '--self-test' ]]; then run_selftest; return; fi
    local probe_only=0 upgrade=0 repair=0 arg
    for arg in "$@"; do
        case "$arg" in
            --probe-only) probe_only=1;;
            --upgrade) upgrade=1;;
            --repair) repair=1;;
            --help)
                printf 'Usage: install-desktop-macos.command [--probe-only] [--upgrade|--repair]\n'
                return 0;;
            *) fail 'DSH-D010' "未知参数：${arg}";;
        esac
    done
    [[ "$(uname -s)" == Darwin ]] || fail 'DSH-D009' '桌面版 macOS 安装器必须在 macOS 上运行。'
    for dependency in curl awk sed shasum xxd base64 ditto codesign spctl open plutil stat mktemp; do
        command -v "$dependency" >/dev/null 2>&1 || fail 'DSH-D010' "macOS 必要系统工具不可用：${dependency}。不会自动安装额外依赖。"
    done
    [[ -x /usr/libexec/PlistBuddy ]] || fail 'DSH-D010' 'macOS PlistBuddy 不可用。'
    local machine_arch
    machine_arch="$(uname -m)"
    if [[ "$machine_arch" == arm64 ]]; then
        ARCH_TARGET='mac-arm64'
    elif [[ "$machine_arch" == x86_64 ]]; then
        if [[ "$(/usr/sbin/sysctl -in hw.optional.arm64 2>/dev/null || true)" == 1 ]]; then ARCH_TARGET='mac-arm64'; else ARCH_TARGET='mac-x64'; fi
    else
        fail 'DSH-D009' "不支持的 CPU 架构：${machine_arch}。"
    fi
    APP_HOME="$(cd -P "$HOME" && pwd)"
    APP_DIR="$APP_HOME/Applications"
    APP_PATH="$APP_DIR/$APP_NAME"
    BASE_DIR="$APP_HOME/Library/Application Support/DeepSeekHarnessDesktopDeployer"
    CACHE_DIR="$BASE_DIR/cache"
    RECEIPT_DIR="$BASE_DIR/receipts"
    RECEIPT="$RECEIPT_DIR/desktop-macos.json"
    STATE_DIR="$BASE_DIR/state"
    JOURNAL="$STATE_DIR/transaction.json"
    DESKTOP_DIR="$APP_HOME/Desktop"
    LAUNCHER="$DESKTOP_DIR/DeepSeek Harness Desktop.command"
    [[ ! -L "$APP_HOME/Library" ]] || fail 'DSH-D007' '用户 Library 路径为符号链接；为保护数据已停止。'
    ensure_dir "$APP_DIR" '用户 Applications 目录'
    ensure_dir "$APP_HOME/Library/Application Support" 'Application Support 目录'
    ensure_dir "$BASE_DIR" '部署器数据目录'
    ensure_dir "$CACHE_DIR" '下载缓存目录'
    ensure_dir "$RECEIPT_DIR" '安装凭据目录'
    ensure_dir "$STATE_DIR" '事务状态目录'
    ensure_dir "$APP_HOME/Library/Logs" '用户日志目录'
    ensure_dir "$APP_HOME/Library/Logs/DeepSeekHarnessDesktopDeployer" '日志目录'
    LOG_FILE="$APP_HOME/Library/Logs/DeepSeekHarnessDesktopDeployer/install-$(date '+%Y%m%d-%H%M%S')-$$.log"
    [[ ! -e "$LOG_FILE" && ! -L "$LOG_FILE" ]] || fail 'DSH-D010' '日志路径已存在或为符号链接；为保护用户数据已停止。'
    : > "$LOG_FILE"
    STAGE='SystemCheck'
    event INFO "macOS 架构=${ARCH_TARGET}；安装目录=${APP_PATH}。"
    event PASS '系统与 CPU 架构检查完成。'

    STAGE='Recovery'
    assert_no_symlink "$JOURNAL" '事务记录'
    assert_no_symlink "$RECEIPT" '安装凭据'
    recover_transaction
    local existing_version='' owned=0
    if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
        assert_no_symlink "$APP_PATH" '现有应用'
        verify_app "$APP_PATH" || fail 'DSH-D004' '目标路径存在应用，但 Bundle ID、签名、Team ID 或 Gatekeeper 校验不符合官方桌面版。'
        existing_version="$(app_version "$APP_PATH")"
        if receipt_matches; then owned=1; fi
        event PASS "发现官方桌面版 ${existing_version}；不会删除其用户数据。"
    else
        event INFO '目标安装目录尚无桌面版。'
    fi
    if [[ "$probe_only" == 1 ]]; then
        [[ -n "$existing_version" ]] || fail 'DSH-D004' '本机尚未安装官方桌面版。'
        event PASS '只读探测完成；没有下载、安装或启动应用。'
        return 0
    fi
    [[ "$upgrade" == 0 || "$repair" == 0 ]] || fail 'DSH-D010' '不能同时指定 --upgrade 与 --repair。'
    if [[ "$repair" == 1 && -z "$existing_version" ]]; then
        fail 'DSH-D004' '未找到可验证的官方桌面安装；修复模式不会安装缺失或未知的 App。'
    fi
    if [[ "$repair" == 1 && "$owned" != 1 ]]; then
        fail 'DSH-D004' '现有官方 App 没有本部署器安装凭据；为避免覆盖用户应用，不能使用此修复入口。'
    fi
    if [[ -n "$existing_version" && "$upgrade" == 0 && "$repair" == 0 ]]; then
        create_launcher
        launch_and_confirm
        event PASS "已复用官方桌面版 ${existing_version}。"
        return 0
    fi
    if [[ -n "$existing_version" && "$owned" != 1 ]]; then
        fail 'DSH-D004' '发现未由本部署器登记的官方应用；不会自动覆盖。请使用应用内更新，或移除后重试。'
    fi
    assert_no_unresolved_transactions

    STAGE='VersionSelection'
    local feed_url="$ORIGIN/dsh-desk/feeds/$ARCH_TARGET/latest-mac.yml" rc
    if read_feed stable "$feed_url"; then
        :
    else
        rc=$?
        [[ "$rc" == 3 ]] || fail 'DSH-D001' '稳定版清单读取失败。'
        event WARN '官方稳定版清单返回 HTTP 404；候选版不是稳定版。'
        feed_url="$ORIGIN/dsh-desk/feeds/$ARCH_TARGET/nightly-mac.yml"
        read_feed preview "$feed_url"
        event WARN "将安装官方预发布版本 ${RELEASE_VERSION}（Preview/RC），可能存在缺陷或兼容变化。"
        read -r -p '你确认安装此预发布版本吗？ [y/N] ' consent || consent=''
        [[ "$consent" =~ ^[yY]$ ]] || { event WARN '用户取消预发布安装；未执行任何应用替换。'; return 2; }
    fi
    if [[ -n "$existing_version" ]]; then
        rc="$(compare_versions "$RELEASE_VERSION" "$existing_version")" || fail 'DSH-D004' '无法可靠比较当前版本与目标版本。'
        [[ "$rc" != '-1' ]] || fail 'DSH-D004' '目标版本低于现有版本；已阻止降级。'
        if [[ "$rc" == 0 ]]; then
            if [[ "$repair" == 0 ]]; then
                create_launcher
                launch_and_confirm
                event PASS "桌面版已是目标版本 ${existing_version}；没有重新安装。"
                return 0
            fi
            event WARN "修复模式将从已验证的官方 ZIP 重新安装同一版本 ${existing_version}。"
        elif [[ "$repair" == 1 ]]; then
            fail 'DSH-D004' '官方清单已切换到其他版本；修复模式只重装当前版本，请先评估后再使用升级入口。'
        else
            read -r -p "确认把桌面版从 ${existing_version} 升级到 ${RELEASE_VERSION}？ [y/N] " consent || consent=''
            [[ "$consent" =~ ^[yY]$ ]] || { event WARN '用户取消升级；现有应用保持不变。'; return 2; }
        fi
        if [[ "$repair" == 1 ]]; then
            read -r -p "确认重新安装已登记的同版本 ${existing_version}？ [y/N] " consent || consent=''
            [[ "$consent" =~ ^[yY]$ ]] || { event WARN '用户取消修复；现有应用保持不变。'; return 2; }
        fi
    fi
    validate_launcher_destination

    STAGE='Download'
    local zip="$CACHE_DIR/deepseek-harness-${RELEASE_VERSION}-${ARCH_TARGET}.zip"
    local partial="$zip.part" http_status actual_size actual_sha
    if [[ -e "$zip" || -L "$zip" ]]; then
        assert_no_symlink "$zip" '缓存安装包'
        [[ -f "$zip" ]] || fail 'DSH-D003' '缓存路径不是普通文件；为避免覆盖，未继续。'
        actual_size="$(stat -f%z "$zip")"
        actual_sha="$(sha512_base64 "$zip")"
        [[ "$actual_size" == "$RELEASE_SIZE" && "$actual_sha" == "$RELEASE_SHA512" ]] || fail 'DSH-D003' '缓存中的官方安装包校验失败；为避免覆盖，未继续。请联系技术支持清理对应缓存。'
    else
        if [[ -e "$partial" || -L "$partial" ]]; then
            assert_no_symlink "$partial" '未完成下载文件'
            [[ -f "$partial" ]] || fail 'DSH-D003' '下载暂存路径不是普通文件；未覆盖。'
            rm -f "$partial"
        fi
        http_status="$(curl --silent --show-error --max-redirs 0 --connect-timeout 25 --max-time 900 \
            --output "$partial" --write-out '%{http_code}' "$RELEASE_URL" 2>>"$LOG_FILE")" || fail 'DSH-D003' '官方桌面版下载失败；请检查网络后重试。'
        [[ "$http_status" == 200 ]] || fail 'DSH-D003' "官方安装包返回 HTTP ${http_status}；没有跟随重定向。"
        actual_size="$(stat -f%z "$partial")"
        actual_sha="$(sha512_base64 "$partial")"
        if [[ "$actual_size" != "$RELEASE_SIZE" || "$actual_sha" != "$RELEASE_SHA512" ]]; then
            rm -f "$partial"
            fail 'DSH-D003' '官方安装包大小或 SHA-512 不匹配；已删除本次不完整下载，未执行。'
        fi
        mv "$partial" "$zip"
    fi
    event PASS "官方安装包大小和 SHA-512 校验通过（${RELEASE_VERSION}）。"

    STAGE='Install'
    local transaction_id="$(date '+%Y%m%d%H%M%S')-$$"
    local stage_root="$APP_DIR/.DeepSeekHarness-staging-${transaction_id}"
    local staged_app="$stage_root/$APP_NAME"
    local backup="$APP_DIR/.DeepSeekHarness-backup-${transaction_id}.app"
    [[ ! -e "$stage_root" && ! -e "$backup" ]] || fail 'DSH-D007' '临时事务路径已存在；为避免覆盖已停止。'
    mkdir -m 700 "$stage_root" || fail 'DSH-D010' '无法创建应用暂存目录。'
    ditto -x -k "$zip" "$stage_root" 2>>"$LOG_FILE" || fail 'DSH-D005' "无法解压已校验的官方 ZIP；暂存目录保留在 ${stage_root}。"
    verify_app "$staged_app" "$RELEASE_VERSION" || fail 'DSH-D004' "解压后的 App Bundle、版本、签名、公证或 Team ID 校验失败；暂存目录保留在 ${stage_root}。"
    event PASS 'App Bundle、Bundle ID、版本、签名、Team ID 与 Gatekeeper 校验通过。'
    local target_existed=false old_for_journal=''
    if [[ -n "$existing_version" ]]; then target_existed=true; old_for_journal="$existing_version"; fi
    write_journal prepared "$target_existed" "$RELEASE_VERSION" "$old_for_journal" "$stage_root" "$backup"
    if [[ "$target_existed" == true ]]; then
        mv "$APP_PATH" "$backup" || fail 'DSH-D007' "无法安全备份现有应用；备份路径预留为 ${backup}。"
        write_journal backed_up true "$RELEASE_VERSION" "$old_for_journal" "$stage_root" "$backup"
    fi
    if ! mv "$staged_app" "$APP_PATH"; then
        if [[ "$target_existed" == true && ! -e "$APP_PATH" && -e "$backup" ]]; then mv "$backup" "$APP_PATH" || fail 'DSH-D007' "新应用放置失败且旧版回滚失败；旧版备份位于 ${backup}。"; fi
        fail 'DSH-D005' '无法把已验证应用放入用户 Applications。'
    fi
    write_journal promoted "$target_existed" "$RELEASE_VERSION" "$old_for_journal" "$stage_root" "$backup"
    if ! verify_app "$APP_PATH" "$RELEASE_VERSION"; then
        local failed="$APP_DIR/.DeepSeekHarness-failed-${transaction_id}.app"
        mv "$APP_PATH" "$failed" || fail 'DSH-D007' "安装后的 App 校验失败且无法移出目标目录；请人工检查 ${APP_PATH}。"
        if [[ "$target_existed" == true && -e "$backup" ]]; then
            mv "$backup" "$APP_PATH" || fail 'DSH-D007' "新版本校验失败，且旧版恢复失败；备份仍位于 ${backup}。"
            rm -f "$JOURNAL"
            fail 'DSH-D004' "安装后的 App 校验失败；旧版本已恢复，失败版本保留在 ${failed}。"
        fi
        rm -f "$JOURNAL"
        fail 'DSH-D004' "首次安装后 App 校验失败；失败版本保留在 ${failed}，未启动。"
    fi
    write_receipt "$RELEASE_VERSION"
    write_journal complete "$target_existed" "$RELEASE_VERSION" "$old_for_journal" "$stage_root" "$backup"
    rm -f "$JOURNAL"
    rmdir "$stage_root" 2>/dev/null || true
    event PASS "桌面应用安装完成；原版本备份（如有）保留于 ${backup}。"

    STAGE='Launcher'
    create_launcher
    launch_and_confirm
    event PASS "DeepSeek Harness 桌面版 ${RELEASE_VERSION} 安装并启动完成。"
    printf '已安装到：%s\n' "$APP_PATH"
    printf '桌面启动器：%s\n' "$LAUNCHER"
    printf '请在应用 Settings → Models 中自行配置模型/API；本部署器不会收集或保存 API Key。\n'
}

main "$@"
