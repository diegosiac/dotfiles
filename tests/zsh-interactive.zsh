#!/usr/bin/env zsh
setopt NO_UNSET PIPE_FAIL

repo_root="${0:A:h:h}"
interactive_file="$repo_root/dot_config/zsh/omarchy-interactive.zsh"
tmp_root="$(mktemp -d)"
stub_bin="$tmp_root/bin"
fzf_log="$tmp_root/fzf.log"
editor_log="$tmp_root/editor.log"
multiplexer_log="$tmp_root/multiplexer.log"
mkdir -p "$stub_bin" "$tmp_root/empty-bin"
: >"$multiplexer_log"

cleanup() {
    rm -rf -- "$tmp_root"
}
trap cleanup EXIT

print -r -- '#!/bin/sh' 'exit 0' >"$stub_bin/eza"
cat >"$stub_bin/fzf" <<'STUB'
#!/bin/sh
: >"$OMARCHY_TEST_FZF_LOG"
for argument do
    printf '<%s>\n' "$argument" >>"$OMARCHY_TEST_FZF_LOG"
done
if [ "${OMARCHY_TEST_FZF_EMIT-0}" = 1 ]; then
    printf '%s\n' "$OMARCHY_TEST_FZF_OUTPUT"
fi
exit "${OMARCHY_TEST_FZF_STATUS:-0}"
STUB
cat >"$stub_bin/test-editor" <<'STUB'
#!/bin/sh
: >"$OMARCHY_TEST_EDITOR_LOG"
for argument do
    printf '<%s>\n' "$argument" >>"$OMARCHY_TEST_EDITOR_LOG"
done
exit "${OMARCHY_TEST_EDITOR_STATUS:-0}"
STUB
chmod +x "$stub_bin/eza" "$stub_bin/fzf" "$stub_bin/test-editor"

path=("$stub_bin" /usr/bin /bin)
export PATH
export OMARCHY_TEST_FZF_LOG="$fzf_log"
export OMARCHY_TEST_EDITOR_LOG="$editor_log"

source "$interactive_file"
source "$interactive_file"

failures=0
tests_run=0

report_failure() {
    print -u2 -r -- "FAIL: $1"
    failures=$((failures + 1))
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local context="$3"

    if [[ "$actual" != "$expected" ]]; then
        print -u2 -r -- "Expected: $expected"
        print -u2 -r -- "Actual:   $actual"
        report_failure "$context"
    fi
}

assert_public_name_absent() {
    local name="$1"
    local context="$2"

    if (( ${+aliases[$name]} || ${+functions[$name]} )); then
        report_failure "$context"
    fi
}

reset_fzf_stub() {
    unset OMARCHY_TEST_FZF_EMIT OMARCHY_TEST_FZF_OUTPUT OMARCHY_TEST_FZF_STATUS
    : >"$fzf_log"
}

test_listing_aliases_are_exact_and_idempotent() {
    assert_equals 'eza -lh --group-directories-first --icons=auto' "$aliases[ls]" "ls uses Omarchy's enhanced eza listing"
    assert_equals 'eza -lah --group-directories-first --icons=auto' "$aliases[l]" "l preserves the existing all-files listing with icons"
    assert_equals 'eza -lah --group-directories-first --icons=auto' "$aliases[ll]" "ll preserves the existing long all-files listing with icons"
    assert_equals 'ls -a' "$aliases[lsa]" "lsa delegates to the enhanced ls alias"
    assert_equals 'eza --tree --level=2 --long --icons --git' "$aliases[lt]" "lt uses Omarchy's bounded tree listing"
    assert_equals 'lt -a' "$aliases[lta]" "lta delegates to the bounded tree alias"
}

