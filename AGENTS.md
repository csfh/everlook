# Everlook

Everlook is a set of World of Warcraft quality-of-life addons and a static site that lists them. It collects no data: no world data, uploads, signing, journey or reports. Do not add any. Nothing here may depend on a third-party data site (no Wowhead, Wowpedia, Wago or listfile), in code, at build time or at run time.

| Path | What it is |
| --- | --- |
| `addon/` | The addons, Lua 5.1: the core `Everlook` and its `Everlook_<Name>` modules, the folders a release ships, and their tests in `addon/tests`. |
| `harness/` | A Rust host (`mlua`, Lua 5.1) that runs the addon files with the game's frame, mouse and clock rules. It never ships. |
| `www/` | The Vite site for Cloudflare Pages. It reads the module list from the addon TOCs at build time. |
| `scripts/` | Linking the addons into the game, packing and releasing them, and generating the island's art, each with its test beside it. |

## Checks and releases

`just test` runs `just test-addon` (`addon/tests`), `just test-scripts`, `just test-harness` and `just test-www`. Each folder holds its own tests. CI runs the same recipes (`.github/workflows/checks.yml`).

A push to `main` that changes `addon/` can publish a GitHub Release tagged `addon-v<version>`. Commit types decide it: `feat` is minor, `fix`, `perf`, `refactor` and `revert` are patch, and `docs`, `test`, `chore`, `ci`, `style` and `build` do not release. Commit one module at a time, as `feat(addon): ...`, so any one of them can be reverted alone. Do not tag or push `main` unless asked. The version in `addon/Everlook/Everlook.toc` is what ships when that line changes by hand. Module TOCs have no `## Version` until `scripts/pack.sh` stamps it. A commit that touches only `addon/tests`, `scripts/`, `harness/` or `www/` never releases.

## The addon

Lua 5.1 only. No Ace, LibStub or embeds. Each folder named `Everlook` or `Everlook_<Name>` is one addon the game loads, and its TOC order is its wiring. `Everlook` is the core: the shared helpers, the module registry, the settings page and the minimap button (`EverlookMinimapButton`, showing `addon/Everlook/assets/logo.tga`). Every other folder is a module addon that depends on it, grouped under Everlook in the addon list. Core files take the namespace from `local _, Everlook = ...`, and `world.lua` shares it as the global `Everlook`. A module addon's files start with `local addon_name = ...` and `local Everlook = Everlook`.

Modules register with `Everlook.module.register` from `addon/Everlook/module.lua`, and each starts disabled. Settings live in `EverlookSaved.modules`. `addon/Everlook/settings.lua` builds the native Everlook settings page at login, after every module addon has registered. Its subpages come from the page list in `module.lua` (Quests, Vendors, Loot and mail, Social, Chat, Tooltips, Map, Action bars, Bags, Nameplates, Text and names, Combat, Screen and camera, Loading, Island, Radial menu), plus Performance and Debug, which turns the taint log off. A module names its page and its place on it. The bundled Expressway and Manrope fonts keep their licences in `addon/Everlook_Fonts/assets/`, and `fonts.txt` there says where each came from.

### Direction

Everlook works like Leatrix Plus. It tweaks, hides or automates something the default UI already does, behind an option the player turns on. It never replaces a Blizzard frame or builds a rival UI. An earlier attempt at replacement action bars and unit frames was removed after it proved too costly to get right. The lesson that carries over: an addon function that Blizzard's secure code calls taints the code that runs after it, which showed in flyouts in combat.

### Entry points

The minimap icon and `/everlook`, with its short form `/el`, are the only ways in, and they toggle the Everlook settings page. Any new feature gets a control on that page. Slash commands and menus beyond those are out, and `addon/tests/luac_test.py` fails on any other slash command. The radial menu keybinding is the click binding `CLICK EverlookRadialMenuButton:LeftButton` in `addon/Everlook_RadialMenu/Bindings.xml`. The island's two bindings are in `addon/Everlook_Island/Bindings.xml`: `EVERLOOK_ISLAND`, with `runOnUp` to handle holding and releasing its key, and `EVERLOOK_ISLAND_DISMISS`, which dismisses the newest island toast, the keyboard route to its right-click dismiss. The player sets the radial key on the Radial menu page and the island key on the Island page, or under Key Bindings. Another keybinding needs the same kind of reason.

### The client

