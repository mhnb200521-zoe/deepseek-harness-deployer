#!/bin/bash
set -euo pipefail
ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/macos/install-desktop-macos.sh"
ENTRY="$ROOT/macos/install-desktop-macos.command"
STARTER="$ROOT/macos/start-dsh-desktop.command"
REPAIR="$ROOT/macos/repair-desktop-macos.sh"
UNINSTALL="$ROOT/macos/uninstall-desktop-macos.sh"

bash -n "$INSTALLER"
bash -n "$ENTRY"
bash -n "$STARTER"
bash -n "$REPAIR"
bash -n "$UNINSTALL"
echo '[PASS] macOS desktop shell syntax'

output="$(bash "$INSTALLER" --self-test)"
[[ "$output" == *'desktop-macos selftest: PASS'* ]]
echo '[PASS] macOS feed, host, and version parser self-test'

grep -Fq 'download.deepseek.com' "$INSTALLER"
grep -Fq 'shasum -a 512' "$INSTALLER"
grep -Fq 'codesign --verify --deep --strict' "$INSTALLER"
grep -Fq 'spctl --assess --type execute' "$INSTALLER"
grep -Fq 'open "$APP_PATH"' "$INSTALLER"
grep -Fq 'osascript' "$UNINSTALL"
grep -Fq 'REMOVE' "$UNINSTALL"
if grep -E 'mktemp[[:space:]]+"[^"]*X{6}[^"]+"' "$INSTALLER"; then
    echo '[FAIL] macOS mktemp templates must end in XXXXXX' >&2
    exit 1
fi
! grep -Eq 'xattr .*com\.apple\.quarantine|spctl .*master-disable' "$INSTALLER" "$UNINSTALL"
echo '[PASS] official source, integrity, Gatekeeper, path-based launch, and BSD mktemp controls'

echo 'macos-desktop-check: PASS'
