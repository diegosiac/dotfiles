#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
sync_script="$repo_root/vendor/gentleman-dots/sync-nvim.sh"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/nvim-sync-test.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

mkdir -p -- "$sandbox/tmp"
git clone --quiet --depth 1 \
  "https://github.com/Gentleman-Programming/Gentleman.Dots.git" \
  "$sandbox/upstream"
upstream_url="file://$sandbox/upstream"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

rollback_sentinel_file="$sandbox/rollback-sentinel.expected"
printf 'pre-transaction destination sentinel\n' > "$rollback_sentinel_file"

directory_hash() {
  local directory="$1"
  [[ -d "$directory" && ! -L "$directory" ]] || return 1
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -cf - -C "$directory" . | sha256sum | cut -d' ' -f1
}

tree_hash() {
  directory_hash "$1/dot_config/nvim"
}

snapshot_hash() {
  sha256sum "$1/vendor/gentleman-dots/nvim.snapshot" | cut -d' ' -f1
}

create_fixture() {
  local name="$1"
  local root="$sandbox/$name"

  mkdir -p -- \
    "$root/dot_config" \
    "$root/vendor/gentleman-dots" \
    "$root/vendor/omarchy-nvim" \
    "$root/tests"
  cp -a -- "$repo_root/dot_config/nvim" "$root/dot_config/nvim"
  cp -a -- \
    "$repo_root/vendor/gentleman-dots/nvim-omarchy.patch" \
    "$repo_root/vendor/gentleman-dots/nvim-omarchy.preimages" \
    "$repo_root/vendor/gentleman-dots/nvim.snapshot" \
    "$root/vendor/gentleman-dots/"
  cp -a -- "$repo_root/vendor/omarchy-nvim/contract.snapshot" "$root/vendor/omarchy-nvim/"
  cp -a -- \
    "$repo_root/tests/vendor-nvim-omarchy.sh" \
    "$repo_root/tests/nvim-nodejs.sh" \
    "$repo_root/tests/nvim-nodejs.lua" \
    "$root/tests/"

  printf '%s\n' "$root"
}

replacement_tree_hash="$(tree_hash "$repo_root")"

create_rollback_fixture() {
  local name="$1"
  local root
  root="$(create_fixture "$name")"

  rm -rf -- "$root/dot_config/nvim"
  mkdir -p -- "$root/dot_config/nvim/nested"
  cp -- "$rollback_sentinel_file" "$root/dot_config/nvim/rollback-sentinel.txt"
  printf 'nested pre-transaction bytes\n' > "$root/dot_config/nvim/nested/state.txt"
  [[ "$(tree_hash "$root")" != "$replacement_tree_hash" ]] \
    || fail "rollback fixture matches the replacement tree: $name"

  printf '%s\n' "$root"
}

run_sync() {
  local root="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local fault="${4:-}"
  local script="${5:-$sync_script}"

  NVIM_OMARCHY_TESTING=1 \
  NVIM_OMARCHY_TEST_REPO_ROOT="$root" \
  NVIM_OMARCHY_REPO_URL="$upstream_url" \
  NVIM_OMARCHY_TEST_FAULT="$fault" \
  TMPDIR="$sandbox/tmp" \
    bash "$script" > "$stdout_file" 2> "$stderr_file"
}

run_recovery() {
  local root="$1"
  local stdout_file="$2"
  local stderr_file="$3"

  NVIM_OMARCHY_TESTING=1 \
  NVIM_OMARCHY_TEST_REPO_ROOT="$root" \
  NVIM_OMARCHY_REPO_URL="$upstream_url" \
  NVIM_OMARCHY_TEST_EXIT_AFTER_RECOVERY=1 \
  TMPDIR="$sandbox/tmp" \
    bash "$sync_script" > "$stdout_file" 2> "$stderr_file"
}

