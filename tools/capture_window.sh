#!/bin/bash
# Capture only the main window of an app (not the whole screen).
# Usage: tools/capture_window.sh [app process name] [output path]
# Defaults: app=class_set, out=/tmp/class_set_window.png
set -euo pipefail

APP_NAME="${1:-class_set}"
OUT="${2:-/tmp/class_set_window.png}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

INFO="$(swift "$REPO_ROOT/tools/find_window.swift" "$APP_NAME")" || {
  echo "window not found for app '$APP_NAME' (is it running and visible?)" >&2
  exit 1
}

WIN_ID="$(echo "$INFO" | awk '{print $1}')"
POS="$(echo "$INFO" | awk '{print $2, $3, $4, $5}')"
screencapture -l "$WIN_ID" -x -t png "$OUT"
echo "$OUT [window $POS]"
