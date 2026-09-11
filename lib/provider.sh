#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-${AI_ORIGINAL_HOME:-$HOME}/.config/ai}"
CURRENT_PROVIDER_FILE="$AI_CONFIG_DIR/current_provider"

get_current_provider() {
    if [ -f "$CURRENT_PROVIDER_FILE" ]; then
        cat "$CURRENT_PROVIDER_FILE" | tr -d ' \n\r'
    else
        echo "openai"
    fi
}

set_current_provider() {
    local provider="$1"
    if [ ! -f "$AI_CONFIG_DIR/providers/${provider}.sh" ]; then
        error "Provider configuration 'providers/${provider}.sh' does not exist."
        return 1
    fi
    echo "$provider" > "$CURRENT_PROVIDER_FILE"
    success "Switched current provider to: ${BOLD}${provider}${NC}"
}

list_providers() {
    local current
    current=$(get_current_provider)
    info "Available Providers:"
    for p_file in "$AI_CONFIG_DIR/providers/"*.sh; do
        [ -e "$p_file" ] || continue
        local p_name
        p_name=$(basename "$p_file" .sh)
        if [ "$p_name" = "$current" ]; then
            echo -e "  ${GREEN}* ${p_name} (current)${NC}"
        else
            echo -e "    ${p_name}"
        fi
    done
}

add_provider() {
    local provider="$1"
    if [ -z "$provider" ]; then
        read -p "Enter new provider name: " provider
    fi
    [ -z "$provider" ] && die "Provider name cannot be empty."

    local target_provider="$AI_CONFIG_DIR/providers/${provider}.sh"
    local target_secret="$AI_CONFIG_DIR/secrets/${provider}.sh"

    if [ -f "$target_provider" ]; then
        warn "Provider config '$provider' already exists."
    else
        if [ -f "$AI_CONFIG_DIR/templates/provider.sh.template" ]; then
            cp "$AI_CONFIG_DIR/templates/provider.sh.template" "$target_provider"
        else
            cat << 'EOF' > "$target_provider"
# Provider configuration for custom provider
export AI_PROVIDER_NAME="custom"
export OPENAI_BASE_URL="https://api.openai.com/v1"
export ANTHROPIC_BASE_URL="https://api.anthropic.com"
export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"

# Default Models
export OPENAI_MODEL="gpt-4o"
export ANTHROPIC_MODEL="claude-3-5-sonnet-20241022"
export GEMINI_MODEL="gemini-2.5-flash"
EOF
        fi
        success "Created provider config: $target_provider"
    fi

    if [ ! -f "$target_secret" ]; then
        if [ -f "$AI_CONFIG_DIR/templates/secret.sh.template" ]; then
            cp "$AI_CONFIG_DIR/templates/secret.sh.template" "$target_secret"
        else
            cat << 'EOF' > "$target_secret"
# Secret Configuration
export OPENAI_API_KEY=""
export ANTHROPIC_API_KEY=""
export GEMINI_API_KEY=""
EOF
        fi
        chmod 600 "$target_secret"
        success "Created secret file: $target_secret (Please edit this file to fill in your API key)"
    fi
}

remove_provider() {
    local provider="$1"
    [ -z "$provider" ] && die "Please specify provider to remove."
    
    local target_provider="$AI_CONFIG_DIR/providers/${provider}.sh"
    local target_secret="$AI_CONFIG_DIR/secrets/${provider}.sh"

    if [ -f "$target_provider" ]; then
        rm -f "$target_provider"
        success "Removed provider config: $target_provider"
    fi
    if [ -f "$target_secret" ]; then
        rm -f "$target_secret"
        success "Removed secret file: $target_secret"
    fi
}
