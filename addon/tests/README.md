# How the addon is tested

Three layers, from cheapest to closest to the game. All of them run before a push that releases the addon (`just prepush`).

| Layer | Run with | What it proves |
| --- | --- | --- |
| Lua suite | `lua5.1 tests/run.lua` | Module logic on plain Lua 5.1 with stand-ins for the game's API. Fast; runs in public CI. |
| Folder, luac and script checks | `tests/folders_test.py`, `tests/luac_test.py`, and each script's `_test` beside it in `scripts/`; `just test-addon` runs them with the Lua suite | The packed release (folders, versions, media, checksums, the same bytes twice), that every TOC lists real files, `luac5.1` limits (200 locals, 60 upvalues) and stray globals. Run in public CI. |
| Harness | `just test-harness` | The real addon files on frames with the game's strata, mouse, clock and animation rules (`harness/` at the repository root). |

Rules for writing a test (they come from mistakes already made):

- A stand-in widget lists the methods it has and raises on any other. A catch-all that does nothing lets a typo pass.
- Mock only names that appear in Blizzard's own code (wow-ui-source 12.0.0, `Mainline` and `Shared`). A mock of a function the game lacks lets broken code pass.
- Write the failing test first, and check that it fails for the reason you think by running it against the old code.
- A test file is named for what it tests, as the source files are: a core file (`module.lua`), a module (`bags.lua`), a module part (`island_toasts.lua`) or an Island extension (`island_share.lua`). It returns `function(check, lib)` and is listed in `run.lua`. `lib` comes from `tests/lib/`: `root` is the addon folder, `source` finds an addon file and `read_source` reads it, `layout` resolves anchors to rectangles, and `worlds.lua` loads the addon (`load_all`, `load_files`, `island_world`, `quest_world` and their helpers, such as `notice_key`). Lua allows 200 locals in one function, so a group of checks goes in a `do ... end` block. `tests/folders_test.py` fails on a test file that is not named for a shipped file or not listed in `run.lua`.
- A new module folder gets a test file of its own, and `load_all` loads it from its TOC with every other addon; `scripts/pack_test.py` unpacks a real release and runs the suite against it.

