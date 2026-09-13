#!/usr/bin/env bash

# Launcher wrapper for Claude Code CLI
if ! command -v claude >/dev/null 2>&1; then
    echo "[ERROR] 'claude' CLI binary was not found in PATH."
    exit 1
fi

TARGET_ALIAS="${AI_ACTIVE_ALIAS:-${AI_ACTIVE_PROVIDER:-claude}}"
ORIG_HOME="${AI_ORIGINAL_HOME:-$HOME}"
AUTH_STORE_DIR="$ORIG_HOME/.local/share/ai/claude/auth/$TARGET_ALIAS"

CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
export CLAUDE_CONFIG_DIR

STORED_CREDS="$AUTH_STORE_DIR/.credentials.json"
RUNTIME_CREDS="$CLAUDE_CONFIG_DIR/.credentials.json"
STORED_CONFIG="$AUTH_STORE_DIR/.claude.json"
RUNTIME_CONFIG="$CLAUDE_CONFIG_DIR/.claude.json"
STORED_EMAIL_FILE="$AUTH_STORE_DIR/email.txt"

mkdir -p "$AUTH_STORE_DIR/run"
mkdir -p "$CLAUDE_CONFIG_DIR"

# Helper function to extract email from Claude credential / configuration files
get_claude_email() {
    local creds_file="$1"
    local config_file="$2"
    python3 -c "
import json, sys

for fpath in ('$creds_file', '$config_file'):
    if not fpath: continue
    try:
        with open(fpath) as f:
            d = json.load(f)
        for k in ('account_email', 'email', 'accountEmail', 'emailAddress'):
            if d.get(k):
                print(d[k])
                sys.exit(0)
        for sub in ('account', 'profile', 'oauth', 'user'):
            if isinstance(d.get(sub), dict):
                for k in ('account_email', 'email', 'accountEmail', 'emailAddress'):
                    if d[sub].get(k):
                        print(d[sub][k])
                        sys.exit(0)
    except Exception:
        pass
sys.exit(1)
" 2>/dev/null
}

# Helper function to query claude auth status
get_claude_auth_info() {
    CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude auth status 2>/dev/null
}

# Helper function to determine authentication mode
detect_claude_auth_mode() {
    local explicit_mode="${AI_AUTH_MODE:-auto}"
    local explicit_lower
    explicit_lower=$(echo "$explicit_mode" | tr '[:upper:]' '[:lower:]')

    case "$explicit_lower" in
        "oauth"|"claudeai"|"subscription")
            echo "oauth"
            return 0
            ;;
        "api-key"|"apikey"|"api_key"|"api")
            echo "apikey"
            return 0
            ;;
    esac

    # In auto mode:
    # 1. If ANTHROPIC_API_KEY is explicitly set, prioritize API key
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        echo "apikey"
        return 0
    fi

    # 2. Check if credentials file has OAuth token
    for check_file in "$RUNTIME_CREDS" "$STORED_CREDS"; do
        if [ -s "$check_file" ]; then
            echo "oauth"
            return 0
        fi
    done

    # 3. If ANTHROPIC_BASE_URL is set to a custom gateway
    if [ -n "$ANTHROPIC_BASE_URL" ] && [ "$ANTHROPIC_BASE_URL" != "https://api.anthropic.com" ]; then
        echo "apikey"
        return 0
    fi

    echo "oauth"
}

CURRENT_AUTH_MODE=$(detect_claude_auth_mode)