assert_destination_restored() {
  local root="$1"
  local expected_tree="$2"
  local context="$3"

  cmp -s -- "$rollback_sentinel_file" "$root/dot_config/nvim/rollback-sentinel.txt" \
    || fail "destination sentinel bytes were not restored: $context"
  [[ "$(tree_hash "$root")" == "$expected_tree" ]] \
    || fail "destination tree was not restored exactly: $context"
}

assert_failed_unchanged() {
  local root="$1"
  local fault="$2"
  local old_tree old_snapshot status

  old_tree="$(tree_hash "$root")"
  old_snapshot="$(snapshot_hash "$root")"
  assert_destination_restored "$root" "$old_tree" "fixture setup for $fault"
  if run_sync "$root" "$sandbox/stdout" "$sandbox/stderr" "$fault"; then
    status=0
  else
    status=$?
  fi

  ((status != 0)) || fail "fault injection unexpectedly succeeded: $fault"
  assert_destination_restored "$root" "$old_tree" "$fault"
  [[ "$(snapshot_hash "$root")" == "$old_snapshot" ]] || fail "snapshot changed after fault: $fault"
  [[ ! -e "$root/.nvim-omarchy-sync.transaction" && ! -L "$root/.nvim-omarchy-sync.transaction" ]] \
    || fail "transaction remained after recoverable fault: $fault"
}

assert_interrupted_recovers() {
  local point="$1"
  local root old_tree old_snapshot
  root="$(create_rollback_fixture "interrupt-$point")"
  old_tree="$(tree_hash "$root")"
  old_snapshot="$(snapshot_hash "$root")"

  if run_sync \
    "$root" \
    "$sandbox/interrupt-$point.stdout" \
    "$sandbox/interrupt-$point.stderr" \
    "interrupt-$point" \
    2> "$sandbox/interrupt-$point-shell.stderr"; then
    fail "hard-interruption injection unexpectedly succeeded: $point"
  fi
  [[ -d "$root/.nvim-omarchy-sync.transaction" ]] \
    || fail "hard interruption did not leave a recoverable transaction: $point"

  run_recovery \
    "$root" \
    "$sandbox/recovery-$point.stdout" \
    "$sandbox/recovery-$point.stderr"
  assert_destination_restored "$root" "$old_tree" "startup recovery after $point"
  [[ "$(snapshot_hash "$root")" == "$old_snapshot" ]] \
    || fail "startup recovery did not restore the snapshot: $point"
  [[ ! -e "$root/.nvim-omarchy-sync.transaction" ]] \
    || fail "startup recovery left the transaction behind: $point"
  printf 'Recovered interrupted Neovim sync transaction.\n' > "$sandbox/recovery-$point.expected"
  cmp -s -- "$sandbox/recovery-$point.expected" "$sandbox/recovery-$point.stdout" \
    || fail "startup recovery stdout was unexpected: $point"
  [[ ! -s "$sandbox/recovery-$point.stderr" ]] \
    || fail "startup recovery emitted stderr: $point"
}

symlink_root="$(create_fixture symlink-escape)"
external="$sandbox/external-parent"
mkdir -p -- "$external/nested"
printf 'external sentinel\n' > "$external/sentinel"
printf 'nested external bytes\n' > "$external/nested/state"
external_tree_hash="$(directory_hash "$external")"
rm -rf -- "$symlink_root/dot_config"
ln -s -- "$external" "$symlink_root/dot_config"
if run_sync "$symlink_root" "$sandbox/symlink.stdout" "$sandbox/symlink.stderr"; then
  fail "symlinked destination parent was accepted"
fi
[[ "$(directory_hash "$external")" == "$external_tree_hash" ]] \
  || fail "external directory tree changed during symlink rejection"
printf 'PASS: symlinked destination parent is rejected without external mutation\n'

destination_symlink_root="$(create_fixture destination-symlink)"
external_destination="$sandbox/external-destination"
mkdir -p -- "$external_destination/nested"
printf 'destination sentinel\n' > "$external_destination/sentinel"
printf 'nested destination bytes\n' > "$external_destination/nested/state"
external_destination_tree_hash="$(directory_hash "$external_destination")"
rm -rf -- "$destination_symlink_root/dot_config/nvim"
ln -s -- "$external_destination" "$destination_symlink_root/dot_config/nvim"
if run_sync "$destination_symlink_root" "$sandbox/destination-symlink.stdout" "$sandbox/destination-symlink.stderr"; then
  fail "symlinked destination was accepted"
