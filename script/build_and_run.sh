#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="my-first-macos-app"
BUNDLE_ID="com.perryfinn.my-first-macos-app"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
PROJECT_PATH="$ROOT_DIR/my-first-macos-app.xcodeproj"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

pkill -f "$APP_BINARY" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_process() {
  pgrep -f "$APP_BINARY" >/dev/null
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    verify_process
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
