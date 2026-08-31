#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
module_path="${1:-$repo_root/dot_config/nvim/lua/config/nodejs.lua}"
harness="$repo_root/tests/nvim-nodejs.lua"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/nvim-nodejs-test.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT

home="$fixture/home"
fake_bin="$fixture/fake-bin"
active_install="$fixture/active-node"
inactive_install="$fixture/inactive-node"
project_a="$fixture/project-a"
project_b="$fixture/project-b"
json_file="$fixture/mise-node.json"
cwd_log="$fixture/mise-cwd.log"

mkdir -p -- \
  "$home" \
  "$fake_bin" \
  "$active_install/bin" \
  "$inactive_install/bin" \
  "$project_a" \
  "$project_b" \
  "$fixture/xdg/config" \
  "$fixture/xdg/data" \
  "$fixture/xdg/state" \
  "$fixture/xdg/cache"

cat > "$fake_bin/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "ls --global --installed --json node" ]]
printf '%s\n' "$PWD" > "$MISE_CWD_LOG"
command cat -- "$MISE_NODE_JSON_FILE"
EOF

cat > "$active_install/bin/node" <<'EOF'
#!/usr/bin/env bash
printf 'v22.14.0\n'
EOF

cat > "$active_install/bin/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$active_install/bin/neovim-node-host" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$inactive_install/bin/node" <<'EOF'
#!/usr/bin/env bash
printf 'v20.0.0\n'
EOF

chmod +x -- \
  "$fake_bin/mise" \
  "$active_install/bin/node" \
  "$active_install/bin/npm" \
  "$active_install/bin/neovim-node-host" \
  "$inactive_install/bin/node"

python3 - "$json_file" "$active_install" "$inactive_install" <<'PY'
import json
import sys

path, active, inactive = sys.argv[1:]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        [
            {"installed": True, "active": False, "install_path": inactive},
            {"installed": True, "active": True, "install_path": active},
        ],
        handle,
    )
PY

run_harness() {
  local cwd="$1"
  local scenario="$2"
  local initial_path="$active_install/bin:$fake_bin:/usr/bin:$active_install/bin"

  HOME="$home" \
  XDG_CONFIG_HOME="$fixture/xdg/config" \
  XDG_DATA_HOME="$fixture/xdg/data" \
  XDG_STATE_HOME="$fixture/xdg/state" \
  XDG_CACHE_HOME="$fixture/xdg/cache" \
  PATH="$initial_path" \
  MISE_NODE_JSON_FILE="$json_file" \
  MISE_CWD_LOG="$cwd_log" \
  NODEJS_MODULE="$module_path" \
  NODEJS_ACTIVE_INSTALL="$active_install" \
  NODEJS_SCENARIO="$scenario" \
    nvim --headless --clean -u NONE -i NONE --noplugin -l "$harness"

  [[ "$(<"$cwd_log")" == "$home" ]]
}

(
  cd -- "$project_a"
  run_harness "$project_a" "provider-present"
)
(
  cd -- "$project_b"
  run_harness "$project_b" "provider-present"
)

rm -- "$active_install/bin/neovim-node-host"
(
  cd -- "$project_a"
  run_harness "$project_a" "provider-missing"
)

printf 'PASS: global Mise Node.js provider harnesses\n'
