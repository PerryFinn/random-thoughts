#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONFIGURATION=Debug
if [[ $# -gt 0 ]]; then
  if [[ $# -ne 2 || "$1" != --configuration ]]; then
    echo 'Usage: build.sh [--configuration Debug|Release]' >&2
    exit 2
  fi
  CONFIGURATION="$2"
fi
case "$CONFIGURATION" in
  Debug|Release) ;;
  *) echo 'Configuration must be Debug or Release.' >&2; exit 2 ;;
esac

exec xcodebuild \
  -project "$ROOT_DIR/random-thoughts.xcodeproj" \
  -scheme random-thoughts \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$ROOT_DIR/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
