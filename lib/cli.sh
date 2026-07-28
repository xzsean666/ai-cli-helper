#!/usr/bin/env bash

AI_CONFIG_DIR="${AI_CONFIG_DIR:-$HOME/.config/ai}"

run_cli() {
    local cli_name="$1"
    shift

    local cli_script="$AI_CONFIG_DIR/cli/${cli_name}.sh"

    if [ ! -f "$cli_script" ]; then
        die "CLI wrapper script not found: $cli_script"
    fi

    # Load environment for current provider
    load_environment

    # Setup isolated HOME directory
    setup_cli_home "$cli_name"

    # Execute CLI wrapper script with passed arguments
    bash "$cli_script" "$@"
}
