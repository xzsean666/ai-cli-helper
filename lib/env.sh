#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai}"

load_environment() {
    local target="$1"
    local provider=""

    # 1. 优先检查是否存在同名的专属 provider 配置，例如 codexa -> providers/codexa.sh
    if [ -f "$AI_CONFIG_DIR/providers/${target}.sh" ]; then
        provider="$target"
    else
        # 2. 如果没有专属配置，回退读取全局的 current_provider
        provider=$(get_current_provider)
    fi

    local provider_file="$AI_CONFIG_DIR/providers/${provider}.sh"
    local secret_file="$AI_CONFIG_DIR/secrets/${provider}.sh"

    if [ ! -f "$provider_file" ]; then
        die "Provider config not found: $provider_file"
    fi

    # Unset critical variables before loading
    unset OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY
    unset OPENAI_BASE_URL ANTHROPIC_BASE_URL GEMINI_BASE_URL
    unset OPENAI_MODEL ANTHROPIC_MODEL GEMINI_MODEL
    unset AI_HOME_PROFILE

    source "$provider_file"

    if [ -f "$secret_file" ]; then
        source "$secret_file"
    else
        warn "Secret file for '$provider' not found at: $secret_file"
    fi

    export AI_ACTIVE_PROVIDER="$provider"
}

setup_cli_home() {
    local alias_name="$1"
    
    # 决定使用哪个 HOME profile 名称：
    # 1. 如果在 provider 配置文件中定义了 AI_HOME_PROFILE，则优先使用该 profile（实现多 Key 共享 HOME）
    # 2. 否则，默认使用各自别名/Provider 独立的 HOME 空间
    local home_profile="${AI_HOME_PROFILE:-$alias_name}"

    # 获取底层真实的 CLI 名称（如 codex, claude 等）
    local base_cli=""
    for base in codex claude gemini aider qwen openai; do
        if [[ "$alias_name" == "${base}"* ]]; then
            base_cli="$base"
            break
        fi
    done
    [ -z "$base_cli" ] && base_cli="$alias_name"

    local cli_home="$HOME/.local/share/ai/${base_cli}/${home_profile}"
    mkdir -p "$cli_home"
    export HOME="$cli_home"
}

show_env() {
    local target="${1:-$(get_current_provider)}"
    load_environment "$target"
    echo -e "${BOLD}Target/Provider:${NC} $AI_ACTIVE_PROVIDER"
    echo -e "${BOLD}HOME Profile:${NC}     ${AI_HOME_PROFILE:-default ($target)}"
    echo -e "${BOLD}Environment Variables:${NC}"
    echo "  OPENAI_BASE_URL:  ${OPENAI_BASE_URL:-(not set)}"
    echo "  OPENAI_MODEL:     ${OPENAI_MODEL:-(not set)}"
    echo "  OPENAI_API_KEY:   ${OPENAI_API_KEY:+"*****"}"
    echo "  ANTHROPIC_BASE_URL:${ANTHROPIC_BASE_URL:-(not set)}"
    echo "  ANTHROPIC_MODEL:  ${ANTHROPIC_MODEL:-(not set)}"
    echo "  ANTHROPIC_API_KEY:${ANTHROPIC_API_KEY:+"*****"}"
    echo "  GEMINI_BASE_URL:  ${GEMINI_BASE_URL:-(not set)}"
    echo "  GEMINI_MODEL:     ${GEMINI_MODEL:-(not set)}"
    echo "  GEMINI_API_KEY:   ${GEMINI_API_KEY:+"*****"}"
}

export_env() {
    local target="${1:-$(get_current_provider)}"
    load_environment "$target"
    echo "export OPENAI_BASE_URL=\"${OPENAI_BASE_URL}\""
    echo "export OPENAI_MODEL=\"${OPENAI_MODEL}\""
    echo "export OPENAI_API_KEY=\"${OPENAI_API_KEY}\""
    echo "export ANTHROPIC_BASE_URL=\"${ANTHROPIC_BASE_URL}\""
    echo "export ANTHROPIC_MODEL=\"${ANTHROPIC_MODEL}\""
    echo "export ANTHROPIC_API_KEY=\"${ANTHROPIC_API_KEY}\""
    echo "export GEMINI_BASE_URL=\"${GEMINI_BASE_URL}\""
    echo "export GEMINI_MODEL=\"${GEMINI_MODEL}\""
    echo "export GEMINI_API_KEY=\"${GEMINI_API_KEY}\""
}

reset_cli_home() {
    local target="${1:-claude}"
    local custom_profile="$2"

    if [ -f "$AI_CONFIG_DIR/providers/${target}.sh" ]; then
        load_environment "$target" 2>/dev/null || true
    fi

    local home_profile="${custom_profile:-${AI_HOME_PROFILE:-$target}}"

    local base_cli=""
    for base in codex claude gemini aider qwen openai; do
        if [[ "$target" == "${base}"* ]]; then
            base_cli="$base"
            break
        fi
    done
    [ -z "$base_cli" ] && base_cli="$target"

    local cli_home="$HOME/.local/share/ai/${base_cli}/${home_profile}"

    info "Resetting HOME profile for '${base_cli}' (${home_profile}) ..."
    if [ -d "$cli_home" ]; then
        rm -rf "$cli_home"
        success "Reset complete: Removed $cli_home"
    else
        warn "Profile directory does not exist: $cli_home"
    fi
}

