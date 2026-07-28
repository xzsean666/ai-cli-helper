#!/usr/bin/env bash

# Launcher wrapper for Gemini CLI
if command -v gemini >/dev/null 2>&1; then
    exec gemini "$@"
else
    echo "[ERROR] 'gemini' CLI binary was not found in PATH."
    exit 1
fi
