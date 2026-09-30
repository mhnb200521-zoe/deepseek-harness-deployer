#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/install-desktop-macos.sh"
if [[ ! -f "$INSTALLER" ]]; then
    printf '[FAIL] DSH-D004: 找不到桌面版安装器。\n' >&2
    exit 1
fi
exec /bin/bash "$INSTALLER" --repair "$@"
