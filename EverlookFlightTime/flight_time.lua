local FlightTime = Everlook:NewAddon("EverlookFlightTime", {
	label = "Flight Time",
	defaults = {
		show = true,
		remaining = true,
		routes = {}, -- ["realm:faction:origin>destination"] = { seconds = average, samples = n }
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookFlightTime", {
	"TakeTaxiNode",
	"hooksecurefunc",
	"NumTaxiNodes",
	"TaxiNodeName",
	"TaxiNodeGetType",
	"UnitOnTaxi",
	"UnitFactionGroup",
	"GetRealmName",
	"GetTime",
	"UIParent",
})

-- A flight still in the air after a /reload keeps its timer if it started within this long.
local RESUME_WITHIN = 3 * 60 * 60

local route -- the flight being timed: { key, origin, destination, requested, started }
local interval = 0
local hooked = false

local function readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function number(value)
	return readable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function knownRoute(key)
	local known = FlightTime.db.routes[key]
	if type(known) == "table" and number(known.seconds) and known.seconds > 0 then return known end
end

function FlightTime:StopWatch()
	interval = 0
	if self.poller then self.poller:SetScript("OnUpdate", nil) end
end

-- The poller is its own frame, so hiding the timer doesn't stop the timing. It stays idle on the
-- ground: TakeTaxiNode starts it, and landing stops it.
function FlightTime:StartWatch()
	if not self.poller then return end
	self.poller:SetScript("OnUpdate", function(_, elapsed)
		interval = interval + elapsed
		if interval >= 0.25 then
			interval = 0
			self:Update()
		end
	end)
end

-- Kept in saved settings so a /reload in the air doesn't lose the timer: GetTime keeps counting
-- across a reload, and the game still says the player is on a taxi.
local function rememberRoute()
	FlightTime.db.current = { key = route.key, origin = route.origin, destination = route.destination, started = route.started }
end

local function forgetRoute()
	FlightTime.db.current = nil
end

function FlightTime:Resume()
	local saved = self.db.current
	if route or type(saved) ~= "table" then return end
	local now = GetTime()
	if not number(now) or not number(saved.started) or UnitOnTaxi("player") ~= true
		or saved.started > now or now - saved.started > RESUME_WITHIN
		or type(saved.key) ~= "string" or type(saved.origin) ~= "string" or type(saved.destination) ~= "string" then
		forgetRoute()
		return
	end
	route = { key = saved.key, origin = saved.origin, destination = saved.destination, requested = saved.started, started = saved.started }
	self:StartWatch()
end

-- Hooked on TakeTaxiNode(index): the destination is that node, the origin is the node marked CURRENT.
function FlightTime:Departure(index)
	if not self.db.show then return end
	local count = NumTaxiNodes()
	if not number(count) or count < 1 then return end
	local origin
	for node = 1, count do
		local kind = TaxiNodeGetType(node)
		if readable(kind) and kind == "CURRENT" then
			origin = TaxiNodeName(node)
			break
		end
	end
	local destination = TaxiNodeName(index)
	if not readable(origin) or not readable(destination) or type(origin) ~= "string" or type(destination) ~= "string"
		or origin == destination then return end
	local side, realm = UnitFactionGroup("player"), GetRealmName()
	if not readable(side) or not readable(realm) or type(side) ~= "string" or type(realm) ~= "string" then return end
	local now = GetTime()
	if not number(now) then return end
	route = { key = realm .. ":" .. side .. ":" .. origin .. ">" .. destination, origin = origin, destination = destination, requested = now }
	self:StartWatch()
end

function FlightTime:Update()
	if not self.db.show or not route then
		self.frame:Hide()
		self:StopWatch()
		return
	end
	local now, flying = GetTime(), UnitOnTaxi("player")
	if not number(now) or not readable(flying) or type(flying) ~= "boolean" then
		self.frame:Hide()
		return
	end

	if not flying then
		if route.started then
			-- Landed: a flight over a second long updates that route's average.
			local elapsed = now - route.started
			if elapsed > 1 then
				local previous = knownRoute(route.key)
				local samples = previous and number(previous.samples) and previous.samples > 0 and previous.samples or 0
				local total = (previous and previous.seconds or 0) * samples + elapsed
				self.db.routes[route.key] = { seconds = total / (samples + 1), samples = samples + 1 }
			end
			route = nil
			forgetRoute()
		elseif now - route.requested > 10 then
			-- Asked for a flight that never took off.
			route = nil
		end
		self.frame:Hide()
		if not route then self:StopWatch() end
		return
	end

	if not route.started then
		route.started = now
		rememberRoute()
	end
	local elapsed = now - route.started
	if elapsed < 0 then
		self.frame:Hide()
		return
	end
	local text = route.destination .. "  " .. duration(elapsed)
	local known = knownRoute(route.key)
	if known and self.db.remaining then
		text = text .. "  (~" .. duration(known.seconds - elapsed) .. " left)"
	end
	self.label:SetText(text)
	self.frame:Show()
end

function FlightTime:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "World & Camera")
	page:Checkbox("show", "Show a flight timer",
		"Shows the destination and time in the air at the top of the screen while you fly, and learns how long each route takes.")
	page:Checkbox("remaining", "Show time remaining",
		"Adds the expected time left once you've flown the route before. Needs Show a flight timer.")
end

function FlightTime:OnEnable()
	local frame = CreateFrame("Frame", "EverlookFlightTimeFrame", UIParent)
	frame:SetSize(400, 28)
	frame:SetPoint("TOP", 0, -150)
	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER")
	frame:Hide()
	self.frame, self.label = frame, label
	self.poller = CreateFrame("Frame", "EverlookFlightTimePoller")

	if not hooked then
		hooksecurefunc("TakeTaxiNode", function(index) self:Departure(index) end)
		hooked = true
	end
	if self.db.show then self:Resume() end
end

function FlightTime:OnSettingChanged(key, value)
	if key ~= "show" then return end
	if value then
		self:Resume()
	else
		-- Turning it off mid-flight throws that measurement away.
		route = nil
		forgetRoute()
		self.frame:Hide()
		self:StopWatch()
	end
end
