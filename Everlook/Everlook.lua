local _, ns = ...

Everlook = ns
Everlook.addons = {}

local frame = CreateFrame("Frame")
local listeners = {} -- [event] = { [addon] = handler }
local loggedIn = false

-- Events the core listens to itself; addons unregistering them never drop them from the frame.
local CORE_EVENTS = { "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED" }
local coreEvent = {}
for _, event in ipairs(CORE_EVENTS) do coreEvent[event] = true end

-- Load trace: when each stage of a login or reload happened, how long each Everlook addon took to
-- start, and Lua memory along the way. Kept in memory; EverlookPerformance saves a summary.
local function clock() return debugprofilestop and debugprofilestop() end

Everlook.Trace = {
	marks = {}, -- { label, ms, kb } in the order they happened
	spans = {}, -- [label] = total ms
	reload = false,
}

function Everlook.Trace.Mark(label)
	local marks = Everlook.Trace.marks
	marks[#marks + 1] = { label = label, ms = clock(), kb = collectgarbage("count") }
end

-- The first mark with this label, or nil.
function Everlook.Trace.Find(label)
	for _, mark in ipairs(Everlook.Trace.marks) do
		if mark.label == label then return mark end
	end
end

local function span(label, fn, ...)
	local began = clock()
	fn(...)
	if began then
		local spans = Everlook.Trace.spans
		spans[label] = (spans[label] or 0) + (clock() - began)
	end
end

Everlook.Trace.Mark("core")

-- Fill missing keys in `db` from `defaults`, copying nested tables.
local function applyDefaults(db, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(db[key]) ~= "table" then
				db[key] = {}
			end
			applyDefaults(db[key], value)
		elseif db[key] == nil then
			db[key] = value
		end
	end
end

-- Copper as money text with coin icons. The Forever client has no global GetCoinTextureString
-- (EverlookQA, 2026-11-05), so use the newer names and fall back to plain "1g 2s 3c".
function Everlook.FormatMoney(copper)
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	if GetMoneyString then
		return GetMoneyString(copper)
	end
	local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if gold > 0 then parts[#parts + 1] = gold .. "g" end
	if silver > 0 then parts[#parts + 1] = silver .. "s" end
	if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. "c" end
	return table.concat(parts, " ")
end

local Addon = {}
Addon.__index = Addon

function Addon:RegisterEvent(event, handler)
	handler = handler or event
	listeners[event] = listeners[event] or {}
	listeners[event][self] = handler
	frame:RegisterEvent(event)
end

function Addon:UnregisterEvent(event)
	local set = listeners[event]
	if not set then return end
	set[self] = nil
	if next(set) == nil and not coreEvent[event] then
		listeners[event] = nil
		frame:UnregisterEvent(event)
	end
end

function Addon:Print(...)
	print(("|cff33ccff%s|r"):format(self.name), ...)
end

-- /command calls handler(input); handler is a method name or a function.
function Addon:RegisterChatCommand(command, handler)
	local key = ("EVERLOOK_%s_%s"):format(self.name, command):upper()
	_G["SLASH_" .. key .. "1"] = "/" .. command
	SlashCmdList[key] = function(input)
		if type(handler) == "function" then
			handler(input)
		else
			self[handler](self, input)
		end
	end
end

local function initialize(addon)
	EverlookDB[addon.name] = EverlookDB[addon.name] or {}
	addon.db = EverlookDB[addon.name]
	applyDefaults(addon.db, addon.defaults)
	addon.initialized = true
	if addon.OnInitialize then addon:OnInitialize() end
end

local function enable(addon)
	addon.enabled = true
	if addon.OnEnable then addon:OnEnable() end
end

function Everlook:NewAddon(name, options)
	assert(not self.addons[name], "Everlook: addon already exists: " .. name)
	options = options or {}
	local addon = setmetatable({
		name = name,
		label = options.label or name,
		defaults = options.defaults or {},
	}, Addon)
	self.addons[name] = addon
	return addon
end

function Everlook:GetAddon(name)
	return self.addons[name]
end

for _, event in ipairs(CORE_EVENTS) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		local loaded = ...
		if loaded == "Everlook" then
			EverlookDB = EverlookDB or {}
			Everlook.Trace.Mark("saved")
		end
		local addon = Everlook.addons[loaded]
		if addon and not addon.initialized then
			span("init:" .. addon.name, initialize, addon)
			if loggedIn then span("enable:" .. addon.name, enable, addon) end
		end
	elseif event == "PLAYER_LOGIN" then
		loggedIn = true
		Everlook.Trace.Mark("login")
		for _, addon in pairs(Everlook.addons) do
			if addon.initialized and not addon.enabled then span("enable:" .. addon.name, enable, addon) end
		end
	elseif event == "PLAYER_ENTERING_WORLD" and not Everlook.Trace.Find("enter") then
		local _, isReload = ...
		Everlook.Trace.reload = isReload == true
		Everlook.Trace.Mark("enter")
	elseif event == "LOADING_SCREEN_DISABLED" and not Everlook.Trace.Find("done") then
		Everlook.Trace.Mark("done")
	end

	local set = listeners[event]
	if not set then return end
	for addon, handler in pairs(set) do
		if type(handler) == "function" then
			handler(event, ...)
		else
			addon[handler](addon, event, ...)
		end
	end
end)
