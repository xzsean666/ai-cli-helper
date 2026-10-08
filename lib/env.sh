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

    local caller_profile="${AI_HOME_PROFILE:-}"
    # If caller_profile was inherited from a different alias, do not leak it across aliases
    if [ -n "$caller_profile" ] && [ -n "$AI_ACTIVE_ALIAS" ] && [ "$caller_profile" = "$AI_ACTIVE_ALIAS" ] && [ "$caller_profile" != "$target" ]; then
        caller_profile=""
    fi

    # Unset critical variables before loading
    unset OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY
    unset OPENAI_BASE_URL ANTHROPIC_BASE_URL GEMINI_BASE_URL
    unset OPENAI_MODEL ANTHROPIC_MODEL GEMINI_MODEL
    unset OPENAI_REASONING_EFFORT
    unset AI_HOME_PROFILE AI_AUTH_MODE CODEX_MODELS

    source "$provider_file"

    if [ -n "$caller_profile" ]; then
        export AI_HOME_PROFILE="$caller_profile"
    fi

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

    # 保存系统真实的原始 HOME，避免嵌套调用导致路径层叠
    export AI_ORIGINAL_HOME="${AI_ORIGINAL_HOME:-$HOME}"

    # 解析当前配置的数据模式 (shared / isolated / group) 与 Profile 名称
    local raw_profile="${AI_HOME_PROFILE:-shared-team}"
    local profile_lower
    profile_lower=$(echo "$raw_profile" | tr '[:upper:]' '[:lower:]')

    local data_mode="shared"
    local pool_name="shared-data"

    case "$profile_lower" in
        "isolated"|"isolate"|"private"|"standalone")
            data_mode="isolated"
            pool_name="$alias_name"
            ;;
        "shared"|"share"|"shared-team"|"shared-data"|"common"|"team")
            if [ "$AI_SHARE_DATA" = "false" ]; then
                data_mode="isolated"
                pool_name="$alias_name"
            else
                data_mode="shared"
                pool_name="shared-data"
            fi
            ;;
        *)
            if [ "$profile_lower" = "$alias_name" ]; then
                data_mode="isolated"
                pool_name="$alias_name"
            else
                data_mode="group"
                pool_name="$raw_profile"
            fi
            ;;
    esac

    export AI_HOME_PROFILE="$raw_profile"
    export AI_DATA_MODE="$data_mode"
    export AI_DATA_POOL="$pool_name"

    local cli_home
    if [ "$base_cli" = "agy" ] || [ "$base_cli" = "codex" ] || [ "$base_cli" = "claude" ]; then
        # agy, codex, claude 均支持多账号独立凭据与运行时隔离，
        # 而历史会话与数据根据 data_mode 决定软链接到共享池还是保持独立。
        cli_home="$AI_ORIGINAL_HOME/.local/share/ai/${base_cli}/${alias_name}"
    else
        local home_profile
        if [ "$data_mode" = "isolated" ]; then
            home_profile="$alias_name"
        elif [ "$data_mode" = "shared" ]; then
            home_profile="shared-team"
        else
            home_profile="$pool_name"
        fi
        cli_home="$AI_ORIGINAL_HOME/.local/share/ai/${base_cli}/${home_profile}"
    fi

    mkdir -p "$cli_home"
    export HOME="$cli_home"

    if [ "$base_cli" = "codex" ]; then
        export CODEX_HOME="$cli_home/.codex"
        mkdir -p "$CODEX_HOME"
    elif [ "$base_cli" = "claude" ]; then
        export CLAUDE_CONFIG_DIR="$cli_home/.claude"
        mkdir -p "$CLAUDE_CONFIG_DIR"
    fi

    # 针对 agy (Google Antigravity CLI)，根据 data_mode 控制数据持久化、共享与隔离
    if [ "$base_cli" = "agy" ]; then
        # 1. 共享全局 Skills、Workflows 和 MCP 配置 (~/.gemini/config)
        local shared_config_dir="$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-config"
        if [ ! -d "$shared_config_dir" ]; then
            mkdir -p "$shared_config_dir"
            if [ -d "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/.gemini/config" ]; then
                cp -r "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/.gemini/config/"* "$shared_config_dir/" 2>/dev/null || true
            elif [ -d "$AI_ORIGINAL_HOME/.gemini/config" ]; then
                cp -r "$AI_ORIGINAL_HOME/.gemini/config/"* "$shared_config_dir/" 2>/dev/null || true
            fi
        fi
        mkdir -p "$cli_home/.gemini"
        if [ ! -e "$cli_home/.gemini/config" ]; then
            ln -s "$shared_config_dir" "$cli_home/.gemini/config" 2>/dev/null || true
        fi

        # 2. 为当前 profile 初始化 .gemini/antigravity-cli 运行时基础目录
        local profile_app_dir="$cli_home/.gemini/antigravity-cli"
        mkdir -p "$profile_app_dir"/{log,crashes,presence}

        # 3. 根持久化共享池目录（全局 shared-data）
        local global_shared_data="$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-data"
        mkdir -p "$global_shared_data"/{brain,conversations,knowledge,annotations,scratch}

        # 4. 根据 data_mode 决定数据存储策略
        if [ "$data_mode" = "isolated" ]; then
            # === 完全私有隔离模式 (Isolated Mode) ===
            # 解除所有指向共享池的软链接，建立本地私有独立目录与文件
            for item in brain conversations knowledge annotations scratch; do
                if [ -L "$profile_app_dir/$item" ]; then
                    rm -f "$profile_app_dir/$item"
                fi
                mkdir -p "$profile_app_dir/$item"
            done

            if [ -L "$profile_app_dir/conversation_summaries.db" ]; then
                rm -f "$profile_app_dir/conversation_summaries.db"*
            fi

            if [ -L "$profile_app_dir/history.jsonl" ]; then
                rm -f "$profile_app_dir/history.jsonl"
                touch "$profile_app_dir/history.jsonl"
            else
                [ -f "$profile_app_dir/history.jsonl" ] || touch "$profile_app_dir/history.jsonl"
            fi

            if [ -L "$profile_app_dir/settings.json" ]; then
                local real_settings
                real_settings=$(readlink -f "$profile_app_dir/settings.json" 2>/dev/null || true)
                rm -f "$profile_app_dir/settings.json"
                if [ -f "$real_settings" ]; then
                    cp "$real_settings" "$profile_app_dir/settings.json" 2>/dev/null || true
                fi
            fi
            if [ ! -f "$profile_app_dir/settings.json" ] && [ -f "$global_shared_data/settings.json" ]; then
                cp "$global_shared_data/settings.json" "$profile_app_dir/settings.json" 2>/dev/null || true
            fi

            if [ ! -f "$profile_app_dir/jetski_state.pbtxt" ] && [ -f "$global_shared_data/jetski_state.pbtxt" ]; then
                cp "$global_shared_data/jetski_state.pbtxt" "$profile_app_dir/jetski_state.pbtxt" 2>/dev/null || true
            fi
            if [ ! -f "$profile_app_dir/installation_id" ] && [ -f "$global_shared_data/installation_id" ]; then
                cp "$global_shared_data/installation_id" "$profile_app_dir/installation_id" 2>/dev/null || true
            fi

        else
            # === 共享模式 (Shared: 全局 shared-data 或 Group: pools/<name>) ===
            local target_pool_dir
            if [ "$data_mode" = "shared" ]; then
                target_pool_dir="$global_shared_data"
            else
                target_pool_dir="$AI_ORIGINAL_HOME/.local/share/ai/agy/pools/${pool_name}"
            fi

            mkdir -p "$target_pool_dir"/{brain,conversations,knowledge,annotations,scratch}
            if [ ! -f "$target_pool_dir/settings.json" ] && [ -f "$global_shared_data/settings.json" ]; then
                cp "$global_shared_data/settings.json" "$target_pool_dir/settings.json" 2>/dev/null || true
            fi
            if [ ! -f "$target_pool_dir/jetski_state.pbtxt" ] && [ -f "$global_shared_data/jetski_state.pbtxt" ]; then
                cp "$global_shared_data/jetski_state.pbtxt" "$target_pool_dir/jetski_state.pbtxt" 2>/dev/null || true
            fi
            if [ ! -f "$target_pool_dir/installation_id" ] && [ -f "$global_shared_data/installation_id" ]; then
                cp "$global_shared_data/installation_id" "$target_pool_dir/installation_id" 2>/dev/null || true
            fi

            # (a) 目录软链接 (brain, conversations, knowledge, annotations, scratch)
            for item in brain conversations knowledge annotations scratch; do
                if [ -L "$profile_app_dir/$item" ]; then
                    local cur_link
                    cur_link=$(readlink "$profile_app_dir/$item" 2>/dev/null || true)
                    if [ "$cur_link" != "$target_pool_dir/$item" ]; then
                        rm -f "$profile_app_dir/$item"
                        ln -sfn "$target_pool_dir/$item" "$profile_app_dir/$item" 2>/dev/null || true
                    fi
                elif [ -d "$profile_app_dir/$item" ]; then
                    # 之前在 isolated 模式下生成的本地内容，无缝迁移合并进共享池
                    cp -rn "$profile_app_dir/$item/"* "$target_pool_dir/$item/" 2>/dev/null || true
                    rm -rf "$profile_app_dir/$item" 2>/dev/null
                    ln -sfn "$target_pool_dir/$item" "$profile_app_dir/$item" 2>/dev/null || true
                else
                    rm -f "$profile_app_dir/$item" 2>/dev/null || true
                    ln -sfn "$target_pool_dir/$item" "$profile_app_dir/$item" 2>/dev/null || true
                fi
            done

            # (b) conversation_summaries.db (SQLite 会话索引数据库)
            if [ -f "$target_pool_dir/conversation_summaries.db" ]; then
                if [ -L "$profile_app_dir/conversation_summaries.db" ]; then
                    local cur_db_link
                    cur_db_link=$(readlink "$profile_app_dir/conversation_summaries.db" 2>/dev/null || true)
                    if [ "$cur_db_link" != "$target_pool_dir/conversation_summaries.db" ]; then
                        rm -f "$profile_app_dir/conversation_summaries.db"*
                        ln -sf "$target_pool_dir/conversation_summaries.db" "$profile_app_dir/conversation_summaries.db" 2>/dev/null || true
                    fi
                elif [ -f "$profile_app_dir/conversation_summaries.db" ]; then
                    # 合并本地 SQLite 记录至共享池 DB
                    python3 -c "
