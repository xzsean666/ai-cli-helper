#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-${AI_ORIGINAL_HOME:-$HOME}/.config/ai}"

run_doctor() {
    info "Running Doctor Diagnostic Check..."

    local provider
    provider=$(get_current_provider)
    echo -e "Current active provider: ${BOLD}${provider}${NC}"

    local provider_file="$AI_CONFIG_DIR/providers/${provider}.sh"
    if [ -f "$provider_file" ]; then
        success "[✓] Provider config file exists: $provider_file"
    else
        error "[✗] Provider config file missing: $provider_file"
    fi

    local secret_file="$AI_CONFIG_DIR/secrets/${provider}.sh"
    load_environment "$provider"

    if [ "$AI_AUTH_MODE" = "chatgpt" ]; then
        success "[✓] ChatGPT OAuth provider configured"
    elif [ "$AI_AUTH_MODE" = "google-oauth" ]; then
        success "[✓] Google OAuth provider configured (agy)"
    elif [ -f "$secret_file" ]; then
        success "[✓] Secret file exists: $secret_file"
    else
        warn "[!] Secret file missing: $secret_file (You might need to create it)"
    fi

    local orig_home="${AI_ORIGINAL_HOME:-$HOME}"

    if [ "$AI_AUTH_MODE" = "chatgpt" ]; then
        local auth_dir="$orig_home/.local/share/ai/codex/auth/${provider}"
        local profile_auth="$orig_home/.local/share/ai/codex/${provider}/.codex/auth.json"
        local auth_file="$auth_dir/auth.json"
        [ ! -s "$auth_file" ] && [ -s "$profile_auth" ] && auth_file="$profile_auth"
        local email_file="$auth_dir/email.txt"
        local email=""

        if [ -s "$auth_file" ]; then
            email=$(python3 -c "
import json, base64, sys
try:
    with open('$auth_file') as f: data = json.load(f)
    tokens = data.get('tokens', {}) if isinstance(data, dict) else {}
    id_token = tokens.get('id_token') or data.get('id_token')
    if id_token and isinstance(id_token, str) and '.' in id_token:
        parts = id_token.split('.')
        if len(parts) >= 2:
            payload = parts[1] + '=' * ((4 - len(parts[1]) % 4) % 4)
            claims = json.loads(base64.urlsafe_b64decode(payload.encode()))
            em = claims.get('email') or claims.get('https://api.openai.com/profile', {}).get('email')
            if em: print(em); sys.exit(0)
    em = data.get('email') or data.get('user', {}).get('email')
    if em: print(em); sys.exit(0)
except Exception: pass
sys.exit(1)
" 2>/dev/null)
            if [ -n "$email" ]; then
                [ -d "$auth_dir" ] && echo "$email" > "$email_file" 2>/dev/null
            fi
        fi
        [ -z "$email" ] && [ -s "$email_file" ] && email="$(cat "$email_file" 2>/dev/null)"

        if [ -s "$auth_file" ]; then
            if [ -n "$email" ]; then
                success "[✓] ChatGPT OAuth account logged in: $email"
            else
                success "[✓] ChatGPT OAuth account logged in for '$provider'"
            fi
        else
            warn "[!] ChatGPT OAuth not logged in yet for '$provider' (run: ai $provider login or ai $provider login --device-auth)"
        fi
    elif [ "$AI_AUTH_MODE" = "oauth" ] || [ "$AI_AUTH_MODE" = "claudeai" ]; then
        local auth_dir="$orig_home/.local/share/ai/claude/auth/${provider}"
        local profile_creds="$orig_home/.local/share/ai/claude/${provider}/.claude/.credentials.json"
        local creds_file="$auth_dir/.credentials.json"
        [ ! -s "$creds_file" ] && [ -s "$profile_creds" ] && creds_file="$profile_creds"
        local profile_cfg="$orig_home/.local/share/ai/claude/${provider}/.claude/.claude.json"
        local cfg_file="$auth_dir/.claude.json"
        [ ! -s "$cfg_file" ] && [ -s "$profile_cfg" ] && cfg_file="$profile_cfg"
        local email_file="$auth_dir/email.txt"
        local email=""

        if [ -s "$creds_file" ] || [ -s "$cfg_file" ]; then
            email=$(python3 -c "
import json, sys
for fpath in ('$creds_file', '$cfg_file'):
    if not fpath: continue
    try:
        with open(fpath) as f: d = json.load(f)
        for k in ('account_email', 'email', 'accountEmail', 'emailAddress'):
            if d.get(k): print(d[k]); sys.exit(0)
        for sub in ('account', 'profile', 'oauth', 'user'):
            if isinstance(d.get(sub), dict):
                for k in ('account_email', 'email', 'accountEmail', 'emailAddress'):
                    if d[sub].get(k): print(d[sub][k]); sys.exit(0)
    except Exception: pass
sys.exit(1)
" 2>/dev/null)
            if [ -n "$email" ]; then
                [ -d "$auth_dir" ] && echo "$email" > "$email_file" 2>/dev/null
            fi
        fi
        [ -z "$email" ] && [ -s "$email_file" ] && email="$(cat "$email_file" 2>/dev/null)"

        if [ -s "$creds_file" ]; then
            if [ -n "$email" ]; then
                success "[✓] Claude OAuth account logged in: $email"
            else
                success "[✓] Claude OAuth account logged in for '$provider'"
            fi
        else
            warn "[!] Claude OAuth not logged in yet for '$provider' (run: ai $provider login)"
        fi
    elif [ "$AI_AUTH_MODE" = "google-oauth" ]; then
        local auth_dir="$orig_home/.local/share/ai/agy/auth/${provider}"
        local profile_token="$orig_home/.local/share/ai/agy/${provider}/.gemini/antigravity-cli/antigravity-oauth-token"
        local token_file="$auth_dir/antigravity-oauth-token"
        [ ! -s "$token_file" ] && [ -s "$profile_token" ] && token_file="$profile_token"
        local email_file="$auth_dir/email.txt"
        local email=""
        if [ -s "$token_file" ]; then
            email=$(python3 -c "
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
" 2>/dev/null)
            if [ -n "$email" ]; then
                [ -d "$auth_dir" ] && echo "$email" > "$email_file" 2>/dev/null
            fi
        fi
        if [ -z "$email" ] && [ -s "$email_file" ]; then
            email="$(cat "$email_file" 2>/dev/null)"
        fi
        if [ -s "$token_file" ]; then
            if [ -n "$email" ]; then
                success "[✓] Google OAuth account logged in: $email"
            else
                success "[✓] Google OAuth account logged in for '$provider'"
            fi
        elif [ -f "$auth_dir/oauth_creds.json" ]; then
            success "[✓] Google OAuth credentials found for '$provider'"
        else
            warn "[!] Google OAuth not logged in yet for '$provider' (run: ai $provider login)"
        fi
    elif [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$GEMINI_API_KEY" ]; then
        success "[✓] API key detected in environment"
    else
        warn "[!] No API key configured for current provider"
    fi

    info "Checking CLI tools availability in PATH:"
    for tool in codex claude gemini aider qwen agy; do
        if command -v "$tool" >/dev/null 2>&1; then
            success "  [✓] $tool is installed ($(command -v "$tool"))"
        else
            warn "  [!] $tool is not installed in PATH"
        fi
    done
}
