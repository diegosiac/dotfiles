# Curated native Zsh ports of low-surprise Omarchy interactive helpers.

if (( $+commands[eza] )); then
    alias ls='eza -lh --group-directories-first --icons=auto'
    alias l='eza -lah --group-directories-first --icons=auto'
    alias ll='eza -lah --group-directories-first --icons=auto'
    alias lsa='ls -a'
    alias lt='eza --tree --level=2 --long --icons --git'
    alias lta='lt -a'
fi

ff() {
    local preview='bat --style=numbers --color=always {}'

    if [[ "${TERM-}" == "xterm-kitty" ]]; then
        preview='case $(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'
    fi

    command fzf --preview "$preview" "$@"
}

eff() {
    local file

    file="$(ff "$@")" || return $?
    [[ -n "$file" ]] || return 1

    command "${EDITOR:-nvim}" "$file"
}
