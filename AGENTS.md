# Everlook

Everlook is a collection of World of Warcraft quality-of-life addons and a static site that lists them. It collects no data: no world data, uploads, signing, journey or reports. Do not add any.

| Path | What it is |
| --- | --- |
| `addon/` | Lua 5.1 addons. No Ace, LibStub, or embeds. `Everlook` is the core. Each `Everlook_<Name>` is a module addon that depends on it and starts disabled. TOC order is wiring. Settings live in `EverlookSaved.modules`. `addon/AGENTS.md` has the rules modules follow. |
| `harness/` | Rust host (`mlua`, Lua 5.1) that runs the addon files with the game's frame, mouse and clock rules. Its scenarios in `harness/scenarios` run against `addon/`. It never ships. |
| `www/` | Vite static site for Cloudflare Pages. It reads the module list from the addon TOCs at build time. Build output is `www/dist`. |

Checks: `just test` runs `just test-addon` (the Lua suite, `tests/folders_test.py`, `tests/luac_test.py` and each script's test beside it in `addon/scripts/`), `just test-harness` and `just test-www`. CI runs the same recipes (`.github/workflows/checks.yml`).

A push to `main` that changes `addon/**` can publish a GitHub Release tagged `addon-v<version>`. Commit types decide it: `feat` is minor, `fix`, `perf`, `refactor` and `revert` are patch, and `docs`, `test`, `chore`, `ci`, `style` and `build` do not release. Do not tag or push `main` unless asked. The version set in `addon/Everlook/Everlook.toc` is what ships when that field changes by hand. Module TOCs have no `## Version` until `addon/scripts/pack.sh` stamps it.

Nothing here may depend on a third-party data site (no Wowhead, Wowpedia, Wago, or listfile), in code, at build time, or at run time.
