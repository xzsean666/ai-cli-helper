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
ACTIVE_ALIAS_FILE="$APP_DATA_DIR/.active_token_alias"

mkdir -p "$AUTH_STORE_DIR/run"
mkdir -p "$APP_DATA_DIR"
mkdir -p "$HOME/.gemini"

# Helper function to extract email from stored OAuth token
get_stored_email() {
    if [ -s "$STORED_EMAIL_FILE" ]; then
        cat "$STORED_EMAIL_FILE" 2>/dev/null
        return 0
    fi
    if [ -s "$STORED_TOKEN" ]; then
        python3 -c "
import json, sys, urllib.request
try:
    with open('$STORED_TOKEN') as f: data = json.load(f)
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
        
        email=$(get_stored_email)
        if [ -n "$email" ]; then
            [ ! -s "$STORED_EMAIL_FILE" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
            echo "Google Account:  $email"
            exit 0
        elif [ -s "$STORED_TOKEN" ]; then
            echo "Google Account:  (authenticated)"
            exit 0
        fi
        echo "Google Account:  (not logged in. Run 'ai $TARGET_ALIAS' or 'ai $TARGET_ALIAS login' to authenticate)"
        exit 0
        ;;
    logout)
        rm -f "$STORED_TOKEN" "$STORED_EMAIL_FILE"
        rm -f "$AUTH_STORE_DIR/oauth_creds.json" "$AUTH_STORE_DIR/google_accounts.json"
        rm -f "$RUNTIME_TOKEN" "$ACTIVE_ALIAS_FILE"
        rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        echo "[SUCCESS] Logged out from alias '$TARGET_ALIAS'. Stored OAuth credentials removed."
        exit 0
        ;;
    login|auth)
        echo "[INFO] Initiating Google OAuth login for alias '$TARGET_ALIAS'..."
        # Clear existing creds so agy prompts for new authentication
        rm -f "$STORED_TOKEN" "$STORED_EMAIL_FILE"
        rm -f "$AUTH_STORE_DIR/oauth_creds.json" "$AUTH_STORE_DIR/google_accounts.json"
        rm -f "$RUNTIME_TOKEN" "$ACTIVE_ALIAS_FILE"
        rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        shift
        ;;
esac

# Pre-execution: inject saved credentials for THIS alias into shared HOME
if [ -s "$STORED_TOKEN" ]; then
    cp -f "$STORED_TOKEN" "$RUNTIME_TOKEN"
    chmod 600 "$RUNTIME_TOKEN" 2>/dev/null || true
    echo "$TARGET_ALIAS" > "$ACTIVE_ALIAS_FILE"
    if [ -f "$AUTH_STORE_DIR/oauth_creds.json" ]; then
        cp -f "$AUTH_STORE_DIR/oauth_creds.json" "$HOME/.gemini/oauth_creds.json"
    fi
    if [ -f "$AUTH_STORE_DIR/google_accounts.json" ]; then
        cp -f "$AUTH_STORE_DIR/google_accounts.json" "$HOME/.gemini/google_accounts.json"
    fi
else
    # For an alias without saved credentials, ensure $HOME/.gemini
    # does not contain credentials belonging to another alias in a shared HOME profile.
    rm -f "$RUNTIME_TOKEN"
    rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
    echo "$TARGET_ALIAS" > "$ACTIVE_ALIAS_FILE"
fi

# Trap to sync any updated or newly obtained credentials back to the alias auth store
sync_auth_back() {
    if [ -n "$BG_SYNC_PID" ]; then
        kill "$BG_SYNC_PID" 2>/dev/null || true
    fi

    if [ -f "$ACTIVE_ALIAS_FILE" ]; then
        local current_alias
        current_alias="$(cat "$ACTIVE_ALIAS_FILE" 2>/dev/null)"
        if [ "$current_alias" = "$TARGET_ALIAS" ]; then
            if [ -s "$RUNTIME_TOKEN" ]; then
                cp -f "$RUNTIME_TOKEN" "$STORED_TOKEN"
                chmod 600 "$STORED_TOKEN" 2>/dev/null || true
                if [ ! -s "$STORED_EMAIL_FILE" ]; then
                    email=$(get_stored_email)
                    [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
                fi
            fi
            if [ -f "$HOME/.gemini/oauth_creds.json" ]; then
                cp -f "$HOME/.gemini/oauth_creds.json" "$AUTH_STORE_DIR/oauth_creds.json" 2>/dev/null || true
            fi
            if [ -f "$HOME/.gemini/google_accounts.json" ]; then
                cp -f "$HOME/.gemini/google_accounts.json" "$AUTH_STORE_DIR/google_accounts.json" 2>/dev/null || true
            fi
            # Always clean the runtime token from shared profile directory upon exit
            rm -f "$RUNTIME_TOKEN"
            rm -f "$ACTIVE_ALIAS_FILE"
            rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        fi
    fi
}
trap sync_auth_back EXIT INT TERM HUP

# Background watcher to sync token as soon as user completes OAuth in browser
(
    while kill -0 $$ 2>/dev/null; do
        sleep 3
        if [ -s "$RUNTIME_TOKEN" ]; then
            current_alias="$(cat "$ACTIVE_ALIAS_FILE" 2>/dev/null)"
            if [ "$current_alias" = "$TARGET_ALIAS" ]; then
                cp -f "$RUNTIME_TOKEN" "$STORED_TOKEN" 2>/dev/null || true
                chmod 600 "$STORED_TOKEN" 2>/dev/null || true
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

# Launch agy
agy "$@"
EXIT_CODE=$?
sync_auth_back
exit $EXIT_CODE
