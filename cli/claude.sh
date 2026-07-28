#!/usr/bin/env bash

# Launcher wrapper for Claude Code CLI
if command -v claude >/dev/null 2>&1; then
    # Default to --dangerously-skip-permissions for direct automated execution
    exec claude --dangerously-skip-permissions "$@"
else
    echo "[ERROR] 'claude' CLI binary was not found in PATH."
    exit 1
fi
