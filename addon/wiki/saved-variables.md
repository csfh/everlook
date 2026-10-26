# SavedVariables

`Everlook/Everlook.toc` declares one account-wide table. Module addons declare none and keep their settings in it:

```
## SavedVariables: EverlookDB
```

The client stores it at `WTF/Account/<account>/SavedVariables/Everlook.lua` and writes the file on `/reload`, logout, disconnect, or quit. During the initial file execution the table can still be nil, so `minimap.lua` assigns `EverlookDB = EverlookDB or {}`. Migrations run on `ADDON_LOADED`.

## What it holds

Module settings live in `EverlookDB.qol`, one table per module id. Flight routes and a flight already in the air sit under `qol.flight_time`. The minimap angle is `EverlookDB.minimap.angle` (starting angle 160). `schema` is the migration number (`Everlook.migrations.current`).

Other keys the quality-of-life modules write, and that a load keeps:

- `experience`: the Island's own hour and day totals, keyed by character GUID. It never leaves the machine.
- `loadTrace` and `loadTraceHistory`: the last load and a short line for each of the last eight, shown on the Performance page.
- `cameraBefore`, `groundEffectsBefore`, `instantTextBefore`, `timestampsBefore`: the CVar values to put back when that module turns off.
- `island_history`: notices the Island keeps across a reload.

`migrations.lua` clears collection keys on every load, before the schema steps, including on a file saved by a newer Everlook. A second run changes nothing. The keys it removes are `world`, `worldRows`, `worldBytes`, `raw`, `pages`, `pageCounts`, `pagesCheck`, `pagesMigrating`, `segments`, `manifest`, `signer`, `signature`, `secret`, `staleSegments`, `flushStats`, `ixVersion`, `probe`, `reports`, `journey`, `collection`, `enabled`, `eager`, `collect`, `mapsSwept`, `loadStats`, and `qol.journey`. `schema` and the quality-of-life keys above stay.
