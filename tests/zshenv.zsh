#!/usr/bin/env zsh
setopt NO_UNSET PIPE_FAIL

repo_root="${0:A:h:h}"
environment_file="$repo_root/dot_config/zsh/omarchy-environment.zsh"
source "$environment_file"

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

make_omarchy_root() {
    local root="$1"

    mkdir -p "$root/bin"
    print -r -- '#!/usr/bin/env zsh' 'print -r -- test-omarchy' >"$root/bin/omarchy"
    chmod +x "$root/bin/omarchy"
}

path_entry_count() {
    local needle="$1"
    local entry=""
    local count=0

    for entry in $path; do
        [[ "$entry" == "$needle" ]] && count=$((count + 1))
    done

    print -r -- "$count"
}

test_stock_forces_default_without_marker() {
    local tmp="$(mktemp -d)"
    local config_marker="$tmp/missing-omarchy.conf"
    local stock_path="$tmp/stock"
    local stale_path="$tmp/stale-dev"
    local original_path="$tmp/system-bin:/usr/bin"

    make_omarchy_root "$stock_path"
    make_omarchy_root "$stale_path"
    typeset -gU path PATH
    path=("$tmp/system-bin" "/usr/bin")
    typeset -gx OMARCHY_PATH="$stale_path"

    initialize_omarchy_environment "$config_marker" "$stock_path"

    assert_equals "$stock_path" "$OMARCHY_PATH" "stock Omarchy replaces stale inherited override"
    assert_equals "0" "$(path_entry_count "$stock_path/bin")" "stock Omarchy command path is not injected"
    assert_equals "$original_path" "$PATH" "stock Omarchy preserves the system PATH"
    rm -rf -- "$tmp"
}

test_valid_dev_override_is_preserved_with_marker() {
    local tmp="$(mktemp -d)"
    local config_marker="$tmp/omarchy.conf"
    local stock_path="$tmp/stock"
    local override_path="$tmp/dev"

    make_omarchy_root "$stock_path"
    make_omarchy_root "$override_path"
    touch "$config_marker"
    typeset -gU path PATH
    path=("$tmp/system-bin" "/usr/bin")
    typeset -gx OMARCHY_PATH="$override_path"

    initialize_omarchy_environment "$config_marker" "$stock_path"

    assert_equals "$override_path" "$OMARCHY_PATH" "valid inherited dev override is preserved with marker"
    assert_equals "$override_path/bin/omarchy" "$(whence -p omarchy)" "dev Omarchy command resolves"
    rm -rf -- "$tmp"
}

test_dev_command_path_is_deduplicated() {
    local tmp="$(mktemp -d)"
    local config_marker="$tmp/omarchy.conf"
    local stock_path="$tmp/stock"
    local override_path="$tmp/dev"

    make_omarchy_root "$stock_path"
    make_omarchy_root "$override_path"
    touch "$config_marker"
    typeset -gU path PATH
    path=("$override_path/bin" "$tmp/system-bin" "/usr/bin")
    typeset -gx OMARCHY_PATH="$override_path"

    initialize_omarchy_environment "$config_marker" "$stock_path"
    initialize_omarchy_environment "$config_marker" "$stock_path"

    assert_equals "1" "$(path_entry_count "$override_path/bin")" "dev Omarchy command path appears exactly once"
    rm -rf -- "$tmp"
}

test_invalid_dev_override_falls_back_to_stock() {
    local tmp="$(mktemp -d)"
    local config_marker="$tmp/omarchy.conf"
    local stock_path="$tmp/stock"
    local original_path="$tmp/system-bin:/usr/bin"

    make_omarchy_root "$stock_path"
    touch "$config_marker"
    typeset -gU path PATH
    path=("$tmp/system-bin" "/usr/bin")
    typeset -gx OMARCHY_PATH="$tmp/missing-dev"

    initialize_omarchy_environment "$config_marker" "$stock_path"

    assert_equals "$stock_path" "$OMARCHY_PATH" "invalid inherited dev override falls back to stock Omarchy"
    assert_equals "0" "$(path_entry_count "$stock_path/bin")" "stock fallback command path is not injected"
    assert_equals "$original_path" "$PATH" "stock fallback preserves the system PATH"
    rm -rf -- "$tmp"
}

test_non_omarchy_environment_is_unchanged() {
    local tmp="$(mktemp -d)"
    local original_path="$tmp/system-bin:$tmp/tools-bin:/usr/bin"

    typeset -gU path PATH
    path=("$tmp/system-bin" "$tmp/tools-bin" "/usr/bin")
    typeset -gx OMARCHY_PATH="$tmp/missing-dev"

    initialize_omarchy_environment "$tmp/missing-omarchy.conf" "$tmp/missing-stock"

    assert_equals "<unset>" "${OMARCHY_PATH-<unset>}" "non-Omarchy environment leaves OMARCHY_PATH unset"
    assert_equals "$original_path" "$PATH" "non-Omarchy environment preserves PATH"
    rm -rf -- "$tmp"
}

test_zshenv_preserves_existing_session_defaults() {
    local tmp="$(mktemp -d)"
    local home="$tmp/home"
    local output=""
    local expected=""

    mkdir -p "$home/.config/zsh"
    cp "$environment_file" "$home/.config/zsh/omarchy-environment.zsh"

    output="$(
        env -i \
            HOME="$home" \
            PATH="/usr/bin:/bin" \
            DOT_ZSHENV="$repo_root/dot_zshenv" \
            /usr/bin/zsh -dfc '
                PATH="/usr/bin:/bin"
                source "$DOT_ZSHENV"
                print -r -- "PATH=$PATH"
                print -r -- "EDITOR=$EDITOR"
                print -r -- "VISUAL=$VISUAL"
            '
    )"

    expected="PATH=$home/.local/bin:$home/go/bin:/usr/bin:/bin
EDITOR=nvim
VISUAL=nvim"
    assert_equals "$expected" "$output" "dot_zshenv preserves path and editor defaults"
    rm -rf -- "$tmp"
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

run_test "stock forces default without marker" test_stock_forces_default_without_marker
run_test "valid dev override with marker" test_valid_dev_override_is_preserved_with_marker
run_test "dev command path deduplication" test_dev_command_path_is_deduplicated
run_test "invalid dev override stock fallback" test_invalid_dev_override_falls_back_to_stock
run_test "non-Omarchy fallback" test_non_omarchy_environment_is_unchanged
run_test "existing zshenv defaults" test_zshenv_preserves_existing_session_defaults

if ((failures > 0)); then
    print -u2 -r -- "$failures of $tests_run Zsh environment tests failed."
    exit 1
fi

print -r -- "All $tests_run Zsh environment tests passed."
