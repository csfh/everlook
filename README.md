# Everlook

Small quality-of-life addons for WoW Forever (`## Interface: 16001`), each its own addon, all
grouped under Everlook in the AddOns list and configured under `/el` (or the minimap button).

## Layout

- `Everlook/`: the core. `Everlook:NewAddon`, events, saved settings, `Everlook.Schedule`
  (background work on a 1.5 ms frame budget) and `Everlook.Trace` (load timings).
- `EverlookPreferences/`: the settings window, its folders, `/el`, the minimap button, and the
  page API (`NewPage`, `Checkbox`, `Slider`, `NewCanvasPage`).
- `EverlookQA/`: checks at login that the game functions each addon lists with
  `EverlookQA:Expect` exist, the taint-log switch, and `stubs.lua` for the offline tests.
- `EverlookPerformance/`: frame-time chart, task table and load history.
- Every other `Everlook*` folder is one feature.

## Site

`www/` is the project page, built with Vite. It lists every addon from its `.toc` (`## Title`,
`## Notes`) under the settings folder it uses in game.

```sh
cd www && npm ci && npm run build   # output in www/dist
```

## Install

```sh
./link.sh            # symlinks every Everlook* folder into the Forever AddOns folder
```

Restart the game client after adding or renaming a folder; `/reload` is enough for edits.

## Tests

```sh
./test.sh            # runs every *_test.lua with lua5.1
```

Tests run the real addon files against stand-ins for the game API (`EverlookQA/stubs.lua`).
They check logic only; anything that touches the game still needs a look in game.

## License

MIT. See [LICENSE](LICENSE). Copyright (c) 2026 Christoffer Hallas.

If you send a pull request or other contribution, you agree to the [CLA](CLA.md).

The fonts in `EverlookFonts/assets/` keep their own licences, bundled beside them: Manrope under the SIL Open Font License 1.1, and Expressway under the Typodermic freeware licence.
