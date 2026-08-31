#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/Gentleman-Programming/Gentleman.Dots.git"
REPO_URL="${NVIM_OMARCHY_REPO_URL:-$DEFAULT_REPO_URL}"
SOURCE_SUBDIR="GentlemanNvim/nvim"
DEST_DIR="dot_config/nvim"
TRANSACTION_NAME=".nvim-omarchy-sync.transaction"

invocation_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${NVIM_OMARCHY_TEST_REPO_ROOT:-}" ]]; then
  [[ "${NVIM_OMARCHY_TESTING:-}" == "1" ]] || {
    printf 'ERROR: test repository override requires NVIM_OMARCHY_TESTING=1\n' >&2
    exit 1
  }
  repo_root_input="$NVIM_OMARCHY_TEST_REPO_ROOT"
else
  repo_root_input="$(git -C "$invocation_dir" rev-parse --show-toplevel)"
fi

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

repo_root="$(realpath -e -- "$repo_root_input")"
[[ -d "$repo_root" && ! -L "$repo_root" ]] || fail "physical repository root is not a directory"

assert_relative_directory_path() {
  local relative="$1"
  local current="$repo_root"
  local component
  local -a components=()

  [[ "$relative" != /* ]] || fail "destination path must be relative"
  IFS='/' read -r -a components <<< "$relative"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != "." && "$component" != ".." ]] || fail "destination path is invalid"
    current="$current/$component"
    [[ ! -L "$current" ]] || fail "destination ancestor is a symlink: $component"
    [[ -d "$current" ]] || fail "destination ancestor is not a directory: $component"
  done
}

destination_parent_relative="$(dirname -- "$DEST_DIR")"
destination_name="$(basename -- "$DEST_DIR")"
assert_relative_directory_path "$destination_parent_relative"
destination_parent="$(realpath -e -- "$repo_root/$destination_parent_relative")"
case "$destination_parent/" in
  "$repo_root/"*) ;;
  *) fail "destination parent escapes the physical repository root" ;;
esac

destination="$destination_parent/$destination_name"
[[ ! -L "$destination" ]] || fail "destination is a symlink"
[[ ! -e "$destination" || -d "$destination" ]] || fail "destination is not a directory"

assert_relative_directory_path "vendor/gentleman-dots"
assert_relative_directory_path "vendor/omarchy-nvim"
assert_relative_directory_path "tests"

script_dir="$repo_root/vendor/gentleman-dots"
patch_file="$script_dir/nvim-omarchy.patch"
preimages_file="$script_dir/nvim-omarchy.preimages"
contract_file="$repo_root/vendor/omarchy-nvim/contract.snapshot"
test_script="$repo_root/tests/vendor-nvim-omarchy.sh"
snapshot_file="$script_dir/nvim.snapshot"
transaction_dir="$repo_root/$TRANSACTION_NAME"

[[ ! -L "$snapshot_file" ]] || fail "snapshot path is a symlink"
[[ ! -L "$transaction_dir" ]] || fail "transaction path is a symlink"

revalidate_managed_paths() {
  local current_destination_parent current_script_dir

  [[ ! -L "$repo_root/dot_config" && ! -L "$destination" ]] || {
    printf 'ERROR: managed destination path became a symlink\n' >&2
    return 1
  }
  [[ ! -L "$repo_root/vendor" && ! -L "$repo_root/vendor/gentleman-dots" && ! -L "$snapshot_file" ]] || {
    printf 'ERROR: managed snapshot path became a symlink\n' >&2
    return 1
  }
  [[ ! -L "$transaction_dir" ]] || {
    printf 'ERROR: transaction path became a symlink\n' >&2
    return 1
  }

  current_destination_parent="$(realpath -e -- "$repo_root/$destination_parent_relative")" || return 1
  current_script_dir="$(realpath -e -- "$repo_root/vendor/gentleman-dots")" || return 1
  [[ "$current_destination_parent" == "$destination_parent" ]] || {
    printf 'ERROR: destination parent changed after validation\n' >&2
    return 1
  }
  [[ "$current_script_dir" == "$script_dir" ]] || {
    printf 'ERROR: snapshot parent changed after validation\n' >&2
    return 1
  }
  case "$current_destination_parent/" in
    "$repo_root/"*) ;;
    *)
      printf 'ERROR: destination parent escaped the physical repository root\n' >&2
      return 1
      ;;
  esac
}

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

contains_symlink() {
  local root="$1"
  [[ -d "$root" ]] || return 1
  [[ -n "$(find "$root" -type l -print -quit)" ]]
}

remove_directory_safely() {
  local path="$1"
  [[ ! -L "$path" ]] || {
    printf 'ERROR: refusing to remove a symlink during transaction recovery\n' >&2
    return 1
  }
  if [[ -e "$path" ]]; then
    [[ -d "$path" ]] || {
      printf 'ERROR: transaction recovery expected a directory\n' >&2
      return 1
    }
    contains_symlink "$path" && {
      printf 'ERROR: refusing to remove a directory containing symlinks during transaction recovery\n' >&2
      return 1
    }
    rm -rf -- "$path"
  fi
}

remove_file_safely() {
  local path="$1"
  [[ ! -L "$path" ]] || {
    printf 'ERROR: refusing to remove a symlink during transaction recovery\n' >&2
    return 1
  }
  if [[ -e "$path" ]]; then
    [[ -f "$path" ]] || {
      printf 'ERROR: transaction recovery expected a regular file\n' >&2
      return 1
    }
    rm -f -- "$path"
  fi
}

validate_origin_markers() {
  local present_marker="$1"
  local absent_marker="$2"
  if [[ -f "$present_marker" && ! -e "$absent_marker" ]]; then
    printf 'present'
  elif [[ -f "$absent_marker" && ! -e "$present_marker" ]]; then
    printf 'absent'
  else
    printf 'ERROR: transaction origin markers are invalid\n' >&2
    return 1
  fi
}

restore_destination() {
  local origin
  origin="$(validate_origin_markers \
    "$transaction_dir/destination.was-present" \
    "$transaction_dir/destination.was-absent")" || return 1

  if [[ "$origin" == "present" ]]; then
    if path_exists "$transaction_dir/destination.old"; then
      [[ -d "$transaction_dir/destination.old" && ! -L "$transaction_dir/destination.old" ]] || return 1
      remove_directory_safely "$destination" || return 1
      mv -- "$transaction_dir/destination.old" "$destination"
    else
      [[ -d "$destination" && ! -L "$destination" ]] || {
        printf 'ERROR: previous destination cannot be recovered\n' >&2
        return 1
      }
    fi
  else
    remove_directory_safely "$destination" || return 1
  fi
}

restore_snapshot() {
  local origin
  origin="$(validate_origin_markers \
    "$transaction_dir/snapshot.was-present" \
    "$transaction_dir/snapshot.was-absent")" || return 1

  if [[ "$origin" == "present" ]]; then
    if path_exists "$transaction_dir/snapshot.old"; then
      [[ -f "$transaction_dir/snapshot.old" && ! -L "$transaction_dir/snapshot.old" ]] || return 1
      remove_file_safely "$snapshot_file" || return 1
      mv -- "$transaction_dir/snapshot.old" "$snapshot_file"
    else
      [[ -f "$snapshot_file" && ! -L "$snapshot_file" ]] || {
        printf 'ERROR: previous snapshot cannot be recovered\n' >&2
        return 1
      }
    fi
  else
    remove_file_safely "$snapshot_file" || return 1
  fi
}

remove_transaction_safely() {
  [[ ! -L "$transaction_dir" ]] || {
    printf 'ERROR: refusing to remove a symlinked transaction path\n' >&2
    return 1
  }
  if [[ -e "$transaction_dir" ]]; then
    [[ -d "$transaction_dir" ]] || {
      printf 'ERROR: transaction path is not a directory\n' >&2
      return 1
    }
    contains_symlink "$transaction_dir" && {
      printf 'ERROR: refusing to remove a transaction containing symlinks\n' >&2
      return 1
    }
    rm -rf -- "$transaction_dir"
  fi
}

recovered_transaction=0
recover_transaction() {
  path_exists "$transaction_dir" || return 0
  revalidate_managed_paths || return 1
  [[ -d "$transaction_dir" && ! -L "$transaction_dir" ]] || {
    printf 'ERROR: unsafe interrupted transaction path\n' >&2
    return 1
  }
  contains_symlink "$transaction_dir" && {
    printf 'ERROR: interrupted transaction contains a symlink\n' >&2
    return 1
  }

  if [[ -f "$transaction_dir/commit.complete" ]]; then
    if [[ -d "$destination" && ! -L "$destination" && -f "$snapshot_file" && ! -L "$snapshot_file" ]]; then
      remove_transaction_safely || return 1
      recovered_transaction=1
      printf 'Recovered completed Neovim sync transaction.\n'
      return 0
    fi
  fi

  if [[ ! -f "$transaction_dir/rollback.required" ]]; then
    remove_transaction_safely || return 1
    recovered_transaction=1
    printf 'Discarded incomplete Neovim sync staging.\n'
    return 0
  fi

  restore_destination || return 1
  restore_snapshot || return 1
  remove_transaction_safely || return 1
  recovered_transaction=1
  printf 'Recovered interrupted Neovim sync transaction.\n'
}

recover_transaction || fail "interrupted transaction recovery failed"
if [[ "${NVIM_OMARCHY_TESTING:-}" == "1" && "${NVIM_OMARCHY_TEST_EXIT_AFTER_RECOVERY:-}" == "1" ]]; then
  ((recovered_transaction == 1)) || fail "no interrupted transaction was recovered"
  exit 0
fi

work_dir=""
handle_exit() {
  local status=$?
  trap - EXIT INT TERM

  if ((status != 0)) && path_exists "$transaction_dir"; then
    if ! recover_transaction; then
      printf 'ERROR: automatic transaction recovery failed\n' >&2
      status=1
    fi
  fi
  [[ -n "$work_dir" ]] && rm -rf -- "$work_dir"
  exit "$status"
}

trap handle_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

require_file() {
  [[ -f "$1" && ! -L "$1" ]] || fail "required adapter artifact is missing or unsafe"
}

verify_contract() {
  local kind expected path extra actual record
  local records=0
  declare -A seen_contract=()
  local -a required_contract=(
    "version:/usr/share/omarchy/version"
    "sha256:/usr/share/omarchy/version"
    "sha256:/usr/share/omarchy-nvim/config/lazy-lock.json"
    "sha256:/usr/share/omarchy-nvim/config/lua/plugins/all-themes.lua"
    "sha256:/usr/share/omarchy-nvim/config/lua/plugins/omarchy-theme-hotreload.lua"
    "sha256:/usr/share/omarchy-nvim/config/plugin/after/transparency.lua"
    "sha256:/usr/share/omarchy-nvim/config/lua/config/remote_clipboard.lua"
  )

  while IFS=$'\t' read -r kind expected path extra; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    [[ -z "${extra:-}" ]] || fail "invalid Omarchy contract record"
    [[ -n "$expected" && -n "$path" ]] || fail "incomplete Omarchy contract record"
    record="$kind:$path"
    [[ -z "${seen_contract[$record]+x}" ]] || fail "duplicate Omarchy contract record"

    case "$kind" in
      version)
        [[ -f "$path" && ! -L "$path" ]] || fail "Omarchy version file is missing or unsafe"
        actual="$(<"$path")"
        [[ "$actual" == "$expected" ]] || fail "Omarchy version drift"
        ;;
      sha256)
        [[ -f "$path" && ! -L "$path" ]] || fail "Omarchy contract path is missing or unsafe"
        actual="$(sha256sum "$path")"
        [[ "${actual%% *}" == "$expected" ]] || fail "Omarchy contract drift: $path"
        ;;
      *) fail "unknown Omarchy contract record type" ;;
    esac

    seen_contract["$record"]=1
    records=$((records + 1))
  done < "$contract_file"

  ((records == ${#required_contract[@]})) || fail "Omarchy contract snapshot has an unexpected record count"
  for record in "${required_contract[@]}"; do
    [[ -n "${seen_contract[$record]+x}" ]] || fail "Omarchy contract snapshot is incomplete"
  done
}

verify_preimages() {
  local tree="$1"
  local kind expected path extra actual patch_path
  local records=0
  declare -A manifest_paths=()
  local -a patch_paths=()

  while IFS=$'\t' read -r kind expected path extra; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    [[ -z "${extra:-}" ]] || fail "invalid preimage record"
    [[ -n "$expected" && -n "$path" ]] || fail "incomplete preimage record"
    [[ -z "${manifest_paths[$path]+x}" ]] || fail "duplicate preimage path"

    case "$kind" in
      sha256)
        [[ -f "$tree/$path" && ! -L "$tree/$path" ]] || fail "upstream preimage is missing: $path"
        actual="$(sha256sum "$tree/$path")"
        [[ "${actual%% *}" == "$expected" ]] || fail "upstream preimage drift: $path"
        ;;
      absent)
        [[ "$expected" == "-" ]] || fail "absent preimage has an invalid digest"
        [[ ! -e "$tree/$path" && ! -L "$tree/$path" ]] || fail "expected upstream path to be absent: $path"
        ;;
      *) fail "unknown preimage record type" ;;
    esac

    manifest_paths["$path"]="$kind"
    records=$((records + 1))
  done < "$preimages_file"

  mapfile -t patch_paths < <(
    awk '/^diff --git a\// { path=$4; sub(/^b\//, "", path); print path }' "$patch_file"
  )
  ((${#patch_paths[@]} > 0)) || fail "adapter patch contains no file changes"
  ((${#patch_paths[@]} == records)) || fail "preimage manifest does not exactly cover adapter paths"
  for patch_path in "${patch_paths[@]}"; do
    [[ -n "${manifest_paths[$patch_path]+x}" ]] || fail "adapter path has no preimage record: $patch_path"
  done
}

move_with_test_fault() {
  local source="$1"
  local target="$2"
  local point="$3"
  revalidate_managed_paths
  mv -- "$source" "$target"

  if [[ "${NVIM_OMARCHY_TESTING:-}" == "1" && "${NVIM_OMARCHY_TEST_FAULT:-}" == "$point" ]]; then
    return 97
  fi
  if [[ "${NVIM_OMARCHY_TESTING:-}" == "1" && "${NVIM_OMARCHY_TEST_FAULT:-}" == "interrupt-$point" ]]; then
    kill -KILL "$BASHPID"
  fi
}

for required in "$patch_file" "$preimages_file" "$contract_file" "$test_script"; do
  require_file "$required"
done

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gentleman-dots-nvim.XXXXXX")"
clone_dir="$work_dir/upstream"
adapted_tree="$work_dir/adapted"

git clone --quiet --depth 1 -- "$REPO_URL" "$clone_dir"
upstream_commit="$(git -C "$clone_dir" rev-parse HEAD)"
upstream_committed_at="$(git -C "$clone_dir" show -s --format=%cI HEAD)"
raw_tree="$clone_dir/$SOURCE_SUBDIR"
[[ -d "$raw_tree" && ! -L "$raw_tree" ]] || fail "upstream Neovim subtree is missing or unsafe"

verify_preimages "$raw_tree"
verify_contract

mkdir -- "$adapted_tree"
cp -a -- "$raw_tree/." "$adapted_tree/"
contains_symlink "$adapted_tree" && fail "adapted upstream tree contains a symlink"
git -C "$adapted_tree" apply --check "$patch_file"
git -C "$adapted_tree" apply "$patch_file"
contains_symlink "$adapted_tree" && fail "adapted Neovim tree contains a symlink"
bash "$test_script" "$adapted_tree"

adapter_sha256="$(sha256sum "$patch_file")"
adapter_sha256="${adapter_sha256%% *}"
preimages_sha256="$(sha256sum "$preimages_file")"
preimages_sha256="${preimages_sha256%% *}"
omarchy_contract_sha256="$(sha256sum "$contract_file")"
omarchy_contract_sha256="${omarchy_contract_sha256%% *}"

[[ ! -e "$transaction_dir" && ! -L "$transaction_dir" ]] || fail "transaction path became occupied"
revalidate_managed_paths || fail "managed paths changed before transaction creation"
mkdir -- "$transaction_dir"
mkdir -- "$transaction_dir/destination.new"
cp -a -- "$adapted_tree/." "$transaction_dir/destination.new/"
contains_symlink "$transaction_dir/destination.new" && fail "replacement tree contains a symlink"

{
  printf 'repo=%s\n' "$REPO_URL"
  printf 'source_path=%s\n' "$SOURCE_SUBDIR"
  printf 'destination_path=%s\n' "$DEST_DIR"
  printf 'commit=%s\n' "$upstream_commit"
  printf 'upstream_committed_at=%s\n' "$upstream_committed_at"
  printf 'adapter_sha256=%s\n' "$adapter_sha256"
  printf 'preimages_sha256=%s\n' "$preimages_sha256"
  printf 'omarchy_contract_sha256=%s\n' "$omarchy_contract_sha256"
} > "$transaction_dir/snapshot.new"

if path_exists "$destination"; then
  [[ -d "$destination" && ! -L "$destination" ]] || fail "destination became unsafe"
  contains_symlink "$destination" && fail "destination contains a symlink"
  : > "$transaction_dir/destination.was-present"
else
  : > "$transaction_dir/destination.was-absent"
fi

if path_exists "$snapshot_file"; then
  [[ -f "$snapshot_file" && ! -L "$snapshot_file" ]] || fail "snapshot became unsafe"
  : > "$transaction_dir/snapshot.was-present"
else
  : > "$transaction_dir/snapshot.was-absent"
fi

: > "$transaction_dir/rollback.required"

if [[ -f "$transaction_dir/destination.was-present" ]]; then
  move_with_test_fault "$destination" "$transaction_dir/destination.old" "destination-backup"
fi
if [[ -f "$transaction_dir/snapshot.was-present" ]]; then
  move_with_test_fault "$snapshot_file" "$transaction_dir/snapshot.old" "snapshot-backup"
fi

move_with_test_fault "$transaction_dir/destination.new" "$destination" "destination-install"
move_with_test_fault "$transaction_dir/snapshot.new" "$snapshot_file" "snapshot-install"
: > "$transaction_dir/commit.complete"
if [[ "${NVIM_OMARCHY_TESTING:-}" == "1" && "${NVIM_OMARCHY_TEST_FAULT:-}" == "interrupt-commit-complete" ]]; then
  kill -KILL "$BASHPID"
fi
remove_transaction_safely

printf 'PASS: Omarchy Neovim vendor sync\n'
printf 'Commit: %s\n' "$upstream_commit"
printf 'Destination: %s\n' "$DEST_DIR"
printf 'Review: git diff -- %s vendor/gentleman-dots/nvim.snapshot\n' "$DEST_DIR"
