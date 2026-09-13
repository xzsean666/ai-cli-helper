#!/usr/bin/env bash

# Launcher wrapper for OpenAI / Codex CLI
if ! command -v codex >/dev/null 2>&1 && ! command -v openai >/dev/null 2>&1; then
    echo "[ERROR] Neither 'codex' nor 'openai' CLI binary was found in PATH."
    exit 1
fi

# Fallback to legacy openai CLI if codex binary is absent
if ! command -v codex >/dev/null 2>&1; then
    exec openai "$@"
fi

TARGET_ALIAS="${AI_ACTIVE_ALIAS:-${AI_ACTIVE_PROVIDER:-codex}}"
ORIG_HOME="${AI_ORIGINAL_HOME:-$HOME}"
AUTH_STORE_DIR="$ORIG_HOME/.local/share/ai/codex/auth/$TARGET_ALIAS"

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
RUNTIME_AUTH="$CODEX_HOME/auth.json"
STORED_AUTH="$AUTH_STORE_DIR/auth.json"
STORED_EMAIL_FILE="$AUTH_STORE_DIR/email.txt"

mkdir -p "$AUTH_STORE_DIR/run"
mkdir -p "$CODEX_HOME"

# Helper function to extract email from a Codex auth.json file
get_codex_email() {
    local auth_file="$1"
    if [ -s "$auth_file" ]; then
        python3 -c "
import json, base64, sys

auth_path = '$auth_file'
try:
    with open(auth_path) as f:
        data = json.load(f)
    # Check tokens.id_token JWT payload
    tokens = data.get('tokens', {}) if isinstance(data, dict) else {}
    id_token = tokens.get('id_token') or (data.get('id_token') if isinstance(data, dict) else '')
    if id_token and isinstance(id_token, str) and '.' in id_token:
        parts = id_token.split('.')
        if len(parts) >= 2:
            payload = parts[1]
            payload += '=' * ((4 - len(payload) % 4) % 4)
            claims = json.loads(base64.urlsafe_b64decode(payload.encode()))
            em = claims.get('email') or claims.get('https://api.openai.com/profile', {}).get('email')
            if em:
                print(em)
                sys.exit(0)
    # Check direct user email fields
    em = data.get('email') or data.get('user', {}).get('email') if isinstance(data, dict) else ''
    if em:
        print(em)
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
" 2>/dev/null
    fi
}

# Helper function to determine authentication mode (chatgpt vs apikey)
detect_auth_mode() {
    local explicit_mode="${AI_AUTH_MODE:-auto}"
    local explicit_lower
    explicit_lower=$(echo "$explicit_mode" | tr '[:upper:]' '[:lower:]')

    case "$explicit_lower" in
        "chatgpt"|"oauth")
            echo "chatgpt"
            return 0
            ;;
        "api-key"|"apikey"|"api_key"|"api")
            echo "apikey"
            return 0
            ;;
    esac

    # In auto mode:
    # 1. If OPENAI_API_KEY is explicitly set and non-empty, prioritize API key mode
    if [ -n "$OPENAI_API_KEY" ]; then
        echo "apikey"
        return 0
    fi

    # 2. Check if auth.json has stored ChatGPT tokens
    for check_file in "$RUNTIME_AUTH" "$STORED_AUTH"; do
        if [ -s "$check_file" ]; then
            local mode
            mode=$(python3 -c "
import json
try:
    with open('$check_file') as f:
        d = json.load(f)
    if d.get('auth_mode') == 'chatgpt' or ('tokens' in d and d['tokens'].get('access_token')):
        print('chatgpt')
    elif d.get('auth_mode') == 'apikey' or d.get('OPENAI_API_KEY'):
        print('apikey')
except Exception: pass
" 2>/dev/null)
            if [ -n "$mode" ]; then
                echo "$mode"
                return 0
            fi
        fi
    done

    # 3. If OPENAI_BASE_URL is set, assume API mode
    if [ -n "$OPENAI_BASE_URL" ]; then
        echo "apikey"
        return 0
    fi

    echo "chatgpt"
}

CURRENT_AUTH_MODE=$(detect_auth_mode)

