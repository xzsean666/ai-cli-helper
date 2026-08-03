#!/usr/bin/env bash

# Quick installation & environment setup script for AI CLI Helper
# Compatible with Linux (bash) and macOS (zsh / bash)

AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai}"

# Add AI CLI Helper bin directory to PATH
if [ -d "$AI_CONFIG_DIR/bin" ]; then
    case ":$PATH:" in
        *:"$AI_CONFIG_DIR/bin":*) ;;
        *) export PATH="$AI_CONFIG_DIR/bin:$PATH" ;;
    esac
fi

# Determine if script is being sourced or executed directly
IS_SOURCED=0
if [ -n "$ZSH_VERSION" ]; then
    case "$ZSH_EVAL_CONTEXT" in
        *:file*) IS_SOURCED=1 ;;
    esac
elif [ -n "$BASH_VERSION" ]; then
    if [ "${BASH_SOURCE[0]}" != "$0" ] && [ -n "${BASH_SOURCE[0]}" ]; then
        IS_SOURCED=1
    fi
fi

# If executed directly (not sourced by shell), run setup
if [ "$IS_SOURCED" -eq 0 ]; then
    if [ -n "$ZSH_VERSION" ]; then
        SOURCE="${(%):-%x}"
    else
        SOURCE="${BASH_SOURCE[0]:-$0}"
    fi

    while [ -h "$SOURCE" ]; do
      DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
      SOURCE="$(readlink "$SOURCE")"
      [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

    chmod +x "$SCRIPT_DIR/ai" "$SCRIPT_DIR/ai-init.sh" "$SCRIPT_DIR/cli/"*.sh "$SCRIPT_DIR/lib/"*.sh 2>/dev/null || true

    echo "=== Initializing AI CLI Helper ==="
    "$SCRIPT_DIR/ai" init
fi
