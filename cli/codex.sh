#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if command -v codex >/dev/null 2>&1; then
    OPTS=()
    if [ -n "$OPENAI_BASE_URL" ]; then
        OPTS+=(-c "openai_base_url=\"$OPENAI_BASE_URL\"")
    fi
    if [ -n "$OPENAI_MODEL" ]; then
        OPTS+=(-c "model=\"$OPENAI_MODEL\"")
    fi
    exec codex "${OPTS[@]}" "$@"
elif command -v openai >/dev/null 2>&1; then
    exec openai "$@"
else
    echo "[ERROR] Neither 'codex' nor 'openai' CLI binary was found in PATH."
    exit 1
fi
