#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if command -v codex >/dev/null 2>&1; then
    # Pass --oss to force standard OpenAI-compatible REST API instead of Codex proprietary WebSocket/responses endpoint
    if [ -n "$OPENAI_BASE_URL" ]; then
        exec codex --oss --local-provider custom -c "providers.custom.base_url=\"$OPENAI_BASE_URL\"" -c "providers.custom.api_key=\"$OPENAI_API_KEY\"" "$@"
    else
        exec codex "$@"
    fi
elif command -v openai >/dev/null 2>&1; then
    exec openai "$@"
else
    echo "[ERROR] Neither 'codex' nor 'openai' CLI binary was found in PATH."
    exit 1
fi
