---
name: wow-retail-patterns
description: >-
  Finds canonical World of Warcraft retail addon implementations before
  guessing UI geometry or Settings-panel behavior. Use when building or
  fixing addon patterns such as minimap buttons, MinimapCluster parenting,
  frame strata, Settings.RegisterVerticalLayoutCategory, Settings.OpenToCategory,
  HideUIPanel, or when the user mentions Questie, Leatrix, TomTom,
  LibDBIcon, or wow-ui-source.
---

# WoW retail patterns

Do not invent minimap math, Settings-panel open/close, or cluster parenting.
Read a current retail implementation first, then reimplement in this repo's style.

## Source order

1. **Blizzard FrameXML** — [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source). This is how the client parents `Minimap`, `MinimapCluster`, `SettingsPanel`, and `HideUIPanel`.
2. **API page** — [warcraft.wiki.gg](https://warcraft.wiki.gg) for the exact function (`Settings.OpenToCategory`, `RegisterAddOnSetting`, `CreateFrame`).
3. **Two current retail addons** that already ship the pattern. Prefer first-party Lua over Ace wrappers when this repo forbids embeds.
4. **Local install** — `Interface/AddOns/<Name>` on this machine.
5. Invent only after those are missing or contradict each other. State the conflict.

Classic backports (3.3.5, WotLK forks, "PA-" ports) are not retail. Reject a hit whose `.toc` `## Interface:` is below `100000` unless the task is Classic.

## How to find the file

Search GitHub or the local addon tree for the **API symbol**, not the product name.

```
gh search code "RegisterVerticalLayoutCategory" --language Lua --limit 15
gh search code "HideUIPanel(SettingsPanel" --language Lua --limit 15
gh search code "LibDBIcon" "Minimap:GetWidth" --language Lua --limit 15
```

If `gh` is unavailable, use the GitHub `search_code` tool or site search:

`language:Lua Settings.RegisterVerticalLayoutCategory`

Then open the `.toc` and confirm a current retail interface line (`110000+` / `120000+` / Forever's listed interfaces). Read the function that **places** or **toggles**, not the whole addon.

For an addon installed locally:

```
rg -n "OpenToCategory|MinimapCluster|LibDBIcon|RegisterVerticalLayoutCategory" \
  "$WOW/Interface/AddOns" -g '*.lua'
```

Do not treat CurseForge zip comments as source.

## Canonical homes

Read [sources.md](sources.md) for org/repo URLs. Default set:

| Addon | Why read it | Watch for |
| --- | --- | --- |
| Blizzard `wow-ui-source` | Minimap cluster, Settings panel, `HideUIPanel` | Branch must match the API generation |
| **Leatrix Plus / Leatrix Maps** | Vanilla Lua, minimap button, QoL toggles | Official org is `leatrix`, not Classic forks |
| **Questie** | Minimap button show/hide, options entry points | AceConfig / LibDBIcon — extract behavior, do not import Ace |
| TomTom | Arrow + minimap button placement | Mixed Classic/retail branches |
| LibDBIcon-1.0 | De-facto rim angle/radius for round minimaps | LibStub library — copy the **formula**, not the embed |

Also acceptable: Details!, WeakAuras, AllTheThings, BugSack — when they implement the same API.

## Extract, do not vendor

Everlook constraints still win: Lua 5.1 only, no Ace, no LibStub, no embeds, authored files `[a-z0-9_]+.lua`.

From each source, write down only:

- parent frame (`MinimapCluster` vs `Minimap`)
- frame strata / level relative to the minimap
- radius formula (usually `Minimap:GetWidth() / 2 + pad`)
- click → open/close (`Settings.OpenToCategory` / `HideUIPanel(SettingsPanel)`)
- saved-variable key the control writes

Reimplement those facts in this addon's files. Do not paste their modules, XML templates, or license headers into the tree.

If two retail addons disagree, prefer FrameXML, then the addon that uses the stock Settings API without Ace.

## Pattern map

| Need | Search strings | First files to open |
| --- | --- | --- |
| Dial on the minimap rim | `SetPoint("CENTER", Minimap`, `GetWidth() / 2`, `minimapPos` | LibDBIcon `updatePosition`; Leatrix minimap button |
| Button not under the gold border | `MinimapCluster`, `SetFrameLevel`, `SetFrameStrata` | `wow-ui-source` minimap cluster; LibDBIcon button ctor |
| Settings category | `RegisterVerticalLayoutCategory`, `RegisterAddOnSetting` | warcraft.wiki.gg *Creating a settings menu* |
| Toggle Settings from a click | `HideUIPanel(SettingsPanel)`, `SettingsPanel:IsShown`, `OpenToCategory` | FrameXML Settings panel; any retail addon that toggles options from a broker/minimap click |
| Show/hide minimap icon | `minimap.hide`, `showMinimap`, `:Hide()` / `:Show()` | Questie minimap button option (behavior only) |

## Done when

- At least one FrameXML or wiki citation **or** two retail addon file paths are in the work notes.
- The implementation matches the extracted facts, not a remembered Classic recipe.
- No Ace/LibStub entered the tree.
