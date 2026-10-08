#!/usr/bin/env bash

# Installation & setup script for AI CLI Helper
# Compatible with Linux (bash) and macOS (zsh / bash)
set -e

SOURCE="${BASH_SOURCE[0]:-$0}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# Ensure core scripts and executables have execution permissions
chmod +x "$SCRIPT_DIR/ai" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/env.sh" 2>/dev/null || true
[ -d "$SCRIPT_DIR/cli" ] && chmod +x "$SCRIPT_DIR/cli/"*.sh 2>/dev/null || true
[ -d "$SCRIPT_DIR/lib" ] && chmod +x "$SCRIPT_DIR/lib/"*.sh "$SCRIPT_DIR/lib/"*.py 2>/dev/null || true

echo "=== Installing / Updating AI CLI Helper ==="
"$SCRIPT_DIR/ai" init "$@"
