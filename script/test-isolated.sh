#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -x /usr/bin/sandbox-exec ]]; then
  echo 'Isolation requires /usr/bin/sandbox-exec; refusing to run tests without it.' >&2
  exit 1
fi

SWIFT_BIN="$(xcrun --find swift)"
TEST_RUNNER="$(dirname "$SWIFT_BIN")/../libexec/swift/pm/swiftpm-testing-helper"
TEST_RUNNER="$(cd "$(dirname "$TEST_RUNNER")" && pwd -P)/swiftpm-testing-helper"
[[ -x "$TEST_RUNNER" ]]
SDK_PLATFORM="$(xcrun --sdk macosx --show-sdk-platform-path)"
BUILD_OPTIONS=(
  --package-path "$ROOT_DIR"
  --scratch-path "$ROOT_DIR/.build/isolated"
  --cache-path "$ROOT_DIR/.build/swiftpm-cache"
  --config-path "$ROOT_DIR/.build/swiftpm-config"
  --security-path "$ROOT_DIR/.build/swiftpm-security"
  --disable-keychain --disable-netrc
  -Xlinker -rpath -Xlinker "$SDK_PLATFORM/Developer/Library/Frameworks"
  -Xlinker -rpath -Xlinker "$SDK_PLATFORM/Developer/usr/lib"
)
"$SWIFT_BIN" build "${BUILD_OPTIONS[@]}" --build-tests
BIN_DIR="$("$SWIFT_BIN" build "${BUILD_OPTIONS[@]}" --show-bin-path)"
TEST_BINARY="$BIN_DIR/RandomThoughtsIsolationPackageTests.xctest/Contents/MacOS/RandomThoughtsIsolationPackageTests"
[[ -x "$TEST_BINARY" ]]

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp/}random-thoughts-tests.XXXXXX")"
TEST_ROOT="$(cd "$TEST_ROOT" && pwd -P)"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/tmp"

export RANDOM_THOUGHTS_TEST_ROOT="$TEST_ROOT"
export RANDOM_THOUGHTS_PROTECTED_HOME="$HOME"
export CFFIXED_USER_HOME="$TEST_ROOT/home"
export TMPDIR="$TEST_ROOT/tmp/"

/usr/bin/sandbox-exec \
  -D "USER_HOME=$RANDOM_THOUGHTS_PROTECTED_HOME" \
  -D "WORKSPACE=$ROOT_DIR" \
  -D "TEST_ROOT=$TEST_ROOT" \
  -D "TEST_RUNNER=$TEST_RUNNER" \
  -f "$ROOT_DIR/script/isolated-tests.sb" \
  "$TEST_RUNNER" --test-bundle-path "$TEST_BINARY" --testing-library swift-testing "$@"
