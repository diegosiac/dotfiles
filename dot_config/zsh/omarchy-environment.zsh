# Establish Omarchy's native Zsh environment without evaluating Bash code.
initialize_omarchy_environment() {
    local config_marker="${1:-/etc/omarchy.conf}"
    local stock_path="${2:-/usr/share/omarchy}"
    local inherited_path="${OMARCHY_PATH:-}"
    local selected_path=""

    stock_path="${stock_path%/}"
    inherited_path="${inherited_path%/}"

    # The marker authorizes an inherited dev-link path; it is never parsed.
    if [[ -f "$config_marker" && -n "$inherited_path" && "$inherited_path" != "$stock_path" && -x "$inherited_path/bin/omarchy" ]]; then
        selected_path="$inherited_path"
    elif [[ -x "$stock_path/bin/omarchy" ]]; then
        selected_path="$stock_path"
    else
        unset OMARCHY_PATH
        return 0
    fi

    typeset -gx OMARCHY_PATH="$selected_path"
    if [[ "$OMARCHY_PATH" != "$stock_path" ]]; then
        path=("$OMARCHY_PATH/bin" $path)
        export PATH
    fi
}
