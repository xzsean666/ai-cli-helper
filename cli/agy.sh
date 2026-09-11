#!/usr/bin/env bash

# Launcher wrapper for Google Antigravity CLI (agy)
if ! command -v agy >/dev/null 2>&1; then
    echo "[ERROR] 'agy' CLI binary was not found in PATH."
    exit 1
fi

TARGET_ALIAS="${AI_ACTIVE_ALIAS:-${AI_ACTIVE_PROVIDER:-agy}}"
ORIG_HOME="${AI_ORIGINAL_HOME:-$HOME}"
AUTH_STORE_DIR="$ORIG_HOME/.local/share/ai/agy/auth/$TARGET_ALIAS"

APP_DATA_DIR="$HOME/.gemini/antigravity-cli"
RUNTIME_TOKEN="$APP_DATA_DIR/antigravity-oauth-token"
STORED_TOKEN="$AUTH_STORE_DIR/antigravity-oauth-token"
STORED_EMAIL_FILE="$AUTH_STORE_DIR/email.txt"

mkdir -p "$AUTH_STORE_DIR/run"
mkdir -p "$APP_DATA_DIR"
mkdir -p "$HOME/.gemini"

# Helper function to extract email from an OAuth token file
get_token_email() {
    local token_file="$1"
    if [ -s "$token_file" ]; then
        python3 -c "
import json, sys, urllib.request
try:
    with open('$token_file') as f: data = json.load(f)
    token = data.get('token', {})
    acc = token.get('access_token', '') if isinstance(token, dict) else ''
    if acc:
        req = urllib.request.Request(f'https://oauth2.googleapis.com/tokeninfo?access_token={acc}')
        with urllib.request.urlopen(req, timeout=2) as resp:
            em = json.loads(resp.read().decode()).get('email', '')
            if em:
                print(em)
                sys.exit(0)
except Exception:
    pass
sys.exit(1)
" 2>/dev/null
    fi
}

# Helper subcommands for OAuth credential management
case "$1" in
    whoami|status)
        echo "Profile / Alias: $TARGET_ALIAS"
        echo "HOME Profile:    ${AI_HOME_PROFILE:-$TARGET_ALIAS}"
        echo "HOME Directory:  $HOME"
        echo "Auth Storage:    $AUTH_STORE_DIR"
        
        token_to_check=""
        if [ -s "$RUNTIME_TOKEN" ]; then
            token_to_check="$RUNTIME_TOKEN"
        elif [ -s "$STORED_TOKEN" ]; then
            token_to_check="$STORED_TOKEN"
        fi

        email=""
        if [ -n "$token_to_check" ]; then
            email=$(get_token_email "$token_to_check")
            if [ -n "$email" ]; then
                echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
            elif [ -s "$STORED_EMAIL_FILE" ]; then
                email=$(cat "$STORED_EMAIL_FILE" 2>/dev/null)
            fi
            if [ -n "$email" ]; then
                echo "Google Account:  $email"
            else
                echo "Google Account:  (authenticated)"
            fi
            exit 0
        fi

        echo "Google Account:  (not logged in. Run 'ai $TARGET_ALIAS' or 'ai $TARGET_ALIAS login' to authenticate)"
        exit 0
        ;;
    logout)
        rm -f "$STORED_TOKEN" "$STORED_EMAIL_FILE"
        rm -f "$AUTH_STORE_DIR/oauth_creds.json" "$AUTH_STORE_DIR/google_accounts.json"
        rm -f "$RUNTIME_TOKEN"
        rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        echo "[SUCCESS] Logged out from alias '$TARGET_ALIAS'. Stored OAuth credentials removed."
        exit 0
        ;;
    login|auth)
        echo "[INFO] Initiating Google OAuth login for alias '$TARGET_ALIAS'..."
        # Clear existing creds so agy prompts for new authentication
        rm -f "$STORED_TOKEN" "$STORED_EMAIL_FILE"
        rm -f "$AUTH_STORE_DIR/oauth_creds.json" "$AUTH_STORE_DIR/google_accounts.json"
        rm -f "$RUNTIME_TOKEN"
        rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        shift
        ;;
esac

# Pre-execution: ensure profile runtime directory and auth store are in sync
if [ -s "$STORED_TOKEN" ] && [ ! -s "$RUNTIME_TOKEN" ]; then
    cp -f "$STORED_TOKEN" "$RUNTIME_TOKEN"
    chmod 600 "$RUNTIME_TOKEN" 2>/dev/null || true
