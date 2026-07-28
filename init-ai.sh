#!/usr/bin/env bash

# Shell initialization helper script
export AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai}"

# Add bin path to PATH if not present
if [[ ":$PATH:" != *":$AI_CONFIG_DIR/bin:"* ]]; then
    export PATH="$AI_CONFIG_DIR/bin:$PATH"
fi