test_existing_alias_is_preserved_without_eza() {
    local output=""

    output="$(
        env -i \
            HOME="$tmp_root/home" \
            PATH="$tmp_root/empty-bin" \
            INTERACTIVE_FILE="$interactive_file" \
            /usr/bin/zsh -dfc '
                alias ls="existing-listing"
                source "$INTERACTIVE_FILE"
                print -r -- "$aliases[ls]"
            '
    )"

    assert_equals 'existing-listing' "$output" "an existing ls alias remains untouched when eza is unavailable"
}

test_ff_delegates_non_kitty_preview_and_arguments() {
    local expected=""
    local exit_status=0

    reset_fzf_stub
    TERM=xterm-256color ff --query 'needle with spaces' >/dev/null
    exit_status=$?

    expected='<--preview>
<bat --style=numbers --color=always {}>
<--query>
<needle with spaces>'
    assert_equals '0' "$exit_status" "ff returns fzf success"
    assert_equals "$expected" "$(<"$fzf_log")" "ff delegates the non-Kitty preview and preserves arguments"
}

test_ff_delegates_kitty_image_preview() {
    local expected=""

    reset_fzf_stub
    TERM=xterm-kitty ff >/dev/null

    expected='<--preview>
<case $(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac>'
    assert_equals "$expected" "$(<"$fzf_log")" "ff delegates Omarchy's Kitty-aware preview"
}

test_ff_propagates_fzf_failure() {
    local exit_status=0

    reset_fzf_stub
    export OMARCHY_TEST_FZF_STATUS=23
    ff >/dev/null
    exit_status=$?

    assert_equals '23' "$exit_status" "ff propagates fzf failure"
}

test_eff_opens_selected_file_with_editor() {
    local expected_fzf=""
    local expected_editor=""
    local selected_file="$tmp_root/files/file with spaces.txt"
    local exit_status=0

    reset_fzf_stub
    : >"$editor_log"
    export OMARCHY_TEST_FZF_EMIT=1
    export OMARCHY_TEST_FZF_OUTPUT="$selected_file"
    export EDITOR="$stub_bin/test-editor"
    eff --query target
    exit_status=$?

    expected_fzf='<--preview>
<bat --style=numbers --color=always {}>
<--query>
<target>'
    expected_editor="<$selected_file>"
    assert_equals '0' "$exit_status" "eff returns editor success"
    assert_equals "$expected_fzf" "$(<"$fzf_log")" "eff passes arguments through ff"
    assert_equals "$expected_editor" "$(<"$editor_log")" "eff passes one selected path to the configured editor"
}

test_eff_propagates_selection_failure_without_editor() {
    local exit_status=0

    reset_fzf_stub
    : >"$editor_log"
    export OMARCHY_TEST_FZF_STATUS=17
    export EDITOR="$stub_bin/test-editor"
    eff >/dev/null
    exit_status=$?

    assert_equals '17' "$exit_status" "eff propagates ff failure"
    assert_equals '' "$(<"$editor_log")" "eff does not launch the editor after ff failure"
}

test_eff_propagates_editor_failure() {
    local selected_file="$tmp_root/files/selected.txt"
    local exit_status=0

    reset_fzf_stub
    : >"$editor_log"
    export OMARCHY_TEST_FZF_EMIT=1
    export OMARCHY_TEST_FZF_OUTPUT="$selected_file"
    export OMARCHY_TEST_EDITOR_STATUS=29
    export EDITOR="$stub_bin/test-editor"
    eff >/dev/null
    exit_status=$?
    unset OMARCHY_TEST_EDITOR_STATUS

    assert_equals '29' "$exit_status" "eff propagates editor failure"
    assert_equals "<$selected_file>" "$(<"$editor_log")" "eff delegates the selected file before propagating editor failure"
}

test_eff_rejects_empty_selection_without_editor() {
    local exit_status=0

    reset_fzf_stub
    : >"$editor_log"
    export EDITOR="$stub_bin/test-editor"
    eff >/dev/null
    exit_status=$?

    assert_equals '1' "$exit_status" "eff rejects an empty successful selection"
    assert_equals '' "$(<"$editor_log")" "eff does not launch the editor for an empty selection"
}

test_deferred_and_replaced_helpers_are_absent() {
    local name=""

    for name in fzfbat fzfnvim compress decompress ga gd iso2sd format-drive fip dip lip rsw lsw dsw tdl tds tdlm tsl hdl hds hdlm hsl; do
        assert_public_name_absent "$name" "$name remains intentionally undefined"
    done
}

test_isolated_interactive_zshrc_loads_curated_helpers_once() {
    local runtime_home="$tmp_root/runtime-home"
    local runtime_bin="$tmp_root/runtime-bin"
    local runtime_probe="$tmp_root/runtime-probe.zsh"
    local init_log="$tmp_root/initializers.log"
    local command_name=""
    local output=""
    local expected_output=""
    local expected_initializers=""

    mkdir -p "$runtime_home/.config/zsh" "$runtime_bin"
    cp "$interactive_file" "$runtime_home/.config/zsh/omarchy-interactive.zsh"
    print -r -- '#!/bin/sh' 'exit 0' >"$runtime_bin/eza"
    chmod +x "$runtime_bin/eza"

    for command_name in carapace mise zoxide atuin starship; do
        cat >"$runtime_bin/$command_name" <<'STUB'
#!/bin/sh
printf '%s:%s\n' "${0##*/}" "$*" >>"$OMARCHY_TEST_INIT_LOG"
printf ':\n'
STUB
        chmod +x "$runtime_bin/$command_name"
    done

    for command_name in herdr tmux; do
        cat >"$runtime_bin/$command_name" <<'STUB'
#!/bin/sh
printf '%s:%s\n' "${0##*/}" "$*" >>"$OMARCHY_TEST_MULTIPLEXER_LOG"
exit 91
STUB
        chmod +x "$runtime_bin/$command_name"
    done

    cat >"$runtime_bin/atuin" <<'STUB'
#!/bin/sh
if [ "$1" = init ]; then
    printf '%s:%s\n' "${0##*/}" "$*" >>"$OMARCHY_TEST_INIT_LOG"
fi
exec /usr/bin/atuin "$@"
STUB
    chmod +x "$runtime_bin/atuin"

    cat >"$runtime_probe" <<'PROBE'
source "$DOT_ZSHRC"
print -r -- "ls=$aliases[ls]"
print -r -- "lsa=$aliases[lsa]"
print -r -- "lt=$aliases[lt]"
print -r -- "lta=$aliases[lta]"
print -r -- "ff=${+functions[ff]}"
print -r -- "eff=${+functions[eff]}"
print -r -- "loader=${+parameters[omarchy_interactive_file]}"
policy_name='TERMINAL_''MULTIPLEXER'
startup_name='start_terminal_''multiplexer_if_needed'
print -r -- "multiplexer_policy=${+parameters[$policy_name]}"
print -r -- "multiplexer_startup=${+functions[$startup_name]}"
/bin/sh -c 'printf "%s\n" "fzf_ctrl_t=$FZF_CTRL_T_COMMAND"'
print -r -- "fzf_default_t=${+parameters[FZF_DEFAULT_T_COMMAND]}"

main_tab="$(bindkey -M main '^I')"
viins_tab="$(bindkey -M viins '^I')"
main_ctrl_r="$(bindkey -M main '^R')"
viins_ctrl_r="$(bindkey -M viins '^R')"
main_ctrl_t="$(bindkey -M main '^T')"
viins_ctrl_t="$(bindkey -M viins '^T')"
site_functions_entries=("${(@M)fpath:#/usr/share/zsh/site-functions}")
print -r -- "main_tab=${main_tab##* }"
print -r -- "viins_tab=${viins_tab##* }"
print -r -- "main_ctrl_r=${main_ctrl_r##* }"
print -r -- "viins_ctrl_r=${viins_ctrl_r##* }"
print -r -- "main_ctrl_t=${main_ctrl_t##* }"
print -r -- "viins_ctrl_t=${viins_ctrl_t##* }"
print -r -- "site_functions_count=${#site_functions_entries}"

deferred_present=0
for name in fzfbat fzfnvim compress decompress ga gd iso2sd format-drive fip dip lip rsw lsw dsw tdl tds tdlm tsl hdl hds hdlm hsl; do
    if (( ${+aliases[$name]} || ${+functions[$name]} )); then
        deferred_present=1
    fi
done
print -r -- "deferred=$deferred_present"
PROBE

    output="$(
        env -i \
            HOME="$runtime_home" \
            ZDOTDIR="$runtime_home" \
            PATH="$runtime_bin:/usr/bin:/bin" \
            TERM=xterm-256color \
            DOT_ZSHRC="$repo_root/dot_zshrc" \
            OMARCHY_RUNTIME_PROBE="$runtime_probe" \
            OMARCHY_TEST_INIT_LOG="$init_log" \
            OMARCHY_TEST_MULTIPLEXER_LOG="$multiplexer_log" \
            /usr/bin/script -qefc '/usr/bin/zsh -dfi "$OMARCHY_RUNTIME_PROBE"' /dev/null
    )"
    output="${output//$'\r'/}"

    expected_output='ls=eza -lh --group-directories-first --icons=auto
lsa=ls -a
lt=eza --tree --level=2 --long --icons --git
lta=lt -a
ff=1
eff=1
loader=0
multiplexer_policy=0
multiplexer_startup=0
fzf_ctrl_t=fd --hidden --strip-cwd-prefix --exclude .git
fzf_default_t=0
main_tab=fzf-tab-complete
viins_tab=fzf-tab-complete
main_ctrl_r=atuin-search
viins_ctrl_r=atuin-search-viins
main_ctrl_t=fzf-file-widget
viins_ctrl_t=fzf-file-widget
site_functions_count=1
deferred=0'
    expected_initializers='carapace:_carapace
mise:activate zsh
zoxide:init zsh
atuin:init zsh
starship:init zsh'

    assert_equals "$expected_output" "$output" "isolated interactive Zsh exposes only the curated compatibility surface"
    assert_equals "$expected_initializers" "$(<"$init_log")" "interactive initializers each run exactly once"
    assert_equals '' "$(<"$multiplexer_log")" "interactive startup does not launch a terminal multiplexer"
}

