# Everlook

Small quality-of-life addons for World of Warcraft Forever (`## Interface: 16001`). Each
`Everlook*` folder at the repository root is one addon the game loads; `www/` is the project page.

## Where things live

| Path | What it is |
| --- | --- |
| `Everlook/` | The core: `Everlook:NewAddon`, events, saved settings (`EverlookDB[name]`), `Everlook.FormatMoney`, `Everlook.Schedule` (background work on a 1.5 ms frame budget, 0.75 ms below 30 fps) and `Everlook.Trace` (load timings). |
| `EverlookPreferences/` | The settings under `/el` and the minimap button. Pages: `NewPage(self, "Folder")` with `Checkbox` and `Slider`, or `NewCanvasPage`. The folders and their order are `Preferences.FOLDERS`. |
| `EverlookQA/` | `EverlookQA:Expect(name, needed, optional)`, checked at login and on its page; the taint-log switch; `stubs.lua`, the stand-in game API for the offline tests. |
| `EverlookPerformance/` | Frame-time chart, task table and load history. |
| `Everlook<Feature>/` | One feature each: `<Name>.toc`, `<Name>.lua`, `<Name>_test.lua`. |

## Writing an addon

- The folder is `Everlook<Feature>`. Its TOC has `## Interface: 16001`, a Title Case `## Title`,
  `## Notes`, `## Dependencies: Everlook, EverlookPreferences, EverlookQA`, `## Group: Everlook`
  and the logo as `## IconTexture`.
- `Everlook:NewAddon(name, { label, defaults })`, then `EverlookQA:Expect` with every game global
  or field path it uses; names with a fallback go in the optional list.
- Settings come from `EverlookPreferences:NewPage(self, "<folder>")` in `OnInitialize`; react to
  changes in `OnSettingChanged(key, value)`.
- Work that walks many frames or items runs as an `Everlook.Schedule.Task` step, or through
  `Everlook.Schedule.Defer(key, fn)` for bursts of events.
- Holding Shift pauses anything that acts for the player. Nothing touches protected frames
  (action bars, the stance bar) in combat. When the game can't say whether something is safe,
  leave it to the player.
- Check a frame, event or function name against Blizzard's UI source (Gethe/wow-ui-source,
  tag 12.0.0) before using it. EverlookQA reports anything the Forever client lacks.

## Checks

- `./test.sh` runs every `*_test.lua` with `lua5.1` against `EverlookQA/stubs.lua`. A test stubs
  only the globals its addon uses. Tests check logic; game behaviour still needs a look in game.
- `./link.sh` symlinks the folders into the game's AddOns folder. Restart the client after adding
  or renaming a folder; `/reload` is enough for edits.
- `cd www && npm ci && npm run build` builds the site. It reads every TOC's Title and Notes and
  each addon's settings folder.
- CI (`.github/workflows/tests.yml`) runs the tests and the site build on every pull request.
