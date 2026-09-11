#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-${AI_ORIGINAL_HOME:-$HOME}/.config/ai}"

ensure_https_base_url() {
    local variable_name="$1"
    local default_url="$2"
    local base_url="${!variable_name:-$default_url}"

    case "$base_url" in
        ws://*)
            base_url="https://${base_url#ws://}"
            ;;
        wss://*)
            base_url="https://${base_url#wss://}"
            ;;
    esac

    printf -v "$variable_name" '%s' "$base_url"
    export "$variable_name"
}
export -f ensure_https_base_url

load_environment() {
    local target="$1"
    local provider=""

    # 1. 优先检查是否存在同名的专属 provider 配置，例如 codexa -> providers/codexa.sh, agya -> providers/agya.sh
    if [ -f "$AI_CONFIG_DIR/providers/${target}.sh" ]; then
        provider="$target"
    else
        # 尝试匹配底层 base cli 的默认 provider 配置（例如 agyc -> providers/agy.sh）
        local matched_base=""
        for base in agy codex claude gemini aider qwen openai; do
            if [[ "$target" == "${base}"* ]]; then
                matched_base="$base"
                break
            fi
        done
        if [ -n "$matched_base" ] && [ -f "$AI_CONFIG_DIR/providers/${matched_base}.sh" ]; then
            provider="$matched_base"
        else
            # 2. 如果没有专属配置，回退读取全局的 current_provider
            provider=$(get_current_provider)
        fi
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
    unset OPENAI_REASONING_EFFORT
    unset AI_HOME_PROFILE AI_AUTH_MODE

    source "$provider_file"

    if [ -f "$secret_file" ]; then
        source "$secret_file"
    elif [ "$AI_AUTH_MODE" != "chatgpt" ] && [ "$AI_AUTH_MODE" != "google-oauth" ]; then
        warn "Secret file for '$provider' not found at: $secret_file"
    fi

    export AI_ACTIVE_PROVIDER="$provider"
}

setup_cli_home() {
    local alias_name="$1"
    
    # 获取底层真实的 CLI 名称（如 codex, claude, agy 等）
    local base_cli=""
    for base in codex claude gemini aider qwen openai agy; do
        if [[ "$alias_name" == "${base}"* ]]; then
            base_cli="$base"
            break
        fi
    done
    [ -z "$base_cli" ] && base_cli="$alias_name"

    # 决定使用哪个 HOME profile 名称：
    # 1. 如果在 provider 配置文件中定义了 AI_HOME_PROFILE，则优先使用该 profile（实现多 Key 共享 HOME）
    # 2. 否则，默认使用各自别名/Provider 独立的 HOME 空间
    local home_profile="${AI_HOME_PROFILE:-$alias_name}"

    # 保存系统真实的原始 HOME，避免嵌套调用导致路径层叠
    export AI_ORIGINAL_HOME="${AI_ORIGINAL_HOME:-$HOME}"

    # 对于基于 OAuth 认证的 CLI（如 Google OAuth / ChatGPT OAuth），
    # 凭据通常落地保存在 HOME 目录下。为了支持多账号与多终端并发运行，
    # 每个 alias 必须拥有完全独立的 HOME 目录，彻底杜绝多终端/切换账号时的串号覆盖！
    if [ "$AI_AUTH_MODE" = "google-oauth" ]; then
        if [ "$home_profile" = "shared-team" ] || [ -z "$home_profile" ]; then
            home_profile="$alias_name"
        fi
    fi

    local cli_home="$AI_ORIGINAL_HOME/.local/share/ai/${base_cli}/${home_profile}"
    mkdir -p "$cli_home"
    export HOME="$cli_home"

    # Keep Codex auth/config state inside the selected profile even when the
    # caller already exported CODEX_HOME in the parent shell.
    if [ "$base_cli" = "codex" ]; then
        export CODEX_HOME="$cli_home/.codex"
        mkdir -p "$CODEX_HOME"
    fi

    # 针对 agy (Google Antigravity CLI)，自动打通共享配置并复用系统开发环境
    if [ "$base_cli" = "agy" ]; then
        local shared_config_dir="$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-config"
        if [ ! -d "$shared_config_dir" ]; then
            mkdir -p "$shared_config_dir"
            if [ -d "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/.gemini/config" ]; then
                cp -r "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/.gemini/config/"* "$shared_config_dir/" 2>/dev/null || true
            fi
        fi
        mkdir -p "$cli_home/.gemini"

        # 共享全局 Skills、Workflows 和 MCP 配置 (~/.gemini/config)
        if [ ! -e "$cli_home/.gemini/config" ]; then
            ln -s "$shared_config_dir" "$cli_home/.gemini/config" 2>/dev/null || true
        fi

        # 初始 settings.json 继承：若当前 profile 尚未创建 settings.json，从已有配置继承
        local profile_app_dir="$cli_home/.gemini/antigravity-cli"
        mkdir -p "$profile_app_dir"
        if [ ! -f "$profile_app_dir/settings.json" ]; then
            if [ -f "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/.gemini/antigravity-cli/settings.json" ]; then
                cp "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/.gemini/antigravity-cli/settings.json" "$profile_app_dir/settings.json" 2>/dev/null || true
            elif [ -f "$AI_ORIGINAL_HOME/.gemini/antigravity-cli/settings.json" ]; then
                cp "$AI_ORIGINAL_HOME/.gemini/antigravity-cli/settings.json" "$profile_app_dir/settings.json" 2>/dev/null || true
            fi
        fi

        # 共享常用开发工具链（如 cargo, rustup, npm），避免在独立 profile 中找不到工具
        for dev_dir in .cargo .rustup .npm; do
            if [ ! -e "$cli_home/$dev_dir" ]; then
                if [ -d "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/$dev_dir" ]; then
                    ln -s "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/$dev_dir" "$cli_home/$dev_dir" 2>/dev/null || true
                elif [ -d "$AI_ORIGINAL_HOME/$dev_dir" ]; then
                    ln -s "$AI_ORIGINAL_HOME/$dev_dir" "$cli_home/$dev_dir" 2>/dev/null || true
                fi
            fi
        done
    fi
}

