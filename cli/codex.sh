#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if command -v codex >/dev/null 2>&1; then
    ensure_https_base_url OPENAI_BASE_URL "https://api.openai.com/v1"

    # Codex reads API keys from CODEX_HOME/.codex/auth.json. Keep this file
    # aligned with the selected provider while allowing providers to share HOME.
    if [ -n "$OPENAI_API_KEY" ]; then
        export CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
        codex_home="$CODEX_HOME"
        mkdir -p "$codex_home"
        umask 077
        printf '{"auth_mode":"apikey","OPENAI_API_KEY":"%s"}\n' "$OPENAI_API_KEY" > "$codex_home/auth.json"
    fi

    OPTS=()
    
    # Use the HTTPS/SSE transport for compatible providers instead of WebSockets.
    OPTS+=(
        -c 'model_provider="ai_helper"'
        -c 'model_providers.ai_helper.name="AI CLI Helper"'
        -c "model_providers.ai_helper.base_url=\"$OPENAI_BASE_URL\""
        -c 'model_providers.ai_helper.env_key="OPENAI_API_KEY"'
        -c 'model_providers.ai_helper.wire_api="responses"'
        -c 'model_providers.ai_helper.supports_websockets=false'
    )

    # Sync OPENAI_API_KEY to auth.json if set
    if [ -n "$OPENAI_API_KEY" ]; then
        mkdir -p "$HOME/.codex"
        cat << EOF > "$HOME/.codex/auth.json"
{
  "auth_mode": "apikey",
  "OPENAI_API_KEY": "$OPENAI_API_KEY"
}
EOF
    fi

    # Add -c model if OPENAI_MODEL is set
    if [ -n "$OPENAI_MODEL" ]; then
        OPTS+=(-c "model=\"$OPENAI_MODEL\"")
    fi

    # Default to --yolo for non-interactive / automated ease
    exec codex --yolo "${OPTS[@]}" "$@"
elif command -v openai >/dev/null 2>&1; then
    exec openai "$@"
else
    echo "[ERROR] Neither 'codex' nor 'openai' CLI binary was found in PATH."
    exit 1
fi
