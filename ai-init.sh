#!/usr/bin/env bash

# Quick installation / initialization script for AI CLI Helper

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

chmod +x "$SCRIPT_DIR/ai" "$SCRIPT_DIR/cli/"*.sh "$SCRIPT_DIR/lib/"*.sh 2>/dev/null || true

echo "=== Initializing AI CLI Helper ==="
"$SCRIPT_DIR/ai" init
