#!/bin/bash
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)" || exit 1
exec /bin/bash "$SCRIPT_DIR/install-desktop-macos.sh" "$@"