fi
[[ "$(directory_hash "$external_destination")" == "$external_destination_tree_hash" ]] \
  || fail "external destination tree changed during symlink rejection"
printf 'PASS: symlinked destination is rejected without external mutation\n'

for point in destination-backup snapshot-backup destination-install snapshot-install; do
  reported_fault_root="$(create_rollback_fixture "reported-$point")"
  assert_failed_unchanged "$reported_fault_root" "$point"
  printf 'PASS: reported %s failure restores exact destination and snapshot bytes\n' "$point"
done

for point in destination-backup snapshot-backup destination-install snapshot-install; do
  assert_interrupted_recovers "$point"
  printf 'PASS: next-run recovery restores exact bytes after %s interruption\n' "$point"
done

committed_root="$(create_rollback_fixture commit-complete)"
committed_old_tree="$(tree_hash "$committed_root")"
if run_sync \
  "$committed_root" \
  "$sandbox/commit-complete.stdout" \
  "$sandbox/commit-complete.stderr" \
  "interrupt-commit-complete" \
  2> "$sandbox/commit-complete-shell.stderr"; then
  fail "post-commit hard-interruption injection unexpectedly succeeded"
fi
transaction_dir="$committed_root/.nvim-omarchy-sync.transaction"
[[ -f "$transaction_dir/commit.complete" ]] \
  || fail "post-commit interruption did not retain the commit marker"
[[ "$(directory_hash "$transaction_dir/destination.old")" == "$committed_old_tree" ]] \
  || fail "post-commit transaction did not retain exact previous destination bytes"
committed_tree="$(tree_hash "$committed_root")"
committed_snapshot="$(snapshot_hash "$committed_root")"
[[ "$committed_tree" == "$replacement_tree_hash" ]] \
  || fail "post-commit interruption did not leave the replacement destination installed"
[[ "$committed_tree" != "$committed_old_tree" ]] \
  || fail "post-commit fixture cannot distinguish old and replacement destinations"
run_recovery "$committed_root" "$sandbox/commit-recovery.stdout" "$sandbox/commit-recovery.stderr"
[[ "$(tree_hash "$committed_root")" == "$committed_tree" ]] \
  || fail "completed-transaction recovery changed the committed destination"
[[ "$(snapshot_hash "$committed_root")" == "$committed_snapshot" ]] \
  || fail "completed-transaction recovery changed the committed snapshot"
[[ ! -e "$transaction_dir" ]] || fail "completed-transaction recovery left the transaction behind"
printf 'Recovered completed Neovim sync transaction.\n' > "$sandbox/commit-recovery.expected"
cmp -s -- "$sandbox/commit-recovery.expected" "$sandbox/commit-recovery.stdout" \
  || fail "completed-transaction recovery stdout was unexpected"
[[ ! -s "$sandbox/commit-recovery.stderr" ]] \
  || fail "completed-transaction recovery emitted stderr"
printf 'PASS: next-run recovery finalizes a hard interruption after commit completion\n'

mutant_script="$sandbox/sync-nvim-discard-destination-old.sh"
python3 - "$sync_script" "$mutant_script" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
needle = '      mv -- "$transaction_dir/destination.old" "$destination"\n'
replacement = '      remove_directory_safely "$transaction_dir/destination.old"\n'
if source.count(needle) != 1:
    raise SystemExit("destination rollback mutation target was not unique")
Path(sys.argv[2]).write_text(source.replace(needle, replacement))
PY
mutation_root="$(create_rollback_fixture rollback-mutation)"
mutation_tree="$(tree_hash "$mutation_root")"
if run_sync \
  "$mutation_root" \
  "$sandbox/mutation.stdout" \
  "$sandbox/mutation.stderr" \
  "destination-install" \
  "$mutant_script"; then
  fail "rollback mutation unexpectedly completed the sync"
