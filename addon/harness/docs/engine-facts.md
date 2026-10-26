# Engine facts

Every rule of the game the harness assumes, with where it comes from. A rule marked **assumed** has not
been seen in the client. When the client disagrees, fix the harness and fix this page in the same commit.

| # | Rule | Source |
| --- | --- | --- |
| 1 | A new frame starts in its parent's strata, one level above the parent. | assumed; fstack of the island (Pin at 54 under Expanded 50) agrees |
| 2 | `SetFrameLevel` on a frame moves everything under it by the same amount. | **read in the client**: raising the island's panel one level raised its buttons from 54 to 55 (`/islandmouse raise`) |
| 3 | `SetFrameStrata` on a frame does not move its children. | assumed |
| 4 | A frame that is not mouse-enabled never takes the mouse; a hidden one never does either. | assumed |
| 5 | Alpha 0 does not stop a frame taking the mouse. | assumed |
| 6 | A child cut off by a clipping parent cannot take the mouse outside the parent. | assumed |
| 7 | A negative hit-rect inset grows the hit area, a positive one shrinks it. | the addon relies on it (`-2` when closed) |
| 8 | Of the frames under the pointer, the highest strata, then level, then latest created, gets it first. | assumed |
| 9 | `EnableMouse` sets click and motion together; `SetMouseClickEnabled` and `SetMouseMotionEnabled` set them apart. | Blizzard widget docs list all three |
| 10 | A frame table is a plain table: fields the addon never wrote read as nil. | the game |
| 11 | A method the widget type lacks is nil, and calling it is "attempt to call method '...' (a nil value)". | the game |
| 12 | Text is as wide as the advance widths of its font file add up, with no kerning. A Blizzard typeface that is not in the repository is measured with Expressway. | assumed; stand-in used is listed in `FontBook::stand_ins` |
| 13 | A line of text is as tall as its font is high, plus the string's spacing between lines. | assumed |
| 14 | A font object's file, height and colour come from Blizzard's font XML (`api/fonts.json`); a string that follows a font object sees later changes to it. | Blizzard XML; the live link is assumed |
| 15 | A tooltip is ten units in from each edge, its lines are stacked with two between them, its width is the widest line (left text, then twenty, then right text), and it is placed by its owner and anchor (`ANCHOR_RIGHT` puts its bottom left at the owner's top right). The first line is in `GameTooltipHeaderText`, the rest in `GameTooltipText`. A line that may wrap takes up to 300. | assumed, from how the default tooltip looks; the fonts are Blizzard's own |
| 16 | `GameTooltip` methods that Blizzard's documentation does not list (`SetOwner`, `AddLine`, `AddDoubleLine`, `ClearLines`, `NumLines`) are those of the community wiki. | wiki |

| 17 | **Ruled out.** A clipping frame whose own mouse is off hides every frame under it from the mouse (`Rules.clip_needs_mouse`, off). It predicts nothing gets the mouse when the island's own mouse is off; the client said the Pin button did. | the client's `/islandmouse noroot`, 2026-10-11 |
| 18 | **Ruled out.** A frame inside a scroll frame's scroll child must be inside that scroll child's rectangle to be hit (`Rules.scroll_child_limits`). The client lists the quest pane's scroll frame (a direct child of the panel, not inside a scroll child) among the frames that hold the pointer and lose to the island itself, so this cannot be the cause. | the client's `/islandmouse`, 2026-10-11 |
| 19 | **Read in the client.** A clipping frame's whole subtree is ordered as one unit at the clipping frame's strata and level; inside it by the frames' own levels; against a frame outside it at the same level an ancestor wins (`Rules.flatten_clips`, on). The island and its clipping panel were both level 50, so the island took the mouse from every button in the panel. All five of the client's experiments (plain, noroot, noclip, raise, mouse) match it, and only it. | the client's `/islandmouse`, 2026-10-11 |
| 20 | `debugprofilestop` is wall-clock milliseconds since the host started, and keeps running while the harness's own clock (`GetTime`) stands still. Scenarios print it and never assert on it. | assumed; the game's is a high-resolution millisecond clock (Warmup and AddonLoadingTime use it across loading screens) |
| 21 | `harness.census()` counts the frames made, the event registrations on them, and the shown frames with an `OnUpdate` script. Only counts are asserted (`scenarios/perf_budget.lua`). | the harness's own bookkeeping |
| 22 | `Frame:RegisterUnitEvent(event, unit...)` registers the event like `RegisterEvent`, and counts in `harness.census()`. The harness does not filter by unit, since a scenario fires each event by hand. | the game sends the event only for those units; the harness does not model that |

`/islandmouse` in the addon prints what the client says is under the pointer. Its output settles rows 4 to 8.

| 23 | `UNIT_DIED` and `PARTY_KILL` are both accepted by `RegisterEvent` and fire with a readable string GUID in the open world (build 70374), though wow-ui-source 12.0.0 has no `PARTY_KILL` event. `CanLootUnit(guid)` returns `hasLoot, canLoot` and reads `false, true` for an empty corpse the player killed. `GetQuestLogRewardXP(questID)` returns two numbers. The harness does not model any of them. | a check in the client, 2026-10-15 |
| 24 | In combat on build 70374 an addon may call `HideUIPanel(SettingsPanel)` and `SetPassThroughButtons` on an unprotected frame without an error. A `SetMaxLines(1)` text had its full width right after `SetText`; the blank-after-cold-start claim was not reproduced. The harness allows both. | a check in the client, 2026-10-15 | 
