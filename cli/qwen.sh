#!/usr/bin/env bash

# Launcher wrapper for Qwen CLI
if command -v qwen >/dev/null 2>&1; then
    exec qwen "$@"
else
    echo "[ERROR] 'qwen' CLI binary was not found in PATH."
    exit 1
fi
