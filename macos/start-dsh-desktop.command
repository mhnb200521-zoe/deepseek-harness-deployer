#!/bin/bash
APP_PATH="$HOME/Applications/DeepSeek Harness.app"
if [[ ! -d "$APP_PATH" || -L "$APP_PATH" ]]; then
    printf 'DeepSeek Harness Desktop was not found at the expected user Applications path.\n'
    read -r -p 'Press Return to close.' _
    exit 1
fi
exec open "$APP_PATH"
