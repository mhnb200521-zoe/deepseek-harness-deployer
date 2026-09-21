#!/bin/bash
# DeepSeek Harness macOS 一键安装入口
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$SCRIPT_DIR/install-macos.sh" "$@"

