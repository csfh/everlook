# Everlook

Everlook is a World of Warcraft quality-of-life addon. This repository holds the addon, the harness, and a static site. It does not collect world data, sign uploads, or keep a journey.

| Path | What it is |
| --- | --- |
| `addon/` | Lua 5.1 addon. No Ace, LibStub, or embeds. `Everlook` is the core. Each `Everlook_<Name>` is a module addon that depends on it and starts disabled. TOC order is wiring. Settings live in `EverlookDB.qol`. `Everlook/migrations.lua` clears old collection keys on every load. |
| `harness/` | Rust host (`mlua`, Lua 5.1) that runs the addon files. Scenarios are `harness/scenarios`. Tests must set `EVERLOOK_ADDONS_DIR` to this repo's `addon/`; `just test harness` does. |
| `www/` | Vite static site. Build output is `www/dist`. |

Addon checks: `lua5.1 addon/tests/run.lua`, `python3 addon/tests/scripts_test.py`, `python3 addon/tests/luac_test.py`, and `(cd addon/scripts && python3 -m unittest risky_uses_test)`. Harness: `just test harness`. Site: `cd www && npm ci && npm run build`. `just test` runs all three.

A push to `main` that changes `addon/**` can publish a GitHub Release tagged `addon-v<version>`. Do not tag or push `main` unless asked. The version set in `addon/Everlook/Everlook.toc` is what ships when that field changes by hand. Module TOCs have no `## Version` until `addon/scripts/pack.sh` stamps it.

Nothing here may depend on a third-party data site (no Wowhead, Wowpedia, Wago, or listfile), in code, at build time, or at run time.
