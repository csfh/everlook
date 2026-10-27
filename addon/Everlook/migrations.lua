local _, Everlook = ...

-- EverlookDB carries a schema number. Each step brings a file written by an earlier
-- version up to the next number, in order, and a step is only ever added at the end.
-- A file with a higher number than this version knows was saved by a newer Everlook
-- and is left as it is, except the collection purge, which runs every time.
Everlook.migrations = {}

-- Keys written by the old world-data, journey, signing and report code.
-- Quality-of-life settings (qol, minimap, experience, the remembered cvars)
-- stay. Running this again is a no-op once the keys are gone.
local COLLECTION_KEYS = {
	"world", "worldRows", "worldBytes", "raw", "pages", "pageCounts", "pagesCheck", "pagesMigrating",
	"segments", "manifest", "signer", "signature", "secret", "staleSegments", "flushStats",
	"ixVersion", "probe", "reports", "journey", "collection", "enabled", "eager", "collect",
	"mapsSwept", "loadStats",
}

local function purge(db)
	if type(db) ~= "table" then return end
	for index = 1, #COLLECTION_KEYS do
		db[COLLECTION_KEYS[index]] = nil
	end
	if type(db.qol) == "table" then
		db.qol.journey = nil
	end
end

local steps = {
	-- 1: settings hold only what a player changed. module.lua drops the values that
	-- equal a default when each module loads, so this step only makes sure the
	-- container is a table.
	function(db)
		if type(db.qol) ~= "table" then db.qol = {} end
	end,
	-- 2: drop the collection. The purge also runs on every load, so a file that
	-- already passed this number still loses the keys.
	function(db)
		purge(db)
	end,
	-- 3: drop the reports the removed /everlookplates and /islandmouse probes wrote.
	function(db)
		db.plate_anatomy, db.island_mouse = nil, nil
	end,
}

Everlook.migrations.current = #steps
Everlook.migrations.purge = purge

function Everlook.migrations.run(db)
	if type(db) ~= "table" then return end
	purge(db)
	local from = db.schema
	if type(from) ~= "number" or from ~= from or from < 0 then from = 0 end
	if from > #steps then return from end
	for version = from + 1, #steps do
		steps[version](db)
		db.schema = version
	end
	return db.schema or from
end

-- Saved variables are in place when ADDON_LOADED fires for this addon, and the module
-- addons load after it, so they always see a migrated file.
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
	EventUtil.ContinueOnAddOnLoaded("Everlook", function()
		EverlookDB = EverlookDB or {}
		Everlook.migrations.run(EverlookDB)
	end)
end
