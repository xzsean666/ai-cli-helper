#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if command -v codex >/dev/null 2>&1; then
    OPTS=()
    
    # Add -c openai_base_url if OPENAI_BASE_URL is set
    if [ -n "$OPENAI_BASE_URL" ]; then
        OPTS+=(-c "openai_base_url=\"$OPENAI_BASE_URL\"")
    fi

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
