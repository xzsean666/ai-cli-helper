#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai}"

run_cli() {
    local target_cmd="$1"
    shift

    # 1. 查找是否存在精准匹配的 cli wrapper（例如 cli/codexa.sh）
    local cli_script="$AI_CONFIG_DIR/cli/${target_cmd}.sh"

    if [ ! -f "$cli_script" ]; then
        # 2. 尝试模糊匹配底层真实的 CLI 类型（例如 codexa -> codex）
        local matched_cli=""
        for base in codex claude gemini aider qwen openai; do
            if [[ "$target_cmd" == "${base}"* ]]; then
                matched_cli="$base"
                break
            fi
        done

        if [ -n "$matched_cli" ] && [ -f "$AI_CONFIG_DIR/cli/${matched_cli}.sh" ]; then
            cli_script="$AI_CONFIG_DIR/cli/${matched_cli}.sh"
        else
            die "No suitable CLI wrapper found for '$target_cmd'"
        fi
    fi

    # 根据命令别名（如 codexa）自动加载对应环境（若存在 providers/codexa.sh 优先加载，否则使用 active provider）
    load_environment "$target_cmd"

    # 为该别名创建独立隔离的 HOME
    setup_cli_home "$target_cmd"

    # 执行对应 CLI
    bash "$cli_script" "$@"
}
