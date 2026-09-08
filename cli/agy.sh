#!/usr/bin/env bash

# Launcher wrapper for Google Antigravity CLI (agy)
if ! command -v agy >/dev/null 2>&1; then
    echo "[ERROR] 'agy' CLI binary was not found in PATH."
    exit 1
fi

TARGET_ALIAS="${AI_ACTIVE_ALIAS:-${AI_ACTIVE_PROVIDER:-agy}}"
ORIG_HOME="${AI_ORIGINAL_HOME:-$HOME}"
AUTH_STORE_DIR="$ORIG_HOME/.local/share/ai/agy/auth/$TARGET_ALIAS"

mkdir -p "$AUTH_STORE_DIR"
mkdir -p "$HOME/.gemini"

# Helper subcommands for OAuth credential management
case "$1" in
    whoami|status)
        echo "Profile / Alias: $TARGET_ALIAS"
        echo "HOME Profile:    ${AI_HOME_PROFILE:-$TARGET_ALIAS}"
        echo "HOME Directory:  $HOME"
        echo "Auth Storage:    $AUTH_STORE_DIR"
        account_file="$AUTH_STORE_DIR/google_accounts.json"
        if [ -f "$AUTH_STORE_DIR/oauth_creds.json" ] && [ -f "$account_file" ]; then
            active_email=$(grep -o '"active": *"[^"]*"' "$account_file" 2>/dev/null | cut -d'"' -f4)
            if [ -n "$active_email" ]; then
                echo "Google Account:  $active_email"
                exit 0
            fi
        fi
        echo "Google Account:  (not logged in. Run 'ai $TARGET_ALIAS' or 'ai $TARGET_ALIAS login' to authenticate)"
        exit 0
        ;;
    logout)
        rm -f "$AUTH_STORE_DIR/oauth_creds.json" "$AUTH_STORE_DIR/google_accounts.json"
        rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        echo "[SUCCESS] Logged out from alias '$TARGET_ALIAS'. Stored OAuth credentials removed."
        exit 0
        ;;
    login|auth)
        echo "[INFO] Initiating Google OAuth login for alias '$TARGET_ALIAS'..."
        # Clear existing creds so agy prompts for new authentication
        rm -f "$AUTH_STORE_DIR/oauth_creds.json" "$AUTH_STORE_DIR/google_accounts.json"
        rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
        shift
        ;;
    import|import-default)
        if [ -f "$ORIG_HOME/.gemini/oauth_creds.json" ]; then
            cp -f "$ORIG_HOME/.gemini/oauth_creds.json" "$AUTH_STORE_DIR/oauth_creds.json"
            [ -f "$ORIG_HOME/.gemini/google_accounts.json" ] && cp -f "$ORIG_HOME/.gemini/google_accounts.json" "$AUTH_STORE_DIR/google_accounts.json"
            echo "[SUCCESS] Imported default ~/.gemini credentials into alias '$TARGET_ALIAS'."
            exit 0
        else
            echo "[ERROR] No credentials found in $ORIG_HOME/.gemini to import."
            exit 1
        fi
        ;;
esac

# Pre-execution: inject saved credentials for THIS alias
if [ -f "$AUTH_STORE_DIR/oauth_creds.json" ]; then
    cp -f "$AUTH_STORE_DIR/oauth_creds.json" "$HOME/.gemini/oauth_creds.json"
    if [ -f "$AUTH_STORE_DIR/google_accounts.json" ]; then
        cp -f "$AUTH_STORE_DIR/google_accounts.json" "$HOME/.gemini/google_accounts.json"
    else
        rm -f "$HOME/.gemini/google_accounts.json"
    fi
else
    # For a fresh alias without saved credentials, ensure $HOME/.gemini
    # does not contain credentials belonging to another alias in a shared HOME profile.
    rm -f "$HOME/.gemini/oauth_creds.json" "$HOME/.gemini/google_accounts.json"
fi

# Trap to sync any updated or newly obtained credentials back to the alias auth store
sync_auth_back() {
    if [ -f "$HOME/.gemini/oauth_creds.json" ]; then
        mkdir -p "$AUTH_STORE_DIR"
        cp -f "$HOME/.gemini/oauth_creds.json" "$AUTH_STORE_DIR/oauth_creds.json" 2>/dev/null || true
    fi
    if [ -f "$HOME/.gemini/google_accounts.json" ]; then
        mkdir -p "$AUTH_STORE_DIR"
        cp -f "$HOME/.gemini/google_accounts.json" "$AUTH_STORE_DIR/google_accounts.json" 2>/dev/null || true
    fi
}
trap sync_auth_back EXIT INT TERM HUP

# Unset any nested Antigravity session environment variables so agy runs cleanly
unset ANTIGRAVITY_LS_ADDRESS ANTIGRAVITY_AGENT ANTIGRAVITY_CONVERSATION_ID ANTIGRAVITY_TRAJECTORY_ID ANTIGRAVITY_SOURCE_METADATA

# Launch agy
agy "$@"
EXIT_CODE=$?
sync_auth_back
exit $EXIT_CODE
