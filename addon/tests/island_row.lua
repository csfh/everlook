-- Island row: where each part of the closed pill's row hangs, and how a title too long for it takes the longest
-- wording that fits, then a cut at a word, never inside one.
return function(root, check, lib)
	local source, quest_world = lib.source, lib.quest_world
	local Everlook = {}
	local env = setmetatable({ Everlook = Everlook }, { __index = _G })
	env._G = env
	for _, file in ipairs({ "world", "island_row" }) do
		local chunk = assert(loadfile(source(file)))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
	end
	local fit = Everlook.island_row.fit
	local function width(text) return #text * 6 end

	check("the first wording that fits wins, so the longest is kept when it fits", fit({ "Gathering Idols in the Barrens", "Gathering Idols" }, 200, width) == "Gathering Idols in the Barrens")
	check("a shorter wording is taken when the longer does not fit", fit({ "Gathering Idols in the Barrens", "Gathering Idols" }, 100, width) == "Gathering Idols")
	check("a plain string is one wording", fit("Gathering Idols", 200, width) == "Gathering Idols")
	check("with nothing that fits, the last wording is cut at a word", fit({ "Gathering Idols in the Barrens", "Gathering Idols of Kolkar" }, 110, width) == "Gathering Idols...")
	check("it never cuts inside a word", (function()
		for room = 0, 200, 3 do
			local text = fit("Gathering Idols of Kolkar", room, width)
			local body = text:gsub("%.%.%.$", "")
			local ok = body == "" or ("Gathering Idols of Kolkar"):sub(1, #body) == body and (("Gathering Idols of Kolkar"):sub(#body + 1, #body + 1) == " " or #body == #"Gathering Idols of Kolkar")
			if body:sub(-1) == " " then ok = false end
			if not ok then return false end
		end
		return true
	end)())
	check("a room that holds only the dots gets the dots, and less gets nothing", fit("Gathering Idols", 18, width) == "..." and fit("Gathering Idols", 10, width) == "")
	check("no wording gives nothing", fit({}, 100, width) == "" and fit(nil, 100, width) == "")
	check("a one-word title too wide for its room is the dots, not half the word", fit("Gathering", 40, width) == "..." or fit("Gathering", 40, width) == "")

	local natural = Everlook.island_row.natural_width({ title = { "Longer wording", "Short" } }, function(text) return width(text) end, 14, 0)
	check("a row asks for the width of its longest wording", natural >= width("Longer wording"))
	do
		local addon = quest_world()
		local island_row = addon.island_row
		local function region()
			local r = { points = {}, shown = false }
			function r:ClearAllPoints() self.points = {} end
			function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function r:SetText(text) self.text = text end
			function r:GetStringWidth() return #(self.text or "") * 5 end
			function r:Show() self.shown = true end
			function r:Hide() self.shown = false end
			function r:SetSize() end
			function r:SetTextColor(...) self.color = { ... } end
			function r:SetMaxLines() end
			function r:CreateTexture() return region() end
			function r:SetAtlas() end
			function r:SetTexture() end
			function r:SetVertexColor() end
			function r:SetSnapToPixelGrid() end
			function r:SetTexelSnappingBias() end
			function r:SetRotation(angle) self.rotation = angle end
			return r
		end
		local parent = region()
		local rings = { made = 0 }
		function rings.make() local ring = { track = region(), fill = region() }; rings.ring = ring; return ring end
		function rings.set(ring, fraction, tone) rings.fraction, rings.tone = fraction, tone; ring.track:Show() end
		function rings.hide(ring) ring.track:Hide() end
		function rings.chain(ring, following, gap, point) ring.track.points = { { "RIGHT", following, point or "LEFT", -gap, 0 } } end
		local made = island_row.new(parent, { label = function() return region() end, rings = rings, ring_size = 14 })
		made:set({ icon = "quest", title = "Gathering Idols", ring = { fraction = 0.5, tone = { 1, 1, 1 } },
			labels = { "~32 yd", { text = "20", tone = { 1, 0.9, 0.2 } } }, badge = "73%" }, 0)
		local badge, second, first = made.badge, made.labels[2], made.labels[1]
		check("the badge hangs from the right edge and each label from the part after it",
			badge.points[1][2] == parent and badge.points[1][4] == -12 and second.points[1][2] == badge and first.points[1][2] == second
			and second.points[1][4] == -12)
		check("the ring hangs from the first label and the title is held between the lead and the ring",
			rings.ring.track.points[1][2] == first and made.title.points[1][3] == "LEFT" and made.title.points[1][4] == 34
			and made.title.points[2][2] == rings.ring.track and made.title.points[2][4] == -12)
		check("a label takes its own tone", second.color and second.color[2] == 0.9)
		made:set({ labels = { "a", "b" } }, 0)
		check("a label set without a tone leaves the last tone behind", made.labels[2].color[1] == 174 / 255)
		made:set({ icon = "quest", title = "Gathering Idols", badge = "73%" }, 14)
		check("a part the spec leaves out is hidden and the parts that stay close the gap",
			first.shown == false and second.shown == false and rings.ring.track.shown == false
			and badge.points[1][4] == -26 and made.title.points[2][2] == badge)
		made:aim(1.5)
		check("an aimed arrow turns and shows in place of the icon", made.arrow.rotation == 1.5 and made.arrow.shown and made.icon.shown == false)
		made:aim(nil)
		check("without an angle the arrow hides and the icon returns", made.arrow.shown == false and made.icon.shown == true)
		made:set({ title = "Alone" }, 0)
		check("a row with no lead starts its title at the edge and runs it to the other edge",
			made.title.points[1][4] == 12 and made.title.points[2][2] == parent and made.title.points[2][3] == "RIGHT")
	end
end
