set shell := ["bash", "-eu", "-o", "pipefail", "-c"]
# Machine-specific settings, such as EVERLOOK_ADDONS_DIR for `just addon sync`.
set dotenv-filename := ".env.local"

default:
    @just --list

# addon, harness, www, or all
test target="all":
    @just {{ if target == "all" { "addontest harnesstest wwwbuild" } else if target == "addon" { "addontest" } else if target == "harness" { "harnesstest" } else if target == "www" { "wwwbuild" } else { error("unknown test target `" + target + "`; expected addon, harness, www, or omit for all") } }}

# addon: the checks to run before a push that releases it
prepush target="addon":
    @just {{ if target == "addon" { "addonprepush" } else { error("unknown prepush target `" + target + "`; expected addon") } }}

# sync (link into WoW)
addon action:
    @just {{ if action == "sync" { "addonsync" } else { error("unknown addon action `" + action + "`; expected sync") } }}

[private]
[working-directory('addon')]
addontest:
    lua5.1 tests/run.lua
    python3 tests/scripts_test.py
    python3 tests/luac_test.py
    cd scripts && python3 -m unittest risky_uses_test

[private]
addonprepush:
    @just addontest
    @just harnesstest
    @just addonsubjects
    @echo "Tests and harness passed. Now run the in-game smoke list in addon/RELEASING.md before pushing."

# Release notes are made from commit subjects, so a subject past 100 characters is a note nobody can read.
[private]
[working-directory('addon')]
addonsubjects:
    @long="$(git log --format='%h %s' origin/main..HEAD | awk '{ if (length($0) - 8 > 100) print }')"; if [ -n "$long" ]; then echo "These commit subjects are over 100 characters; put the detail in the body:" >&2; echo "$long" >&2; exit 1; fi

[private]
[working-directory('addon/harness')]
harnesstest:
    cargo test -q

[private]
[working-directory('www')]
wwwbuild:
    npm ci && npm run build

[private]
addonsync:
    bash addon/scripts/sync.sh
