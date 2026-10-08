#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

exec xcodebuild \
  -project "$ROOT_DIR/random-thoughts.xcodeproj" \
  -scheme random-thoughts \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$ROOT_DIR/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build
