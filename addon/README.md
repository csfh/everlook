# Everlook addon

Quality-of-life tweaks for World of Warcraft, and the settings page their modules share. Each `Everlook_<Name>` folder is a module addon that depends on the core (`Everlook`) and starts disabled. The addon does not collect world data. Notes for people changing it are in [wiki/README.md](wiki/README.md).

## Install

Download the latest release from https://github.com/csfh/everlook/releases/latest and unpack its folders into `Interface/AddOns`.

## Develop

Link every folder into your game's `AddOns` directory with:

```sh
EVERLOOK_ADDONS_DIR="/path/to/World of Warcraft/<flavor>/Interface/AddOns" bash scripts/sync.sh
```

The script links each `Everlook*` folder. If a real folder is already there, it moves it aside to a backup first.

Lua 5.1 only. No Ace, LibStub, or embeds. See [AGENTS.md](AGENTS.md) for the rules modules follow.

## Test

```sh
lua5.1 tests/run.lua
python3 tests/scripts_test.py
python3 tests/luac_test.py
(cd scripts && python3 -m unittest risky_uses_test)
```

## Package

```sh
bash scripts/pack.sh <version> <output dir>
```

This writes `Everlook-<version>.tar.gz`, a zip of the same folders, and `SHA256SUMS` for both. It stamps the core's version into each module's TOC. Module TOCs in the repository have no `## Version`.

## Third-party assets

The bundled fonts keep their own licenses. See `Everlook_Fonts/assets/`.

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Christoffer Hallas.

If you send a pull request or other contribution, you agree to the [CLA](CLA.md).
