# Minimap button

`minimap.lua` creates `EverlookMinimapButton` after `ADDON_LOADED`. The icon is `Interface\AddOns\Everlook\assets\logo.tga`.

## Shape and position

The button is the stock minimap-button layout: 31px, a 53px border anchored to `TOPLEFT`, and a 20px icon at `TOPLEFT` 7, -5. It sits on the minimap ring and left-drag moves it. The saved angle is `EverlookDB.minimap.angle`. The starting angle is 160.

The textures are:

- `Interface\Minimap\MiniMap-TrackingBorder`
- `Interface\Minimap\UI-Minimap-Background`
- `Interface\Minimap\UI-Minimap-ZoomButton-Highlight`

Hovering shows "Everlook" and "Click to open the settings." Either mouse button toggles the Everlook settings page. `/everlook`, or `/el` for short, does the same and takes no arguments. Esc, Options, AddOns, Everlook reaches the same page.

The page is `Settings.RegisterVerticalLayoutCategory`. Module options are subpages (`Settings.RegisterVerticalLayoutSubcategory`): Quests, Vendors, Loot and mail, Social, Chat, Tooltips, Map, Action bars, Bags, Nameplates, Text and names, Combat, Screen and camera, Loading, Smart island, and Radial menu. Performance is a canvas subpage when the scheduler exposes one. Debug is added only when the client has a taint log or a module reports a problem. See [qol.md](qol.md).
