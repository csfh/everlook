# Everlook harness

A second way to run the Everlook addons: a Lua 5.1 host in Rust that gives them the frame, mouse, timer
and animation behaviour of the game, instead of the permissive stand-ins in `addon/tests`. It finds
bugs the stand-ins cannot show. The addon's own `lua5.1 tests/run.lua` stays the release gate.

- Frames are Lua tables with the id at `[0]`. A field an addon never wrote reads nil, as in the game.
- A type's methods come from Blizzard's own widget documentation (`api/widgets.json`, from
  `harness gen-api <wow-ui-source>`). A method the type lacks is a nil call, and is recorded
  (`harness.missing()`, `harness.fields_read()`). A documented method not built yet raises `HARNESS GAP`.
- Anchors, strata and levels, clipping, hit insets, mouse focus, OnEnter/OnLeave/OnClick, animation groups,
  `C_Timer` and `OnUpdate` run on one clock that a scenario steps with `harness.advance(seconds)`.
- Font objects come from Blizzard's font XML (`api/fonts.json`) and text is measured with the glyphs of the
  real font files, so the Fonts addon's change shows in widths.
- `docs/engine-facts.md` lists every rule of the game the harness assumes. Correct it when the client disagrees.

```
cargo test --locked                         # every scenario in scenarios/ against the addon folders in ..
cargo run -- run scenarios/island_mouse.lua # one scenario, with its checks printed
cargo run -- render scenarios/island_gallery.lua out.html # one HTML file; a scenario's harness.snapshot(name) calls become its states
cargo run -- serve scenarios/island_mouse.lua             # the same, live: hover, click, wheel, step the clock
cargo run -- gen-api /tmp/wow-ui-source     # rebuild api/widgets.json and api/fonts.json
```

A scenario is a Lua file. It loads addons with `harness.load_addon`, sets the world through `game`
(`scenarios/lib/game.lua`), and looks and pushes with `harness.rect`, `hit`, `move`, `click`, `wheel`,
`event`, `advance` and `check`.

Blizzard's own art (atlases, `Interface\\...` textures) is not in the repository, so it draws as a hatched
placeholder with its name. Every Everlook addon loads and runs with no script error (`scenarios/all_addons.lua`). XML is read in a
small subset (`src/xml.rs` lists it): templates, size, anchors, texture and font-string layers, child frames and
scripts. Anything else is a named `HARNESS GAP`. Not built yet: the rest of the widget
API (`HARNESS GAP` names each).