# Helper subcommands for Codex credential & profile management
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

        echo "Profile / Alias: $TARGET_ALIAS"
        echo "HOME Profile:    $raw_prof"
        echo "Data Sharing:    $share_status"
        echo "HOME Directory:  $HOME"
        echo "CODEX_HOME:      $CODEX_HOME"
        echo "Auth Storage:    $AUTH_STORE_DIR"
        echo "Auth Mode:       $CURRENT_AUTH_MODE"

        if [ "$CURRENT_AUTH_MODE" = "chatgpt" ]; then
            auth_to_check=""
            if [ -s "$RUNTIME_AUTH" ]; then
                auth_to_check="$RUNTIME_AUTH"
            elif [ -s "$STORED_AUTH" ]; then
                auth_to_check="$STORED_AUTH"
            fi

            email=""
            if [ -n "$auth_to_check" ]; then
                email=$(get_codex_email "$auth_to_check")
                if [ -n "$email" ]; then
                    echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
                elif [ -s "$STORED_EMAIL_FILE" ]; then
                    email=$(cat "$STORED_EMAIL_FILE" 2>/dev/null)
                fi
            fi

            if [ -n "$email" ]; then
                echo "ChatGPT Account: $email"
            elif [ -n "$auth_to_check" ]; then
                echo "ChatGPT Account: (authenticated)"
            else
                echo "ChatGPT Account: (not logged in. Run 'ai $TARGET_ALIAS login' or 'ai $TARGET_ALIAS login --device-auth')"
            fi
        else
            echo "API Key:         ${OPENAI_API_KEY:+configured (*****)}"
            echo "Base URL:        ${OPENAI_BASE_URL:-(default / official)}"
            echo "Model:           ${OPENAI_MODEL:-(default)}"
            echo "Reasoning Effort:${OPENAI_REASONING_EFFORT:-(default)}"
        fi
        exit 0
        ;;
    logout)
        rm -f "$STORED_AUTH" "$STORED_EMAIL_FILE" "$RUNTIME_AUTH"
        CODEX_HOME="$CODEX_HOME" codex logout 2>/dev/null || true
        echo "[SUCCESS] Logged out from Codex alias '$TARGET_ALIAS'. Stored credentials removed."
        exit 0
        ;;
    login)
        shift
        echo "[INFO] Starting login flow for Codex alias '$TARGET_ALIAS'..."
        # If user is logging in with ChatGPT, clear previous apikey or tokens to avoid stale state
        rm -f "$RUNTIME_AUTH" "$STORED_AUTH" "$STORED_EMAIL_FILE"
        CODEX_HOME="$CODEX_HOME" codex login "$@"
        LOGIN_STATUS=$?
        if [ -s "$RUNTIME_AUTH" ]; then
            cp -f "$RUNTIME_AUTH" "$STORED_AUTH" 2>/dev/null || true
            chmod 600 "$STORED_AUTH" 2>/dev/null || true
            email=$(get_codex_email "$RUNTIME_AUTH")
            [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
        fi
        exit $LOGIN_STATUS
        ;;
esac

# Pre-execution: synchronize auth store and runtime CODEX_HOME
if [ "$CURRENT_AUTH_MODE" = "apikey" ]; then
    if [ -n "$OPENAI_API_KEY" ]; then
        umask 077
        printf '{"auth_mode":"apikey","OPENAI_API_KEY":"%s"}\n' "$OPENAI_API_KEY" > "$RUNTIME_AUTH"
        cp -f "$RUNTIME_AUTH" "$STORED_AUTH" 2>/dev/null || true
        chmod 600 "$STORED_AUTH" 2>/dev/null || true
    fi
else
    # ChatGPT OAuth mode: sync stored auth into runtime
    if [ -s "$STORED_AUTH" ] && [ ! -s "$RUNTIME_AUTH" ]; then
        cp -f "$STORED_AUTH" "$RUNTIME_AUTH"
        chmod 600 "$RUNTIME_AUTH" 2>/dev/null || true
    elif [ -s "$RUNTIME_AUTH" ] && [ ! -s "$STORED_AUTH" ]; then
        cp -f "$RUNTIME_AUTH" "$STORED_AUTH"
        chmod 600 "$STORED_AUTH" 2>/dev/null || true
    elif [ -s "$STORED_AUTH" ] && [ -s "$RUNTIME_AUTH" ]; then
        if [ "$STORED_AUTH" -nt "$RUNTIME_AUTH" ]; then
            cp -f "$STORED_AUTH" "$RUNTIME_AUTH"
            chmod 600 "$RUNTIME_AUTH" 2>/dev/null || true
        elif [ "$RUNTIME_AUTH" -nt "$STORED_AUTH" ]; then
            cp -f "$RUNTIME_AUTH" "$STORED_AUTH"
            chmod 600 "$STORED_AUTH" 2>/dev/null || true
        fi
    fi
fi

# Trap to sync any updated or refreshed credentials back to alias auth store
sync_codex_auth_back() {
    if [ -n "$BG_SYNC_PID" ]; then
        kill "$BG_SYNC_PID" 2>/dev/null || true
    fi

    if [ -s "$RUNTIME_AUTH" ]; then
        cp -f "$RUNTIME_AUTH" "$STORED_AUTH" 2>/dev/null || true
        chmod 600 "$STORED_AUTH" 2>/dev/null || true
        local email
        email=$(get_codex_email "$RUNTIME_AUTH")
        [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
    fi
}
trap sync_codex_auth_back EXIT INT TERM HUP

# Background watcher to sync token as soon as user completes OAuth in browser/device code
(
    while kill -0 $$ 2>/dev/null; do
        sleep 3
        if [ -s "$RUNTIME_AUTH" ]; then
            if [ ! -f "$STORED_AUTH" ] || [ "$RUNTIME_AUTH" -nt "$STORED_AUTH" ]; then
                cp -f "$RUNTIME_AUTH" "$STORED_AUTH" 2>/dev/null || true
                chmod 600 "$STORED_AUTH" 2>/dev/null || true
                email=$(get_codex_email "$RUNTIME_AUTH")
                [ -n "$email" ] && echo "$email" > "$STORED_EMAIL_FILE" 2>/dev/null
            fi
        fi
    done
) >/dev/null 2>&1 &
BG_SYNC_PID=$!

# Isolate system DBus session bus address to avoid keyring credential leakage
export ORIGINAL_DBUS_SESSION_BUS_ADDRESS="${ORIGINAL_DBUS_SESSION_BUS_ADDRESS:-$DBUS_SESSION_BUS_ADDRESS}"
export DBUS_SESSION_BUS_ADDRESS="disabled"
export XDG_RUNTIME_DIR="$AUTH_STORE_DIR/run"

OPTS=()

# Configure API provider options ONLY when in apikey mode
if [ "$CURRENT_AUTH_MODE" = "apikey" ]; then
    if [ -n "$OPENAI_BASE_URL" ]; then
        ensure_https_base_url OPENAI_BASE_URL "https://api.openai.com/v1"
        OPTS+=(
            -c 'model_provider="ai_helper"'
            -c 'model_providers.ai_helper.name="AI CLI Helper"'
            -c "model_providers.ai_helper.base_url=\"$OPENAI_BASE_URL\""
            -c 'model_providers.ai_helper.env_key="OPENAI_API_KEY"'
            -c 'model_providers.ai_helper.wire_api="responses"'
            -c 'model_providers.ai_helper.supports_websockets=false'
        )
    fi

    if [ -n "$OPENAI_MODEL" ]; then
        OPTS+=(-c "model=\"$OPENAI_MODEL\"")
    fi

    if [ -n "$OPENAI_REASONING_EFFORT" ]; then
        OPTS+=(-c "model_reasoning_effort=\"$OPENAI_REASONING_EFFORT\"")
    fi

    # Load local metadata so custom Grok models work with /model and effort selection
    if [[ "$OPENAI_MODEL" == grok-* ]]; then
        grok_catalog="${AI_CONFIG_DIR:-$HOME/.config/ai}/templates/codex-grok-models.json"
        if [ -f "$grok_catalog" ]; then
            OPTS+=(-c "model_catalog_json=\"$grok_catalog\"")
        fi
    fi
else
    # In ChatGPT OAuth mode, optionally pass model override if user explicitly set OPENAI_MODEL
    if [ -n "$OPENAI_MODEL" ]; then
        OPTS+=(-m "$OPENAI_MODEL")
    fi
fi

# Detect whether a known subcommand or approval flag is passed
is_subcommand=false
has_approval_flag=false
for arg in "$@"; do
    case "$arg" in
        --yolo|--ask-for-approval|--dangerously-bypass-approvals-and-sandbox|-a)
            has_approval_flag=true
            ;;
        login|logout|doctor|resume|fork|archive|unarchive|delete|apply|exec|e|review|mcp|plugin|cloud)
            is_subcommand=true
            ;;
    esac
done

CODEX_ARGS=()
if [ "$has_approval_flag" = false ] && [ "$is_subcommand" = false ] && [ "${CODEX_DISABLE_YOLO:-false}" != "true" ]; then
    CODEX_ARGS+=(--yolo)
fi
CODEX_ARGS+=("${OPTS[@]}")
CODEX_ARGS+=("$@")

# Launch Codex
codex "${CODEX_ARGS[@]}"
EXIT_CODE=$?
sync_codex_auth_back
exit $EXIT_CODE