fi
if (assert_destination_restored "$mutation_root" "$mutation_tree" "discard-destination.old mutation") \
  > "$sandbox/mutation-assertion.stdout" 2> "$sandbox/mutation-assertion.stderr"; then
  fail "corrected rollback assertion accepted a discarded destination.old"
fi
printf 'PASS: corrected rollback assertion rejects a destination.old-discarding mutant\n'

lock_drift_root="$(create_fixture lock-drift)"
lock_tree="$(tree_hash "$lock_drift_root")"
lock_snapshot="$(snapshot_hash "$lock_drift_root")"
python3 - "$lock_drift_root/vendor/omarchy-nvim/contract.snapshot" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
for index, line in enumerate(lines):
    if line.endswith("\t/usr/share/omarchy-nvim/config/lazy-lock.json"):
        fields = line.split("\t")
        fields[1] = "0" * 64
        lines[index] = "\t".join(fields)
        break
else:
    raise SystemExit("lazy-lock contract record not found")
path.write_text("\n".join(lines) + "\n")
PY
if run_sync "$lock_drift_root" "$sandbox/lock.stdout" "$sandbox/lock.stderr"; then
  fail "installed lock-only drift unexpectedly succeeded"
fi
[[ "$(tree_hash "$lock_drift_root")" == "$lock_tree" ]] || fail "lock drift changed the destination"
[[ "$(snapshot_hash "$lock_drift_root")" == "$lock_snapshot" ]] || fail "lock drift changed the snapshot"
[[ ! -e "$lock_drift_root/.nvim-omarchy-sync.transaction" ]] || fail "lock drift created a transaction"
printf 'PASS: installed lock-only drift fails before mutation\n'

preimage_root="$(create_fixture preimage-drift)"
preimage_tree="$(tree_hash "$preimage_root")"
preimage_snapshot="$(snapshot_hash "$preimage_root")"
python3 - "$preimage_root/vendor/gentleman-dots/nvim-omarchy.preimages" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = text.split("\t", 2)[1]
path.write_text(text.replace(old, "0" * 64, 1))
PY
if run_sync "$preimage_root" "$sandbox/preimage.stdout" "$sandbox/preimage.stderr"; then
  fail "preimage drift unexpectedly succeeded"
fi
[[ "$(tree_hash "$preimage_root")" == "$preimage_tree" ]] || fail "preimage drift changed the destination"
[[ "$(snapshot_hash "$preimage_root")" == "$preimage_snapshot" ]] || fail "preimage drift changed the snapshot"
[[ ! -e "$preimage_root/.nvim-omarchy-sync.transaction" ]] || fail "preimage drift created a transaction"
printf 'PASS: upstream preimage drift fails before mutation\n'

deterministic_root="$(create_fixture deterministic)"
run_sync "$deterministic_root" "$sandbox/run-1.stdout" "$sandbox/run-1.stderr"
tree_1="$(tree_hash "$deterministic_root")"
snapshot_1="$(snapshot_hash "$deterministic_root")"
run_sync "$deterministic_root" "$sandbox/run-2.stdout" "$sandbox/run-2.stderr"
tree_2="$(tree_hash "$deterministic_root")"
snapshot_2="$(snapshot_hash "$deterministic_root")"
cmp -s -- "$sandbox/run-1.stdout" "$sandbox/run-2.stdout" || fail "identical sync stdout differs"
cmp -s -- "$sandbox/run-1.stderr" "$sandbox/run-2.stderr" || fail "identical sync stderr differs"
[[ "$tree_1" == "$tree_2" ]] || fail "identical sync tree hashes differ"
[[ "$snapshot_1" == "$snapshot_2" ]] || fail "identical sync snapshot hashes differ"
printf 'PASS: isolated repeated sync output and artifacts are byte-identical\n'

printf 'PASS: Omarchy Neovim sync safety regressions\n'
