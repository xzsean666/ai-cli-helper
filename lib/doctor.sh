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
    if [ -f "$secret_file" ]; then
        success "[✓] Secret file exists: $secret_file"
    else
        warn "[!] Secret file missing: $secret_file (You might need to create it)"
    fi

    load_environment

    if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ] || [ -n "$GEMINI_API_KEY" ]; then
        success "[✓] API key detected in environment"
    else
        warn "[!] No API key configured for current provider"
    fi

    info "Checking CLI tools availability in PATH:"
    for tool in codex claude gemini aider qwen; do
        if command -v "$tool" >/dev/null 2>&1; then
            success "  [✓] $tool is installed ($(command -v "$tool"))"
        else
            warn "  [!] $tool is not installed in PATH"
        fi
    done
}
