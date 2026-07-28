#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if command -v codex >/dev/null 2>&1; then
    # Inject --config wire_mock / base URL override if OPENAI_BASE_URL is set
    if [ -n "$OPENAI_BASE_URL" ]; then
        exec codex -c "openai_base_url=\"$OPENAI_BASE_URL\"" "$@"
    else
        exec codex "$@"
    fi
elif command -v openai >/dev/null 2>&1; then
    exec openai "$@"
else
    echo "[ERROR] Neither 'codex' nor 'openai' CLI binary was found in PATH."
    exit 1
fi
