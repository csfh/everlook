# Everlook

Small quality-of-life addons for World of Warcraft Forever (`## Interface: 16001`). Each
`Everlook*` folder at the repository root is one addon the game loads; `www/` is the project page.

## Where things live

| Path | What it is |
| --- | --- |
| `Everlook/` | The core: `Everlook:NewAddon`, events, saved settings (`EverlookDB[name]`), `Everlook.FormatMoney`, `Everlook.Schedule` (background work on a 1.5 ms frame budget, 0.75 ms below 30 fps), `Everlook.Trace` (load timings) and `Everlook.Font` (the font tokens). |
| `EverlookPreferences/` | The settings under `/el` and the minimap button. Pages: `NewPage(self, "Folder")` with `Checkbox`, `Slider` and `Dropdown` (a `{ value, label }` list, or a function returning one), or `NewCanvasPage`. The folders and their order are `Preferences.FOLDERS`. |
| `EverlookQA/` | `EverlookQA:Expect(name, needed, optional)`, checked at login and on its page; the taint-log switch; `stubs.lua`, the stand-in game API for the offline tests. |
| `EverlookPerformance/` | Frame-time chart, task table and load history. |
| `Everlook<Feature>/` | One feature each: `Everlook<Feature>.toc`, `<feature>.lua`, `<feature>_test.lua`. |

## Writing an addon

- The folder is `Everlook<Feature>`, and its TOC is `Everlook<Feature>.toc`: the game loads a TOC
  only if it is named after its folder. Every other file is snake_case, without the Everlook
  prefix: `EverlookSpellRanks/spell_ranks.lua`, `spell_ranks_test.lua`, `assets/fira_sans.ttf`.
- The TOC has `## Interface: 16001`, a Title Case `## Title`,
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

## Restyling the game's frames

These rules hold for `EverlookTheme` and for any addon that changes how a game frame looks. In
12.0, an addon that writes to Blizzard's frames or functions taints them, and tainted Blizzard
code fails on secret values.

- An addon may hide a game texture, with `Hide()` where the game fades it by alpha and
  `SetAlpha(0)` where the game shows and hides it itself. It may draw frames of its own on a game
  frame, and run after Blizzard code with `hooksecurefunc` or `HookScript`.
- It never re-anchors, resizes, reparents, shows or hides a game frame. It never replaces a
  Blizzard function, calls `SetScript` on a game frame, writes a field onto one, or calls
  Blizzard's styling functions (`NineSliceUtil.ApplyLayout`). It never opens or closes a Blizzard
  panel. What it drew is kept in its own tables, keyed by the game frame.
- In `EverlookTheme`, each surface is one file that hands a record to `Theme:Surface` (its fields
  are listed in `theme.lua`), with its own `_test.lua` built on `test_setup.lua`. Add it to the
  TOC after `theme.lua` and its setting to the defaults there.
- Only frames a surface names are restyled; nothing sweeps the interface. Each surface has its own
  switch, off by default. Turning it off shows every texture it hid again and hides what it drew,
  and its test checks exactly that.
- Frames of its own on protected frames (unit frames) are made out of combat only and queued
  until `PLAYER_REGEN_ENABLED`.
- Every frame and texture path a surface uses goes in `EverlookQA:Expect`, so a client without one
  shows it on the QA page instead of throwing an error.
- Each kind of change has one owner, and the others leave it alone:

  | Owner | What only it changes |
  | --- | --- |
  | `EverlookTheme` | Art textures, and the panels it draws |
  | `EverlookFonts` | Fonts and text, and the font tokens' fonts and sizes |
  | `EverlookUnitFrames` | Portraits and unit frame layout |
  | `EverlookChat` | Chat messages |

  Where two of them work on the same frame, each touches only its own part or its own child
  frames.
- Everlook's own text takes a font token: `text:SetFontObject(Everlook.Font.Body)` (Heading, Body,
  Small, Chat or Number; `Everlook/font_tokens.lua`). Only EverlookFonts sets a token.
- An accent line Everlook draws is 2 interface units thick and never thinner than 2 screen
  pixels, as `Theme.LINE` and `Theme.LINE_PIXELS` set it: `Theme.Panel` draws it, and a line of
  an addon's own is sized with `PixelUtil.SetHeight(line, 2, 2)`. One pixel reads as a hairline.
- Every dark background Everlook draws is `Theme.BACKGROUND` at the background opacity token,
  `Theme:Opacity()`: the Theme page's one "Background opacity" slider, shared by every surface.
  `Theme.Panel` draws it and `Theme:FillAll` repaints it when the slider moves. A lighter or
  darker background is that slider's job, for every surface at once.
- Lua errors and taint land in `_forever_/Logs/General.log`, as "execution tainted by
  '<addon>'". Read it after the first session with a new surface switched on.

## Checks

- `./test.sh` runs every `*_test.lua` with `lua5.1` against `EverlookQA/stubs.lua`. A test stubs
  only the globals its addon uses. Tests check logic; game behaviour still needs a look in game.
- `./link.sh` symlinks the folders into the game's AddOns folder. Restart the client after adding
  or renaming a folder; `/reload` is enough for edits.
- `cd www && npm ci && npm run build` builds the site. It reads every TOC's Title and Notes and
  each addon's settings folder.
- CI (`.github/workflows/tests.yml`) runs the tests and the site build on every pull request.
