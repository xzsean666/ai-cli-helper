#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if command -v codex >/dev/null 2>&1; then
    OPTS=()
    
    # Add -c model_provider if MODEL_PROVIDER is set
    if [ -n "$MODEL_PROVIDER" ]; then
        OPTS+=(-c "model_provider=\"$MODEL_PROVIDER\"")
    fi
    
    # Add -c model if OPENAI_MODEL is set
    if [ -n "$OPENAI_MODEL" ]; then
        OPTS+=(-c "model=\"$OPENAI_MODEL\"")
    fi

    # Add -c model_reasoning_effort if MODEL_REASONING_EFFORT is set
    if [ -n "$MODEL_REASONING_EFFORT" ]; then
        OPTS+=(-c "model_reasoning_effort=\"$MODEL_REASONING_EFFORT\"")
    fi

    # Add -c openai_base_url if OPENAI_BASE_URL is set
    if [ -n "$OPENAI_BASE_URL" ]; then
        OPTS+=(-c "openai_base_url=\"$OPENAI_BASE_URL\"")
    fi

    # Default to --yolo (or --dangerously-bypass-approvals-and-sandbox) for non-interactive / automated ease
    exec codex --yolo "${OPTS[@]}" "$@"
elif command -v openai >/dev/null 2>&1; then
    exec openai "$@"
else
    echo "[ERROR] Neither 'codex' nor 'openai' CLI binary was found in PATH."
    exit 1
fi