import sqlite3, os
src_db = '$profile_app_dir/conversation_summaries.db'
dst_db = '$target_pool_dir/conversation_summaries.db'
if os.path.isfile(src_db) and os.path.isfile(dst_db):
    try:
        conn = sqlite3.connect(dst_db)
        cur = conn.cursor()
        cur.execute('ATTACH DATABASE ? AS src', (src_db,))
        cur.execute('INSERT OR IGNORE INTO main.conversation_summaries SELECT * FROM src.conversation_summaries')
        conn.commit()
        conn.close()
    except Exception: pass
" 2>/dev/null || true
                    rm -f "$profile_app_dir/conversation_summaries.db"* 2>/dev/null
                    ln -sf "$target_pool_dir/conversation_summaries.db" "$profile_app_dir/conversation_summaries.db" 2>/dev/null || true
                else
                    rm -f "$profile_app_dir/conversation_summaries.db"* 2>/dev/null
                    ln -sf "$target_pool_dir/conversation_summaries.db" "$profile_app_dir/conversation_summaries.db" 2>/dev/null || true
                fi
            elif [ -f "$profile_app_dir/conversation_summaries.db" ] && [ ! -L "$profile_app_dir/conversation_summaries.db" ]; then
                cp "$profile_app_dir/conversation_summaries.db" "$target_pool_dir/conversation_summaries.db" 2>/dev/null || true
                rm -f "$profile_app_dir/conversation_summaries.db"* 2>/dev/null
                ln -sf "$target_pool_dir/conversation_summaries.db" "$profile_app_dir/conversation_summaries.db" 2>/dev/null || true
            fi

            # (c) history.jsonl
            [ -f "$target_pool_dir/history.jsonl" ] || touch "$target_pool_dir/history.jsonl"
            if [ -L "$profile_app_dir/history.jsonl" ]; then
                local cur_hist_link
                cur_hist_link=$(readlink "$profile_app_dir/history.jsonl" 2>/dev/null || true)
                if [ "$cur_hist_link" != "$target_pool_dir/history.jsonl" ]; then
                    rm -f "$profile_app_dir/history.jsonl"
                    ln -sf "$target_pool_dir/history.jsonl" "$profile_app_dir/history.jsonl" 2>/dev/null || true
                fi
            elif [ -f "$profile_app_dir/history.jsonl" ]; then
                cat "$profile_app_dir/history.jsonl" >> "$target_pool_dir/history.jsonl" 2>/dev/null || true
                rm -f "$profile_app_dir/history.jsonl" 2>/dev/null
                ln -sf "$target_pool_dir/history.jsonl" "$profile_app_dir/history.jsonl" 2>/dev/null || true
            else
                rm -f "$profile_app_dir/history.jsonl" 2>/dev/null
                ln -sf "$target_pool_dir/history.jsonl" "$profile_app_dir/history.jsonl" 2>/dev/null || true
            fi

            # (d) settings.json
            if [ -f "$target_pool_dir/settings.json" ]; then
                if [ -L "$profile_app_dir/settings.json" ]; then
                    local cur_set_link
                    cur_set_link=$(readlink "$profile_app_dir/settings.json" 2>/dev/null || true)
                    if [ "$cur_set_link" != "$target_pool_dir/settings.json" ]; then
                        rm -f "$profile_app_dir/settings.json"
                        ln -sf "$target_pool_dir/settings.json" "$profile_app_dir/settings.json" 2>/dev/null || true
                    fi
                else
                    rm -f "$profile_app_dir/settings.json" 2>/dev/null
                    ln -sf "$target_pool_dir/settings.json" "$profile_app_dir/settings.json" 2>/dev/null || true
                fi
            fi

            # (e) jetski_state.pbtxt & installation_id (保持 workspace 及初始化配置统一)
            if [ -f "$target_pool_dir/jetski_state.pbtxt" ] && [ ! -f "$profile_app_dir/jetski_state.pbtxt" ]; then
                cp "$target_pool_dir/jetski_state.pbtxt" "$profile_app_dir/jetski_state.pbtxt" 2>/dev/null || true
            fi
            if [ -f "$target_pool_dir/installation_id" ] && [ ! -f "$profile_app_dir/installation_id" ]; then
                cp "$target_pool_dir/installation_id" "$profile_app_dir/installation_id" 2>/dev/null || true
            fi
        fi
    fi

    # 针对 codex，根据 data_mode 控制会话记录、历史与状态共享
    if [ "$base_cli" = "codex" ]; then
        local global_shared_codex="$AI_ORIGINAL_HOME/.local/share/ai/codex/shared-data"
        mkdir -p "$global_shared_codex"/{rollouts,archived_rollouts,sessions}

        local target_pool_dir
        if [ "$data_mode" = "shared" ]; then
            target_pool_dir="$global_shared_codex"
        elif [ "$data_mode" = "group" ]; then
            target_pool_dir="$AI_ORIGINAL_HOME/.local/share/ai/codex/pools/${pool_name}"
            mkdir -p "$target_pool_dir"/{rollouts,archived_rollouts,sessions}
        fi

        if [ "$data_mode" = "isolated" ]; then
            # === 完全私有隔离模式 (Isolated Mode) ===
            for item in rollouts archived_rollouts sessions; do
                if [ -L "$CODEX_HOME/$item" ]; then
                    rm -f "$CODEX_HOME/$item"
                fi
                mkdir -p "$CODEX_HOME/$item"
            done
            if [ -L "$CODEX_HOME/history.jsonl" ]; then
                rm -f "$CODEX_HOME/history.jsonl"
                touch "$CODEX_HOME/history.jsonl"
            else
                [ -f "$CODEX_HOME/history.jsonl" ] || touch "$CODEX_HOME/history.jsonl"
            fi
            for db in "$CODEX_HOME"/*.sqlite; do
                [ -L "$db" ] && rm -f "$db"
            done
        else
            # === 共享模式 (Shared 全局 shared-data 或 Group pools/<name>) ===
            for item in rollouts archived_rollouts sessions; do
                if [ -L "$CODEX_HOME/$item" ]; then
                    local cur_link
                    cur_link=$(readlink "$CODEX_HOME/$item" 2>/dev/null || true)
                    if [ "$cur_link" != "$target_pool_dir/$item" ]; then
                        rm -f "$CODEX_HOME/$item"
                        ln -sfn "$target_pool_dir/$item" "$CODEX_HOME/$item" 2>/dev/null || true
                    fi
                elif [ -d "$CODEX_HOME/$item" ]; then
                    cp -rn "$CODEX_HOME/$item/"* "$target_pool_dir/$item/" 2>/dev/null || true
                    rm -rf "$CODEX_HOME/$item" 2>/dev/null
                    ln -sfn "$target_pool_dir/$item" "$CODEX_HOME/$item" 2>/dev/null || true
                else
                    rm -f "$CODEX_HOME/$item" 2>/dev/null || true
                    ln -sfn "$target_pool_dir/$item" "$CODEX_HOME/$item" 2>/dev/null || true
                fi
            done

            # history.jsonl
            [ -f "$target_pool_dir/history.jsonl" ] || touch "$target_pool_dir/history.jsonl"
            if [ -L "$CODEX_HOME/history.jsonl" ]; then
                local cur_h_link
                cur_h_link=$(readlink "$CODEX_HOME/history.jsonl" 2>/dev/null || true)
                if [ "$cur_h_link" != "$target_pool_dir/history.jsonl" ]; then
                    rm -f "$CODEX_HOME/history.jsonl"
                    ln -sf "$target_pool_dir/history.jsonl" "$CODEX_HOME/history.jsonl" 2>/dev/null || true
                fi
            elif [ -f "$CODEX_HOME/history.jsonl" ]; then
                cat "$CODEX_HOME/history.jsonl" >> "$target_pool_dir/history.jsonl" 2>/dev/null || true
                rm -f "$CODEX_HOME/history.jsonl" 2>/dev/null
                ln -sf "$target_pool_dir/history.jsonl" "$CODEX_HOME/history.jsonl" 2>/dev/null || true
            else
                rm -f "$CODEX_HOME/history.jsonl" 2>/dev/null
                ln -sf "$target_pool_dir/history.jsonl" "$CODEX_HOME/history.jsonl" 2>/dev/null || true
            fi

            # 跨 profile 共享 SQLite 状态与数据库 (state_*.sqlite, logs_*.sqlite, goals_*.sqlite, memories_*.sqlite, queue_*.sqlite, thread_history_*.sqlite)
            for db_pattern in "state_*.sqlite" "logs_*.sqlite" "goals_*.sqlite" "memories_*.sqlite" "queue_*.sqlite" "thread_history_*.sqlite"; do
                for pool_db in "$target_pool_dir"/$db_pattern; do
                    [ -f "$pool_db" ] || continue
                    local db_base
                    db_base=$(basename "$pool_db")
                    if [ ! -e "$CODEX_HOME/$db_base" ] || [ -L "$CODEX_HOME/$db_base" ]; then
                        ln -sf "$pool_db" "$CODEX_HOME/$db_base" 2>/dev/null || true
                    fi
                done
                for local_db in "$CODEX_HOME"/$db_pattern; do
                    [ -f "$local_db" ] || continue
                    [ -L "$local_db" ] && continue
                    local db_base
                    db_base=$(basename "$local_db")
                    if [ ! -f "$target_pool_dir/$db_base" ]; then
                        mv "$local_db" "$target_pool_dir/$db_base" 2>/dev/null || true
                        ln -sf "$target_pool_dir/$db_base" "$CODEX_HOME/$db_base" 2>/dev/null || true
                    fi
                done
            done
        fi
    fi

    # 针对 claude，根据 data_mode 控制项目、对话与会话共享
    if [ "$base_cli" = "claude" ]; then
        local global_shared_claude="$AI_ORIGINAL_HOME/.local/share/ai/claude/shared-data"
        mkdir -p "$global_shared_claude"/{projects,sessions,todos,file-history,shell-snapshots,backups}

        local target_pool_dir
        if [ "$data_mode" = "shared" ]; then
            target_pool_dir="$global_shared_claude"
        elif [ "$data_mode" = "group" ]; then
            target_pool_dir="$AI_ORIGINAL_HOME/.local/share/ai/claude/pools/${pool_name}"
            mkdir -p "$target_pool_dir"/{projects,sessions,todos,file-history,shell-snapshots,backups}
        fi

        if [ "$data_mode" = "isolated" ]; then
            # === 完全私有隔离模式 (Isolated Mode) ===
            for item in projects sessions todos file-history shell-snapshots backups; do
                if [ -L "$CLAUDE_CONFIG_DIR/$item" ]; then
                    rm -f "$CLAUDE_CONFIG_DIR/$item"
                fi
                mkdir -p "$CLAUDE_CONFIG_DIR/$item"
            done
            if [ -L "$CLAUDE_CONFIG_DIR/history.jsonl" ]; then
                rm -f "$CLAUDE_CONFIG_DIR/history.jsonl"
                touch "$CLAUDE_CONFIG_DIR/history.jsonl"
            else
                [ -f "$CLAUDE_CONFIG_DIR/history.jsonl" ] || touch "$CLAUDE_CONFIG_DIR/history.jsonl"
            fi
        else
            # === 共享模式 (Shared 全局 shared-data 或 Group pools/<name>) ===
            for item in projects sessions todos file-history shell-snapshots backups; do
                if [ -L "$CLAUDE_CONFIG_DIR/$item" ]; then
                    local cur_link
                    cur_link=$(readlink "$CLAUDE_CONFIG_DIR/$item" 2>/dev/null || true)
                    if [ "$cur_link" != "$target_pool_dir/$item" ]; then
                        rm -f "$CLAUDE_CONFIG_DIR/$item"
                        ln -sfn "$target_pool_dir/$item" "$CLAUDE_CONFIG_DIR/$item" 2>/dev/null || true
                    fi
                elif [ -d "$CLAUDE_CONFIG_DIR/$item" ]; then
                    cp -rn "$CLAUDE_CONFIG_DIR/$item/"* "$target_pool_dir/$item/" 2>/dev/null || true
                    rm -rf "$CLAUDE_CONFIG_DIR/$item" 2>/dev/null
                    ln -sfn "$target_pool_dir/$item" "$CLAUDE_CONFIG_DIR/$item" 2>/dev/null || true
                else
                    rm -f "$CLAUDE_CONFIG_DIR/$item" 2>/dev/null || true
                    ln -sfn "$target_pool_dir/$item" "$CLAUDE_CONFIG_DIR/$item" 2>/dev/null || true
                fi
            done

            # history.jsonl
            [ -f "$target_pool_dir/history.jsonl" ] || touch "$target_pool_dir/history.jsonl"
            if [ -L "$CLAUDE_CONFIG_DIR/history.jsonl" ]; then
                local cur_h_link
                cur_h_link=$(readlink "$CLAUDE_CONFIG_DIR/history.jsonl" 2>/dev/null || true)
                if [ "$cur_h_link" != "$target_pool_dir/history.jsonl" ]; then
                    rm -f "$CLAUDE_CONFIG_DIR/history.jsonl"
                    ln -sf "$target_pool_dir/history.jsonl" "$CLAUDE_CONFIG_DIR/history.jsonl" 2>/dev/null || true
                fi
            elif [ -f "$CLAUDE_CONFIG_DIR/history.jsonl" ]; then
                cat "$CLAUDE_CONFIG_DIR/history.jsonl" >> "$target_pool_dir/history.jsonl" 2>/dev/null || true
                rm -f "$CLAUDE_CONFIG_DIR/history.jsonl" 2>/dev/null
                ln -sf "$target_pool_dir/history.jsonl" "$CLAUDE_CONFIG_DIR/history.jsonl" 2>/dev/null || true
            else
                rm -f "$CLAUDE_CONFIG_DIR/history.jsonl" 2>/dev/null
                ln -sf "$target_pool_dir/history.jsonl" "$CLAUDE_CONFIG_DIR/history.jsonl" 2>/dev/null || true
            fi
        fi
    fi

    # 共享常用开发工具链（如 cargo, rustup, npm）及 Git / SSH / GitHub CLI 配置
    if [ "$base_cli" = "agy" ] || [ "$base_cli" = "codex" ] || [ "$base_cli" = "claude" ]; then
        for dev_dir in .cargo .rustup .npm; do
            if [ ! -e "$cli_home/$dev_dir" ]; then
                if [ -d "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/$dev_dir" ]; then
                    ln -s "$AI_ORIGINAL_HOME/.local/share/ai/agy/shared-team/$dev_dir" "$cli_home/$dev_dir" 2>/dev/null || true
                elif [ -d "$AI_ORIGINAL_HOME/$dev_dir" ]; then
                    ln -s "$AI_ORIGINAL_HOME/$dev_dir" "$cli_home/$dev_dir" 2>/dev/null || true
                fi
            fi
        done

        # 软链接 Git, SSH, GitHub CLI 配置，确保在隔离 profile 中运行开发命令与鉴权正常
        for user_config in .gitconfig .ssh; do
            if [ ! -e "$cli_home/$user_config" ] && [ -e "$AI_ORIGINAL_HOME/$user_config" ]; then
                ln -s "$AI_ORIGINAL_HOME/$user_config" "$cli_home/$user_config" 2>/dev/null || true
            fi
        done
        if [ -d "$AI_ORIGINAL_HOME/.config/gh" ] && [ ! -e "$cli_home/.config/gh" ]; then
            mkdir -p "$cli_home/.config"
            ln -s "$AI_ORIGINAL_HOME/.config/gh" "$cli_home/.config/gh" 2>/dev/null || true
        fi

        # GitHub CLI shim，以桥接系统 D-Bus / Keyring 获取 GitHub 凭据，同时保持 CLI 自身的 OAuth 隔离
        mkdir -p "$cli_home/.local/bin"
        local gh_shim="$cli_home/.local/bin/gh"
        if [ ! -f "$gh_shim" ]; then
            cat << 'EOF' > "$gh_shim"
#!/usr/bin/env bash
if [ -n "$AI_ORIGINAL_HOME" ] && command -v /usr/bin/gh >/dev/null 2>&1; then
    HOME="$AI_ORIGINAL_HOME" \
    DBUS_SESSION_BUS_ADDRESS="${ORIGINAL_DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}" \
    exec /usr/bin/gh "$@"
else
    exec gh "$@"
fi
EOF
            chmod +x "$gh_shim" 2>/dev/null || true
        fi

        # pnpm wrapper shim: 修复 Codex 等工具调用 `pnpm add -g @openai/codex` 未带 @latest 导致无法更新陷入死循环
        local pnpm_shim="$cli_home/.local/bin/pnpm"
        if [ ! -f "$pnpm_shim" ]; then
            cat << 'EOF' > "$pnpm_shim"
#!/usr/bin/env bash
# Locate real pnpm binary outside of this shim
REAL_PNPM=""
for p in /root/.local/share/pnpm/bin/pnpm $(which -a pnpm 2>/dev/null); do
    if [ -x "$p" ] && [ "$p" != "${BASH_SOURCE[0]}" ]; then
        REAL_PNPM="$p"
        break
    fi
done

if [ -z "$REAL_PNPM" ]; then
    REAL_PNPM="pnpm"
fi

ARGS=()
has_add=false
has_global=false
for arg in "$@"; do
    case "$arg" in
        add|install|i)
            has_add=true
            ARGS+=("$arg")
            ;;
        -g|--global)
            has_global=true
            ARGS+=("$arg")
            ;;
        @openai/codex|@anthropic-ai/claude-code)
            if [ "$has_add" = true ] && [ "$has_global" = true ]; then
                ARGS+=("${arg}@latest")
            else
                ARGS+=("$arg")
            fi
            ;;
        *)
            ARGS+=("$arg")
            ;;
    esac
done

exec "$REAL_PNPM" "${ARGS[@]}"
EOF
            chmod +x "$pnpm_shim" 2>/dev/null || true
        fi
        export PATH="$cli_home/.local/bin:$PATH"
    fi
}

show_env() {
    local target="${1:-$(get_current_provider)}"
    load_environment "$target"
    local orig_home="${AI_ORIGINAL_HOME:-$HOME}"
    echo -e "${BOLD}Target/Provider:${NC} $AI_ACTIVE_PROVIDER"
    echo -e "${BOLD}Auth Mode:${NC}       ${AI_AUTH_MODE:-api-key}"
    echo -e "${BOLD}HOME Profile:${NC}    ${AI_HOME_PROFILE:-default ($target)}"

    local base_cli=""
    for base in codex claude gemini aider qwen openai agy; do
        if [[ "$target" == "${base}"* ]]; then
            base_cli="$base"
            break
        fi
    done
    [ -z "$base_cli" ] && base_cli="$target"

    local raw_profile="${AI_HOME_PROFILE:-shared-team}"
    local profile_lower
    profile_lower=$(echo "$raw_profile" | tr '[:upper:]' '[:lower:]')

    local data_sharing=""
    case "$profile_lower" in
        "isolated"|"isolate"|"private"|"standalone")
            data_sharing="Isolated (private to $target)"
            ;;
        "shared"|"share"|"shared-team"|"shared-data"|"common"|"team")
            if [ "$AI_SHARE_DATA" = "false" ]; then
                data_sharing="Isolated (private to $target)"
            else
                data_sharing="Shared (global: shared-data)"
            fi
            ;;
        *)
            if [ "$profile_lower" = "$target" ]; then
                data_sharing="Isolated (private to $target)"
            else
                data_sharing="Shared (group pool: $raw_profile)"
            fi
            ;;
    esac
    echo -e "${BOLD}Data Sharing:${NC}    $data_sharing"

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
    elif [ "$base_cli" = "codex" ]; then
        local auth_dir="$orig_home/.local/share/ai/codex/auth/${target}"
        local profile_auth="$orig_home/.local/share/ai/codex/${target}/.codex/auth.json"
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

        local is_chatgpt=false
        if [ "$AI_AUTH_MODE" = "chatgpt" ] || [ "$AI_AUTH_MODE" = "oauth" ]; then
            is_chatgpt=true
        elif [ -s "$auth_file" ]; then
            local chk_mode
            chk_mode=$(python3 -c "
import json
try:
    with open('$auth_file') as f: d = json.load(f)
    if d.get('auth_mode') == 'chatgpt' or ('tokens' in d and d['tokens'].get('access_token')):
        print('chatgpt')
except Exception: pass
" 2>/dev/null)
            [ "$chk_mode" = "chatgpt" ] && is_chatgpt=true
        fi

        if [ "$is_chatgpt" = true ]; then
            if [ -n "$email" ]; then
                echo -e "${BOLD}ChatGPT Account:${NC} $email"
            elif [ -s "$auth_file" ]; then
                echo -e "${BOLD}ChatGPT Account:${NC} (authenticated)"
            else
                echo -e "${BOLD}ChatGPT Account:${NC} (not logged in - run: ai $target login)"
            fi
        else
            echo -e "${BOLD}Codex Mode:${NC}       API Key"
        fi
    elif [ "$base_cli" = "claude" ]; then
        local auth_dir="$orig_home/.local/share/ai/claude/auth/${target}"
        local profile_creds="$orig_home/.local/share/ai/claude/${target}/.claude/.credentials.json"
        local creds_file="$auth_dir/.credentials.json"
        [ ! -s "$creds_file" ] && [ -s "$profile_creds" ] && creds_file="$profile_creds"
        local profile_cfg="$orig_home/.local/share/ai/claude/${target}/.claude/.claude.json"
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

        if [ "$AI_AUTH_MODE" = "oauth" ] || [ "$AI_AUTH_MODE" = "claudeai" ] || [ -s "$creds_file" ]; then
            if [ -n "$email" ]; then
                echo -e "${BOLD}Claude Account:${NC}  $email"
            elif [ -s "$creds_file" ]; then
                echo -e "${BOLD}Claude Account:${NC}  (authenticated)"
            else
                echo -e "${BOLD}Claude Account:${NC}  (not logged in - run: ai $target login)"
            fi
        else
            echo -e "${BOLD}Claude Mode:${NC}      API Key"
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

    local base_cli=""
    for base in codex claude gemini aider qwen openai agy; do
        if [[ "$target" == "${base}"* ]]; then
            base_cli="$base"
            break
        fi
    done
    [ -z "$base_cli" ] && base_cli="$target"

    local orig_home="${AI_ORIGINAL_HOME:-$HOME}"
    local cli_home
    if [ "$base_cli" = "agy" ] || [ "$base_cli" = "codex" ] || [ "$base_cli" = "claude" ]; then
        cli_home="$orig_home/.local/share/ai/${base_cli}/${target}"
    else
        local home_profile="${custom_profile:-${AI_HOME_PROFILE:-$target}}"
        cli_home="$orig_home/.local/share/ai/${base_cli}/${home_profile}"
    fi

    info "Resetting profile for '${base_cli}' (${target}) ..."
    if [ -d "$cli_home" ]; then
        rm -rf "$cli_home"
        success "Reset complete: Removed $cli_home"
    else
        warn "Profile directory does not exist: $cli_home"
    fi

    if [ "$base_cli" = "agy" ] || [ "$base_cli" = "codex" ] || [ "$base_cli" = "claude" ]; then
        local auth_dir="$orig_home/.local/share/ai/${base_cli}/auth/$target"
        if [ -d "$auth_dir" ]; then
            info "Resetting stored credentials for ${base_cli} alias '${target}' ..."
            rm -rf "$auth_dir"
            success "Stored credentials reset: Removed $auth_dir"
        fi
    fi
}
