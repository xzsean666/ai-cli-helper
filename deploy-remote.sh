#!/usr/bin/env bash
set -e

ORIG_HOME="${AI_ORIGINAL_HOME:-$HOME}"
if [ -d "/home/sean" ] && [ ! -f "$ORIG_HOME/ssh/sean" ]; then
    ORIG_HOME="/home/sean"
fi

SSH_KEY="${SSH_KEY:-$ORIG_HOME/ssh/sean}"
# Handle leading ~ in SSH_KEY
SSH_KEY="${SSH_KEY/#\~/$ORIG_HOME}"

SSH_PORT="${SSH_PORT:-22}"
REMOTE_HOST="${1:-${REMOTE_HOST:-root@192.168.31.110}}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying AI CLI Helper to $REMOTE_HOST ==="

# Check SSH connectivity
echo "[INFO] Testing SSH connection to $REMOTE_HOST (Port: $SSH_PORT, Key: $SSH_KEY) ..."
if ! ssh -i "$SSH_KEY" -p "$SSH_PORT" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$REMOTE_HOST" "echo SSH_CONNECTED" >/dev/null 2>&1; then
    echo "[ERROR] Cannot connect to $REMOTE_HOST via SSH."
    echo "[INFO] Diagnosis:"
    echo "  - SSH Key: $SSH_KEY (exists: $([ -f "$SSH_KEY" ] && echo 'yes' || echo 'no'))"
    echo "  - Port: $SSH_PORT"
    echo "  - Host: $REMOTE_HOST"
    echo "  - Ping test: $(ping -c 1 -W 1 "${REMOTE_HOST#*@}" >/dev/null 2>&1 && echo 'reachable' || echo 'unreachable / offline')"
    exit 1
fi

echo "[✓] SSH connection established."

# Determine remote target directory
REMOTE_DIR="/root/git/ai-cli-helper"

echo "[INFO] Syncing repository files to $REMOTE_HOST:$REMOTE_DIR ..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE_HOST" "mkdir -p $REMOTE_DIR"

rsync -avz -e "ssh -i $SSH_KEY -p $SSH_PORT" \
    --exclude '.git' \
    --exclude 'secrets/' \
    "$SRC_DIR/" "$REMOTE_HOST:$REMOTE_DIR/"

echo "[INFO] Running initialization on remote host..."
ssh -i "$SSH_KEY" -p "$SSH_PORT" "$REMOTE_HOST" "
    cd $REMOTE_DIR
    chmod +x ai ai-init.sh cli/*.sh lib/*.sh
    ./ai-init.sh
    AI_CONFIG_DIR=/root/.config/ai ./ai init
    echo '=== Remote Deployment Verification ==='
    /root/.config/ai/bin/ai doctor || true
"

echo "[SUCCESS] Successfully deployed AI CLI Helper to $REMOTE_HOST!"
