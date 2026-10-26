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
cargo test                                  # every scenario in scenarios/ against ../addon
cargo run -- run scenarios/island_mouse.lua # one scenario, with its checks printed
cargo run -- render scenarios/island_gallery.lua out.html # one HTML file; a scenario's harness.snapshot(name) calls become its states
cargo run -- serve scenarios/island_mouse.lua             # the same, live: hover, click, wheel, step the clock
cargo run -- gen-api /tmp/wow-ui-source     # rebuild api/widgets.json and api/fonts.json
cargo run --release -- casc <game dir> info                      # open the game's own file storage and count its files
cargo run --release -- casc <game dir> id 135274 icon.png       # a file by id; a .png output decodes the texture
cargo run --release -- casc <game dir> path 'Interface\\Icons\\INV_Sword_04.blp' icon.png
cargo run --release -- casc <game dir> stitch layout.json map.png # a map picture from tile ids, sizes and places
cargo run --release -- casc <game dir> worldmaps zones.tsv out/  # stitched zone pictures from `id<TAB>name[<TAB>folder]` lines
cargo run --release -- casc <game dir> scan WDC5                  # every table: file id, rows, fields, record size, table and layout hash
cargo run --release -- casc <game dir> find 'Frostbolt'          # the tables whose string table holds a text (tables have no name here)
cargo run --release -- casc <game dir> db2 1990283 spells.json   # one table as JSON; a column that reads as text also gives its text
cargo run --release -- casc <game dir> sparse 1758037 20         # a table of variable-length records: id, size, words and inline text
cargo run --release -- casc <game dir> findvalue 135940          # every table cell holding a number, with row id and parent
cargo run --release -- casc <game dir> blpcolumns [file id]      # table columns whose values are texture files (one table: every column)
cargo run --release -- casc <game dir> lenient 1990283 raw.bin    # a file with its encrypted blocks as zeros, and where they were
cargo run --release -- casc <game dir> filestatus 1003144 10 [all]   # a table column of file ids: how many read as textures, are encrypted, not stored or not in the root (five ids of each, or all of them)
cargo run --release -- casc <game dir> maplayouts out/ png      # every map region's layout from the tables as out/<id>.json, and its full picture (base and every explored piece) as out/<id>.png
cargo run --release -- casc <game dir> instances out.json      # every dungeon and raid with its entrance (world point, place on the continent's map, every zone frame that holds it) and its bosses by difficulty id and order
cargo run --release -- casc <game dir> unreadable [files]         # files stored locally whose first blocks do not read, why, and the key each encrypted block names (nothing is decrypted)
cargo run --release -- casc <game dir> magics                    # how many files start with each four bytes (the formats the storage holds)
cargo run --release -- casc <game dir> cdnplan [ids]              # root entries the install lists but does not hold, and where Blizzard's servers keep them (no download)
cargo run --release -- casc <game dir> cdnfetch out/ 1 99000000 tables  # fetch those from Blizzard's content servers, by range, into out/ (only tables with `tables`)
cargo run --release -- casc <game dir> locked                  # tables with encrypted sections: rows listed against rows readable
cargo run --release -- casc <game dir> hotfix <DBCache.bin>       # the tables the hotfix cache names, and which have a local table
```

`casc` reads the game's own local file storage (`<game dir>/Data`, with `.build.info` beside it) and nothing else: no
list of names and no key from anywhere. A file is found by id, or by a path through the game's own name hash, and an
encrypted block is reported, not guessed. Files are opened read-only, so it can run while the game is open. `src/casc.rs`
is the storage, `src/blp.rs` the texture format, `src/stitch.rs` the map composer, `src/db2.rs` the `WDC5` table reader and
`src/hotfix.rs` the hotfix cache reader and `src/maps.rs` the map layouts, `src/instances.rs` the instances and their bosses and `src/cdn.rs` the reader of files the install lists but does not hold (from the
hosts `.build.info` names, with the archive indexes the install keeps; nothing is written to the game folder). A table reader knows how columns are stored, not what they mean: a column's meaning is
a layout, and a layout is keyed by the table's layout hash. `docs/game-data-facts.md` rows 19, 20, 22 to 24, 26 and 27 say what is checked. A map layout is JSON (`layerWidth`, `layerHeight`, `tileWidth`, `tileHeight`, `tiles`, and `overlays` with `offsetX`, `offsetY`, `width`, `height`, `files`).

A scenario is a Lua file. It loads addons with `harness.load_addon`, sets the world through `game`
(`scenarios/lib/game.lua`), and looks and pushes with `harness.rect`, `hit`, `move`, `click`, `wheel`,
`event`, `advance` and `check`.

Blizzard's own art (atlases, `Interface\\...` textures) is not in the repository, so it draws as a hatched
placeholder with its name. Every Everlook addon loads and runs with no script error (`scenarios/all_addons.lua`). XML is read in a
small subset (`src/xml.rs` lists it): templates, size, anchors, texture and font-string layers, child frames and
scripts. Anything else is a named `HARNESS GAP`. Not built yet: the rest of the widget
API (`HARNESS GAP` names each).
