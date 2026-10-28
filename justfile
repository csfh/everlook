set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
# Machine-specific settings, such as EVERLOOK_ADDONS_DIR for `just sync`.
set dotenv-filename := ".env.local"

# List the recipes
default:
    @just --list --unsorted

# Every check: the addon, the scripts, the harness and the site
test: test-addon test-scripts test-harness test-www

# The addon's tests in addon/tests: the Lua suite, and the folder and luac checks
test-addon:
    lua5.1 addon/tests/run.lua
    python3 -m unittest discover --quiet --start-directory addon/tests --pattern '*_test.py'

# Each script's test, beside it in scripts/
test-scripts:
    python3 -m unittest discover --quiet --start-directory scripts --pattern '*_test.py'
    bash scripts/push_release_commit_test.sh

# Every harness scenario, run against addon/
[working-directory('harness')]
test-harness:
    cargo test --quiet --locked

# The site's build
[working-directory('www')]
test-www:
    npm ci
    npm run build

# Before a push that releases the addon. Release notes are made from commit subjects, so one over 100 characters fails.
prepush: test-addon test-scripts test-harness
    #!/usr/bin/env bash
    set -euo pipefail
    long="$(git log --format='%h %s' origin/main..HEAD | awk 'length($0) - 8 > 100')"
    if [[ -n "${long}" ]]; then
        echo "These commit subjects are over 100 characters; put the detail in the body:" >&2
        echo "${long}" >&2
        exit 1
    fi
    echo "Checks passed. Now walk the smoke list in README.md in the game before pushing."

# Link the addon folders into the game's AddOns folder, EVERLOOK_ADDONS_DIR
sync:
    bash scripts/sync.sh
