#!/usr/bin/env bash

# Launcher wrapper for Aider CLI
if command -v aider >/dev/null 2>&1; then
    exec aider "$@"
else
    echo "[ERROR] 'aider' CLI binary was not found in PATH."
    exit 1
fi
