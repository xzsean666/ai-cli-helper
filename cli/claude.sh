#!/usr/bin/env bash

# Launcher wrapper for Claude Code CLI
if command -v claude >/dev/null 2>&1; then
    ensure_https_base_url ANTHROPIC_BASE_URL "https://api.anthropic.com"

    # Keep browser integration off so the launcher does not start its WebSocket bridge.
    exec claude --dangerously-skip-permissions --no-chrome "$@"
else
    echo "[ERROR] 'claude' CLI binary was not found in PATH."
    exit 1
fi