run_test() {
    local name="$1"
    local test_function="$2"
    local failures_before="$failures"

    tests_run=$((tests_run + 1))
    "$test_function"
    if [[ "$failures" -eq "$failures_before" ]]; then
        print -r -- "PASS: $name"
    fi
}

run_test "exact listing aliases" test_listing_aliases_are_exact_and_idempotent
run_test "preserve aliases without eza" test_existing_alias_is_preserved_without_eza
run_test "ff non-Kitty delegation" test_ff_delegates_non_kitty_preview_and_arguments
run_test "ff Kitty delegation" test_ff_delegates_kitty_image_preview
run_test "ff failure propagation" test_ff_propagates_fzf_failure
run_test "eff editor delegation" test_eff_opens_selected_file_with_editor
run_test "eff selection failure propagation" test_eff_propagates_selection_failure_without_editor
run_test "eff editor failure propagation" test_eff_propagates_editor_failure
run_test "eff empty selection handling" test_eff_rejects_empty_selection_without_editor
run_test "deferred helpers remain absent" test_deferred_and_replaced_helpers_are_absent
run_test "isolated interactive Zsh load" test_isolated_interactive_zshrc_loads_curated_helpers_once

if ((failures > 0)); then
    print -u2 -r -- "$failures failures across $tests_run Zsh interactive compatibility tests."
    exit 1
fi

print -r -- "All $tests_run Zsh interactive compatibility tests passed."
