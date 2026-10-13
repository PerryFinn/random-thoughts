#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -x "$ROOT_DIR/.build/cargo/bin/cargo" ]]; then
  export RUSTUP_HOME="$ROOT_DIR/.build/rustup"
  export CARGO_HOME="$ROOT_DIR/.build/cargo"
  TOKENIZER_CARGO="$CARGO_HOME/bin/cargo"
else
  TOKENIZER_CARGO="$(command -v cargo)" || { echo 'Tokenizer build requires Rust 1.90.0; see docs/chat-completions-generation.md.' >&2; exit 1; }
fi
export MACOSX_DEPLOYMENT_TARGET=26.5
cd "$ROOT_DIR/Tokenizer"
exec "$TOKENIZER_CARGO" build --release --locked --target-dir "$ROOT_DIR/.build/tokenizer"
