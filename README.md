# Everlook

Quality-of-life addons for World of Warcraft, and the small site that lists them. Everlook tweaks the default interface. Each module starts off, and you turn on the ones you want from the Everlook settings page. It collects no data.

## Install

Download the latest release from https://github.com/csfh/everlook/releases/latest and unpack its folders into `Interface/AddOns`.

## Layout

```
addon/    The Everlook core and its Everlook_<Name> modules (the folders a release ships), and their tests
harness/  A Rust host that runs the addon files with the game's frame, mouse and clock rules. It never ships
www/      The static site (Vite) for Cloudflare Pages
scripts/  Sync, pack and release, each with its test
```

## Develop

```sh
just sync      # link the addon folders into the game's AddOns folder
just test      # every check: test-addon, test-scripts, test-harness and test-www
just prepush   # before a push that releases the addon
```

`just` lists every recipe. `just sync` reads `EVERLOOK_ADDONS_DIR` from the environment or `.env.local`, and moves a real folder that is in the way to a backup first. The rules for the code and its tests are in `AGENTS.md`.

In `harness/`, `cargo run -- run scenarios/island_mouse.lua` runs one scenario and prints its checks, `cargo run -- render scenarios/island_gallery.lua out.html` draws a scenario's `harness.snapshot(name)` states into one HTML file, `cargo run -- serve scenarios/island_mouse.lua` shows the same live (hover, click, wheel, step the clock), and `cargo run -- gen-api <wow-ui-source>` rebuilds `harness/api/widgets.json` and `harness/api/fonts.json`.

## Release

A push to `main` runs the checks and, when its commits ask for one, publishes a GitHub Release tagged `addon-v<version>`: a tarball, a zip and their checksums, from `scripts/pack.sh`. The commit types decide it, as `AGENTS.md` lists, and a commit outside `addon/` never releases. The version in `addon/Everlook/Everlook.toc`, written `## Version: x.y.z`, is what ships when that line changes by hand; `addon/tests/folders_test.py` fails on any other form. Do not tag a release yourself.

CI has never played the build, so before that push:

1. `just prepush`. It runs the addon and script checks and the harness, then fails if a commit subject since `origin/main` is over 100 characters, because the release notes are made from subjects.
2. `just sync`, then log in on the current client with the modules the push touches turned on.
3. Walk the smoke list. Skip anything the push did not touch, and say which were skipped.
4. Watch the Lua error display (`/console scriptErrors 1` if it is off) and the Everlook Debug page.

The smoke list:

- Login and `/reload` give no Lua error.
- `/everlook` and `/el` open settings, and every module page opens. Either with extra words still only toggles that page.
- The island shows level and the quest, opens on hover, closes, and a notice appears (a vendor visit or mail).
- Bags open, close, and search (if Bags is on).
- Quest dialog: accept and turn in with quest automation on, and a PvP-flagging quest is left to the player.
- An item tooltip and a creature tooltip show the Everlook id lines once.
- With cinematic skip on: a cinematic and a movie close as they start, a cinematic during a vehicle ride keeps playing with you still in the vehicle, and no "blocked" message appears.
- A full client restart, then login: nothing blank, no error.

After the push, check the release page.

## Site

Cloudflare Pages:

| Setting | Value |
| --- | --- |
| Root directory | `www` |
| Build command | `npm ci && npm run build` |
| Output directory | `dist` |
| Node.js | 22 |

The page lists the modules from their TOC files at build time, so a new module shows up on the next build. These settings live in the Pages project, not in a Wrangler file. Nothing here creates a Cloudflare project or a custom domain.

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Christoffer Hallas. The bundled fonts keep their own licenses, in `addon/Everlook_Fonts/assets/`.

If you send a pull request or other contribution, you agree to the [CLA](CLA.md). [CONTRIBUTING.md](CONTRIBUTING.md) says how pull requests and reports are handled.
