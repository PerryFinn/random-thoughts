#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:-scenarios}"
case "$MODE" in probes|scenarios|invalid-response|s07-plans|s08-minimum|s08-blockers) ;; *) echo 'Usage: test-live-openai.sh [probes|scenarios|invalid-response|s07-plans|s08-minimum|s08-blockers]' >&2; exit 2 ;; esac

# Build and check the offline material before loading any credential.
env -u RANDOM_THOUGHTS_LIVE_OPENAI -u OPENAI_API_KEY \
  "$ROOT_DIR/script/test-isolated.sh" --filter 'ReportSemanticFixtureTests|ReportAcceptanceScenarioTests|LiveOpenAISemanticTests'
SWIFT_BIN="$(xcrun --find swift)"
TEST_RUNNER="$(dirname "$SWIFT_BIN")/../libexec/swift/pm/swiftpm-testing-helper"
TEST_RUNNER="$(cd "$(dirname "$TEST_RUNNER")" && pwd -P)/swiftpm-testing-helper"
BIN_DIR="$("$SWIFT_BIN" build --build-system swiftbuild --configuration debug --package-path "$ROOT_DIR" --scratch-path "$ROOT_DIR/.build/isolated" --show-bin-path)"
TEST_BINARY="$BIN_DIR/IsolatedTests.xctest/Contents/MacOS/IsolatedTests"
[[ -x "$TEST_RUNNER" && -x "$TEST_BINARY" && -x /usr/bin/sandbox-exec ]]
umask 077
mkdir -p "$ROOT_DIR/.build/live-openai"
TEST_ROOT="$(mktemp -d "$ROOT_DIR/.build/live-openai/run.XXXXXX")"
mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/tmp"

# Read one literal assignment, never source shell code or place the Key in argv.
/usr/bin/python3 - "$ROOT_DIR" "$TEST_ROOT" "$TEST_RUNNER" "$TEST_BINARY" "$MODE" <<'PY'
import os, pathlib, stat, sys
root, output, runner, binary, mode = sys.argv[1:]
env_file = pathlib.Path(root) / '.env.local'
if env_file.is_symlink() or not env_file.is_file():
    raise SystemExit('Expected a regular .env.local file.')
if stat.S_IMODE(env_file.stat().st_mode) != 0o600:
    raise SystemExit('.env.local must have mode 0600.')
lines = env_file.read_text().splitlines()
values = [line[len('OPENAI_API_KEY='):] for line in lines if line.startswith('OPENAI_API_KEY=')]
if len(values) != 1 or not values[0] or any(c.isspace() for c in values[0]):
    raise SystemExit('Expected one literal OPENAI_API_KEY assignment.')
env = os.environ.copy()
env.update(OPENAI_API_KEY=values[0], RANDOM_THOUGHTS_LIVE_OPENAI='1',
           RANDOM_THOUGHTS_LIVE_MODE=mode, RANDOM_THOUGHTS_LIVE_OUTPUT=output,
           CFFIXED_USER_HOME=output + '/home', TMPDIR=output + '/tmp/')
print('Live OpenAI mode: ' + mode + '; private results: ' + output, flush=True)
os.execve('/usr/bin/sandbox-exec', [
    '/usr/bin/sandbox-exec', '-D', 'USER_HOME=' + os.path.expanduser('~'),
    '-D', 'WORKSPACE=' + root, '-D', 'ENV_FILE=' + str(env_file),
    '-D', 'TEST_ROOT=' + output, '-D', 'TEST_RUNNER=' + runner,
    '-f', root + '/script/live-openai-tests.sb', runner,
    '--test-bundle-path', binary, '--testing-library', 'swift-testing',
    '--filter', 'LiveOpenAISemanticTests'], env)
PY
