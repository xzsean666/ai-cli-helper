#!/usr/bin/env bash

# Launcher wrapper for OpenAI CLI
if command -v openai >/dev/null 2>&1; then
    exec openai "$@"
else
    echo "[ERROR] 'openai' CLI binary was not found in PATH."
    exit 1
fi