elif [ -s "$RUNTIME_TOKEN" ] && [ ! -s "$STORED_TOKEN" ]; then
    cp -f "$RUNTIME_TOKEN" "$STORED_TOKEN"
    chmod 600 "$STORED_TOKEN" 2>/dev/null || true
fi

if [ -f "$AUTH_STORE_DIR/oauth_creds.json" ] && [ ! -f "$HOME/.gemini/oauth_creds.json" ]; then
    cp -f "$AUTH_STORE_DIR/oauth_creds.json" "$HOME/.gemini/oauth_creds.json" 2>/dev/null || true
fi
if [ -f "$AUTH_STORE_DIR/google_accounts.json" ] && [ ! -f "$HOME/.gemini/google_accounts.json" ]; then
    cp -f "$AUTH_STORE_DIR/google_accounts.json" "$HOME/.gemini/google_accounts.json" 2>/dev/null || true
fi

# Trap to sync any updated or newly obtained credentials back to the alias auth store
sync_auth_back() {
    if [ -n "$BG_SYNC_PID" ]; then
        kill "$BG_SYNC_PID" 2>/dev/null || true
    fi

    if [ -s "$RUNTIME_TOKEN" ]; then
        cp -f "$RUNTIME_TOKEN" "$STORED_TOKEN" 2>/dev/null || true
        chmod 600 "$STORED_TOKEN" 2>/dev/null || true
        local email
        email=$(get_token_email "$RUNTIME_TOKEN")
        [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
    fi
    if [ -f "$HOME/.gemini/oauth_creds.json" ]; then
        cp -f "$HOME/.gemini/oauth_creds.json" "$AUTH_STORE_DIR/oauth_creds.json" 2>/dev/null || true
    fi
    if [ -f "$HOME/.gemini/google_accounts.json" ]; then
        cp -f "$HOME/.gemini/google_accounts.json" "$AUTH_STORE_DIR/google_accounts.json" 2>/dev/null || true
    fi
    # DO NOT delete $RUNTIME_TOKEN upon exit. HOME is strictly isolated per alias!
}
trap sync_auth_back EXIT INT TERM HUP

# Background watcher to sync token as soon as user completes OAuth in browser or token refreshes
(
    while kill -0 $$ 2>/dev/null; do
        sleep 3
        if [ -s "$RUNTIME_TOKEN" ]; then
            if [ ! -f "$STORED_TOKEN" ] || [ "$RUNTIME_TOKEN" -nt "$STORED_TOKEN" ]; then
                cp -f "$RUNTIME_TOKEN" "$STORED_TOKEN" 2>/dev/null || true
                chmod 600 "$STORED_TOKEN" 2>/dev/null || true
                email=$(get_token_email "$RUNTIME_TOKEN")
                [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
            fi
        fi
    done
) >/dev/null 2>&1 &
BG_SYNC_PID=$!

# 关键：完全隔离系统级 DBus / Keyring，强制 agy 使用当前 profile/alias 的专属文件存储，
# 避免 Linux 桌面环境自动读取或覆盖全局唯一的 GNOME Keyring 导致串号。
export DBUS_SESSION_BUS_ADDRESS="disabled"
export XDG_RUNTIME_DIR="$AUTH_STORE_DIR/run"

# Unset any nested Antigravity session environment variables so agy runs cleanly
unset ANTIGRAVITY_LS_ADDRESS ANTIGRAVITY_AGENT ANTIGRAVITY_CONVERSATION_ID ANTIGRAVITY_TRAJECTORY_ID ANTIGRAVITY_SOURCE_METADATA

# Default to --dangerously-skip-permissions for automated ease unless already specified
has_skip_perms=false
for arg in "$@"; do
    if [ "$arg" = "--dangerously-skip-permissions" ]; then
        has_skip_perms=true
        break
    fi
done

AGY_ARGS=()
if [ "${AGY_SKIP_PERMISSIONS:-true}" = "true" ] && [ "$has_skip_perms" = false ]; then
    AGY_ARGS+=(--dangerously-skip-permissions)
fi
AGY_ARGS+=("$@")

# Launch agy
agy "${AGY_ARGS[@]}"
EXIT_CODE=$?
sync_auth_back
exit $EXIT_CODE