show_env() {
    local target="${1:-$(get_current_provider)}"
    load_environment "$target"
    local orig_home="${AI_ORIGINAL_HOME:-$HOME}"
    echo -e "${BOLD}Target/Provider:${NC} $AI_ACTIVE_PROVIDER"
    echo -e "${BOLD}Auth Mode:${NC}       ${AI_AUTH_MODE:-api-key}"
    echo -e "${BOLD}HOME Profile:${NC}    ${AI_HOME_PROFILE:-default ($target)}"

    if [ "$AI_AUTH_MODE" = "google-oauth" ]; then
        local auth_dir="$orig_home/.local/share/ai/agy/auth/${target}"
        local profile_token="$orig_home/.local/share/ai/agy/${target}/.gemini/antigravity-cli/antigravity-oauth-token"
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
                echo -e "${BOLD}Google Account:${NC}  $email"
            else
                echo -e "${BOLD}Google Account:${NC}  (authenticated)"
            fi
        else
            echo -e "${BOLD}Google Account:${NC}  (not logged in - run: ai $target login)"
        fi
    fi

    echo -e "${BOLD}Environment Variables:${NC}"
    echo "  OPENAI_BASE_URL:  ${OPENAI_BASE_URL:-(not set)}"
    echo "  OPENAI_MODEL:     ${OPENAI_MODEL:-(not set)}"
    echo "  OPENAI_REASONING_EFFORT: ${OPENAI_REASONING_EFFORT:-(not set)}"
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
    if [ "$AI_AUTH_MODE" = "google-oauth" ] && [ "$home_profile" = "shared-team" ]; then
        home_profile="$target"
    fi

    local base_cli=""
    for base in codex claude gemini aider qwen openai agy; do
        if [[ "$target" == "${base}"* ]]; then
            base_cli="$base"
            break
        fi
    done
    [ -z "$base_cli" ] && base_cli="$target"

    local orig_home="${AI_ORIGINAL_HOME:-$HOME}"
    local cli_home="$orig_home/.local/share/ai/${base_cli}/${home_profile}"

    info "Resetting HOME profile for '${base_cli}' (${home_profile}) ..."
    if [ -d "$cli_home" ]; then
        rm -rf "$cli_home"
        success "Reset complete: Removed $cli_home"
    else
        warn "Profile directory does not exist: $cli_home"
    fi

    if [ "$base_cli" = "agy" ]; then
        local auth_dir="$orig_home/.local/share/ai/agy/auth/$target"
        if [ -d "$auth_dir" ]; then
            info "Resetting OAuth credentials for agy alias '${target}' ..."
            rm -rf "$auth_dir"
            success "OAuth credentials reset: Removed $auth_dir"
        fi
    fi
}