Forever is built on Mainline, the retail client. The reference is `Gethe/wow-ui-source` at tag `12.0.0`, in the `Mainline` and `Shared` folders. Before using a frame name, event, function or constant, find it there. A sparse clone is enough: `git clone --depth 1 --filter=blob:none --sparse --branch 12.0.0 https://github.com/Gethe/wow-ui-source.git`, then `git sparse-checkout set Interface/AddOns`, and grep it; GitHub code search runs out of requests and its empty answers look like "not found". The generated API documentation lacks many old globals that still work, so a global counts when Blizzard's own code calls it, and a name in neither place is wrong. Old globals such as `GetItemInfo` moved to `C_` namespaces on this client, so call the namespaced form. What was checked in the source or in the client is a comment beside the code it guards, with the date when it was seen in the client. There is no wiki.

For a pattern Blizzard's code does not settle, such as a minimap button or opening the settings panel, read how a current retail addon does it (its TOC has an `## Interface:` of 100000 or more), take the behaviour, and write it here in Everlook's style. Copy no code, template or library from it.

### Rules for modules

- A module is its own addon in `Everlook_<Name>`, where the name is its module id in CamelCase. Its files are `<id>.lua` and `<id>_<part>.lua`, or `island_<id>.lua` for an Island extension, and a file puts on `Everlook` only the module's table, `Everlook.<id>`, or one named for the file itself. Settings, the addon list, Key Bindings and the site call it by the folder's words in sentence case, such as Chat layout for `Everlook_ChatLayout`. Its TOC has the core's `## Interface`, `## Notes`, and a `## Title` of `Everlook` and the same words Settings uses, such as `Everlook Auto repair`. "Everlook" is in gold (`|cffffd100`). The name after it is in blue (`|cff66bbff`) for a module, or in the island's accent (`|cffad76ef`) for `Everlook_Island` and its `Everlook_Island<Name>` modules. The TOC also has `## Dependencies: Everlook` and `## Group: Everlook`. It has no `## Version`, because pack stamps the core's, and no `## SavedVariables`, because settings live in `EverlookSaved`. `addon/tests/folders_test.py` fails on any of this that differs. The module calls `Everlook.module.register` with `addon = addon_name`, a `page` and an `order`, and starts disabled, and it gets a test file named for its id. A release ships every `Everlook*` folder.
- Something that adds to another module, such as an island feed, is an extension. It lives in its own addon that also depends on the host's addon, so an island module has `## Dependencies: Everlook, Everlook_Island`, and it calls `Everlook.module.extend`. Its options are saved under the host. The Island calls `refresh(force)` and `follow(signal, snapshot, ...)` on its extensions, and an option's `presets` field sets it under each island preset.
- A module that acts for the player checks `Everlook.module.paused()`, so holding Shift pauses it. Work that a protected frame blocks waits until combat ends.
- Turning an option or the whole module off puts back what it changed, and only that.
- Hook in a way that can be undone. Unregister a frame's own events and register them again, or hook its `OnShow`. Reparenting or replacing Blizzard frames is off the table.
- Fail closed. When an API that an automation depends on is missing, the automation does nothing. A guard written as `fn and fn()` fails open, so it cannot protect anything that spends, sells, deletes or accepts.
- Health, power, names, ids and chat text can be secret values in combat and restricted content. Hand them straight to a status bar or `SetText`. Comparing them or doing arithmetic on them raises an error, and an id needs an `issecretvalue` check before it goes into text.
- Use `Everlook.secret(value)`, `Everlook.public(value)`, `Everlook.readable(value)` (not nil and not hidden), `Everlook.text(value, maximum)` (a readable, non-blank string no longer than maximum) and `Everlook.finite(value)` (a public number that is neither NaN nor infinite; core, `world.lua`) instead of a copy of the check in each file, `Everlook.call(object, method, ...)` for a method a widget may lack, `Everlook.clock()` for the profiling timer in milliseconds, and `Everlook.after_combat(key, fn)` (core, `combat.lua`) for work on protected frames that must wait for combat to end: the latest request under a key wins. Add tooltip lines through `Everlook.tooltips.add` (core, `tooltips.lua`), never a post-call of your own.
- One click vocabulary on every Everlook surface. A left click acts, opens or selects. A right click on a notice dismisses it, on the island and on its action buttons alike. Holding Shift while a window opens pauses an automation module for that visit. Shift-click on a listed item puts its link in the chat box, as in the game's own lists. Nothing asks for a confirmation; an action that cannot be undone is not offered, and one that can be is undone from the notice it made. The minimap button opens the settings page with either button.
- Combat policy for anything Everlook draws or opens. A frame Everlook creates is never protected, so it stays as it is in combat and nothing about it waits. A frame the game protects (the stance bar, action buttons, secure unit buttons, the settings panel's close in combat) is changed only out of combat, through `Everlook.after_combat(key, fn)` or `out_of_combat = true` on the module, and the module reads `InCombatLockdown()` before it touches one. A window the player opens in combat opens; one that would need a protected change says so in one line and does it when combat ends. Stock bag item buttons are not protected, so Bags may place them in combat.

## Tests

The tests check module logic and nothing about how the game behaves, so a change stays unverified until someone has run it in the game. Three layers, from cheapest to closest to the game, all run by `just prepush` with the scripts' tests:

| Layer | Run with | What it proves |
| --- | --- | --- |
| Lua suite | `lua5.1 addon/tests/run.lua` | Module logic on plain Lua 5.1 with stand-ins for the game's API. |
| Folder and luac checks | `addon/tests/folders_test.py` and `addon/tests/luac_test.py`; `just test-addon` runs them with the Lua suite | The rules for addon folders above, and `luac5.1` limits (200 locals, 60 upvalues) and stray globals. `scripts/pack_test.py` also packs a real release, unpacks it and runs the suite against it (`lua5.1 addon/tests/run.lua <folder>`). |
| Harness | `just test-harness` | The real addon files on frames with the game's strata, mouse, clock and animation rules (`harness/`, below). |

Rules for writing a test, each from a mistake already made:

- A stand-in widget lists the methods it has and raises on any other. A catch-all that does nothing lets a typo pass.
- Mock only names that appear in Blizzard's own code (wow-ui-source 12.0.0, `Mainline` and `Shared`). A mock of a function the game lacks lets broken code pass.
- Write the failing test first, and check that it fails for the reason you think by running it against the old code.
- A test file is named for what it tests, as the source files are: a core file (`module.lua`), a module (`bags.lua`), a module part (`island_toasts.lua`) or an Island extension (`island_share.lua`). It returns `function(check, lib)` and is listed in `run.lua`; `addon/tests/folders_test.py` fails on one that is not. `lib` comes from `addon/tests/lib/`: `root` is the addon folder (`addon/`, or the one given to `run.lua`), `source` finds an addon file and `read_source` reads it, `layout` resolves anchors to rectangles, and `worlds.lua` loads the addon (`load_all`, which loads every addon from its TOC in the game's order, `load_files`, `island_world`, `quest_world` and their helpers, such as `notice_key`). Lua allows 200 locals in one function, so a group of checks goes in a `do ... end` block.

## Harness

`harness/` runs the addon files on what the game does instead of permissive stand-ins, and finds bugs the Lua suite cannot show. A scenario in `harness/scenarios` is a Lua file: it loads addons with `harness.load_addon` (`harness.addons()` lists them in the game's load order), sets the world through `game` (`harness/scenarios/lib/game.lua`), and looks and pushes with `harness.rect`, `hit`, `move`, `click`, `wheel`, `event`, `advance` and `check`. `cargo test` runs every scenario against `addon/`.

- Frames are Lua tables with the id at `[0]`. A field an addon never wrote reads nil, as in the game.
- A type's methods come from Blizzard's widget documentation (`harness/api/widgets.json`, from `cargo run -- gen-api <wow-ui-source>`). A method the type lacks is a nil call, and is recorded (`harness.missing()`, `harness.fields_read()`). A documented method not built yet raises `HARNESS GAP`, as does XML outside the small subset `harness/src/xml.rs` lists.
- Anchors, strata and levels, clipping, hit insets, mouse focus, OnEnter, OnLeave and OnClick, animation groups, `C_Timer` and `OnUpdate` run on one clock that a scenario steps with `harness.advance(seconds)`.
- Font objects come from Blizzard's font XML (`harness/api/fonts.json`), and text is measured with the glyphs of the real font files, so the Fonts addon's change shows in widths. Blizzard's own art is not in the repository and draws as a hatched placeholder with its name.
- `harness/docs/engine-facts.md` lists every rule of the game the harness assumes. When the client disagrees, fix the harness and that page in the same commit.

## The site

Every visible change in `www/` is a design decision. Settle hierarchy, layout, typography, color, spacing, states, accessibility and copy before writing code. The addon's own surfaces follow its Direction above.

## Skills

Load the skill for the work before starting it, and always for UI work. Skills live in `~/.agents/skills`, linked into `~/.claude/skills`.

| Work | Skill |
| --- | --- |
| Building or reviewing the site's UI | `better-interface`, or the focused `better-layout`, `better-typography`, `better-colors`, `better-ui`, `better-accessibility`, `better-writing` |
| Assessing an existing screen | `interface-review`, `explain-interface` |
| Motion and polish | `animate`, `emil-design-eng`, `apple-design`, `review-animations`, `improve-animations`, `find-animation-opportunities` |
| Touch and small screens | `mobile-native` |
| Choosing a library for the site, which is vanilla Vite | `pick-ui-library` |
| Implementing, refactoring, committing | `swe`, with `tdd` for test-first work |
| Something broken | `diagnosing-bugs` |
| Editing this file or a skill | `writing-for-agents` |
| The license, CLA or contributing guide | `oss` |
