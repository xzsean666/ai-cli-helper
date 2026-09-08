#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai}"

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

    if [ "$AI_AUTH_MODE" = "chatgpt" ]; then
        info "ChatGPT OAuth credentials are managed by Codex (run: ai codexh login)"
    elif [ "$AI_AUTH_MODE" = "google-oauth" ]; then
        local orig_home="${AI_ORIGINAL_HOME:-$HOME}"
        local auth_dir="$orig_home/.local/share/ai/agy/auth/${provider}"
        local token_file="$auth_dir/antigravity-oauth-token"
        local email_file="$auth_dir/email.txt"
        local email=""
        if [ -s "$email_file" ]; then
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