# Helper subcommands for Claude credential & profile management
case "$1" in
    whoami|status)
        raw_prof="${AI_HOME_PROFILE:-shared-team}"
        prof_lower=$(echo "$raw_prof" | tr '[:upper:]' '[:lower:]')
        share_status=""
        case "$prof_lower" in
            "isolated"|"isolate"|"private"|"standalone")
                share_status="Isolated (private to $TARGET_ALIAS)"
                ;;
            "shared"|"share"|"shared-team"|"shared-data"|"common"|"team")
                if [ "$AI_SHARE_DATA" = "false" ]; then
                    share_status="Isolated (private to $TARGET_ALIAS)"
                else
                    share_status="Shared (global: shared-data)"
                fi
                ;;
            *)
                if [ "$prof_lower" = "$TARGET_ALIAS" ]; then
                    share_status="Isolated (private to $TARGET_ALIAS)"
                else
                    share_status="Shared (group pool: $raw_prof)"
                fi
                ;;
        esac

        echo "Profile / Alias:   $TARGET_ALIAS"
        echo "HOME Profile:      $raw_prof"
        echo "Data Sharing:      $share_status"
        echo "HOME Directory:    $HOME"
        echo "CLAUDE_CONFIG_DIR: $CLAUDE_CONFIG_DIR"
        echo "Auth Storage:      $AUTH_STORE_DIR"
        echo "Auth Mode:         $CURRENT_AUTH_MODE"

        if [ "$CURRENT_AUTH_MODE" = "oauth" ]; then
            email=""
            creds_to_check=""
            [ -s "$RUNTIME_CREDS" ] && creds_to_check="$RUNTIME_CREDS"
            [ -z "$creds_to_check" ] && [ -s "$STORED_CREDS" ] && creds_to_check="$STORED_CREDS"

            config_to_check=""
            [ -s "$RUNTIME_CONFIG" ] && config_to_check="$RUNTIME_CONFIG"
            [ -z "$config_to_check" ] && [ -s "$STORED_CONFIG" ] && config_to_check="$STORED_CONFIG"

            if [ -n "$creds_to_check" ] || [ -n "$config_to_check" ]; then
                email=$(get_claude_email "$creds_to_check" "$config_to_check")
            fi
            if [ -z "$email" ] && [ -s "$STORED_EMAIL_FILE" ]; then
                email=$(cat "$STORED_EMAIL_FILE" 2>/dev/null)
            fi

            if [ -n "$email" ]; then
                echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
                echo "Claude Account:    $email"
            elif [ -s "$creds_to_check" ]; then
                echo "Claude Account:    (authenticated)"
            else
                echo "Claude Account:    (not logged in. Run 'ai $TARGET_ALIAS login')"
            fi
        else
            echo "API Key:           ${ANTHROPIC_API_KEY:+configured (*****)}"
            echo "Base URL:          ${ANTHROPIC_BASE_URL:-(default / official)}"
            echo "Model:             ${ANTHROPIC_MODEL:-(default)}"
        fi
        exit 0
        ;;
    logout)
        rm -f "$STORED_CREDS" "$STORED_CONFIG" "$STORED_EMAIL_FILE" "$RUNTIME_CREDS" "$RUNTIME_CONFIG"
        CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude auth logout 2>/dev/null || true
        echo "[SUCCESS] Logged out from Claude alias '$TARGET_ALIAS'. Stored credentials removed."
        exit 0
        ;;
    login)
        shift
        echo "[INFO] Initiating login for Claude alias '$TARGET_ALIAS'..."
        rm -f "$STORED_CREDS" "$STORED_CONFIG" "$STORED_EMAIL_FILE" "$RUNTIME_CREDS"
        CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude auth login "$@"
        LOGIN_STATUS=$?
        if [ -s "$RUNTIME_CREDS" ]; then
            cp -f "$RUNTIME_CREDS" "$STORED_CREDS" 2>/dev/null || true
            chmod 600 "$STORED_CREDS" 2>/dev/null || true
        fi
        if [ -s "$RUNTIME_CONFIG" ]; then
            cp -f "$RUNTIME_CONFIG" "$STORED_CONFIG" 2>/dev/null || true
            chmod 600 "$STORED_CONFIG" 2>/dev/null || true
        fi
        email=$(get_claude_email "$RUNTIME_CREDS" "$RUNTIME_CONFIG")
        [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
        exit $LOGIN_STATUS
        ;;
esac

# Pre-execution: ensure profile runtime directory and auth store are synchronized
if [ -s "$STORED_CREDS" ] && [ ! -s "$RUNTIME_CREDS" ]; then
    cp -f "$STORED_CREDS" "$RUNTIME_CREDS"
    chmod 600 "$RUNTIME_CREDS" 2>/dev/null || true
elif [ -s "$RUNTIME_CREDS" ] && [ ! -s "$STORED_CREDS" ]; then
    cp -f "$RUNTIME_CREDS" "$STORED_CREDS"
    chmod 600 "$STORED_CREDS" 2>/dev/null || true
elif [ -s "$STORED_CREDS" ] && [ -s "$RUNTIME_CREDS" ]; then
    if [ "$STORED_CREDS" -nt "$RUNTIME_CREDS" ]; then
        cp -f "$STORED_CREDS" "$RUNTIME_CREDS"
        chmod 600 "$RUNTIME_CREDS" 2>/dev/null || true
    elif [ "$RUNTIME_CREDS" -nt "$STORED_CREDS" ]; then
        cp -f "$RUNTIME_CREDS" "$STORED_CREDS"
        chmod 600 "$STORED_CREDS" 2>/dev/null || true
    fi
fi

if [ -s "$STORED_CONFIG" ] && [ ! -s "$RUNTIME_CONFIG" ]; then
    cp -f "$STORED_CONFIG" "$RUNTIME_CONFIG" 2>/dev/null || true
    chmod 600 "$RUNTIME_CONFIG" 2>/dev/null || true
fi

# Trap to sync updated credentials back to alias auth store
sync_claude_auth_back() {
    if [ -n "$BG_SYNC_PID" ]; then
        kill "$BG_SYNC_PID" 2>/dev/null || true
    fi

    if [ -s "$RUNTIME_CREDS" ]; then
        cp -f "$RUNTIME_CREDS" "$STORED_CREDS" 2>/dev/null || true
        chmod 600 "$STORED_CREDS" 2>/dev/null || true
    fi
    if [ -s "$RUNTIME_CONFIG" ]; then
        cp -f "$RUNTIME_CONFIG" "$STORED_CONFIG" 2>/dev/null || true
        chmod 600 "$STORED_CONFIG" 2>/dev/null || true
    fi
    local email
    email=$(get_claude_email "$RUNTIME_CREDS" "$RUNTIME_CONFIG")
    [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
}
trap sync_claude_auth_back EXIT INT TERM HUP

# Background watcher to sync token as soon as user completes OAuth in browser
(
    while kill -0 $$ 2>/dev/null; do
        sleep 3
        if [ -s "$RUNTIME_CREDS" ]; then
            if [ ! -f "$STORED_CREDS" ] || [ "$RUNTIME_CREDS" -nt "$STORED_CREDS" ]; then
                cp -f "$RUNTIME_CREDS" "$STORED_CREDS" 2>/dev/null || true
                chmod 600 "$STORED_CREDS" 2>/dev/null || true
                email=$(get_claude_email "$RUNTIME_CREDS" "$RUNTIME_CONFIG")
                [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
            fi
        fi
    done
) >/dev/null 2>&1 &
BG_SYNC_PID=$!

# Isolate system DBus session bus address to prevent desktop keyring collision
export ORIGINAL_DBUS_SESSION_BUS_ADDRESS="${ORIGINAL_DBUS_SESSION_BUS_ADDRESS:-$DBUS_SESSION_BUS_ADDRESS}"
export DBUS_SESSION_BUS_ADDRESS="disabled"
export XDG_RUNTIME_DIR="$AUTH_STORE_DIR/run"

if [ -n "$ANTHROPIC_BASE_URL" ]; then
    ensure_https_base_url ANTHROPIC_BASE_URL "https://api.anthropic.com"
    export ANTHROPIC_BASE_URL
fi

# Detect whether permission/browser flags are already provided
has_skip_perms=false
has_chrome_flag=false
for arg in "$@"; do
    if [ "$arg" = "--dangerously-skip-permissions" ]; then
        has_skip_perms=true
    fi
    if [ "$arg" = "--no-chrome" ] || [ "$arg" = "--chrome" ]; then
        has_chrome_flag=true
    fi
done

CLAUDE_ARGS=()
if [ "$has_skip_perms" = false ] && [ "${CLAUDE_SKIP_PERMISSIONS:-true}" = "true" ]; then
    CLAUDE_ARGS+=(--dangerously-skip-permissions)
fi
if [ "$has_chrome_flag" = false ]; then
    CLAUDE_ARGS+=(--no-chrome)
fi
CLAUDE_ARGS+=("$@")

# Launch Claude Code
claude "${CLAUDE_ARGS[@]}"
EXIT_CODE=$?
sync_claude_auth_back
exit $EXIT_CODE
