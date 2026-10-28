-- Island summary: the open island's level line and status cells, and the resting level chip, a capsule the
-- island's own source pushes as a resting status, the lowest rung under a status and a background status.
return function(check, lib)
	local island_world = lib.island_world
	local layout = lib.layout

	local function world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "reduced_motion", true)
		return addon, env, state, frames
	end

	-- The text of a visible region, as the closed pill shows it now.
	local function finder(frames)
		return function(text)
			layout.settle(frames)
			for _, frame in ipairs(frames) do
				local visible, walker = true, frame
				while walker do
					if walker.shown == false or (walker.alpha or 1) == 0 then visible = false end
					walker = walker.parent
				end
				for _, region in ipairs(frame.regions or {}) do
					if visible and region.text == text and region.shown ~= false then return region end
				end
			end
		end
	end

	local function capsule_spec() return { text = "Chip", labels = { "x" } } end

	do
		local addon, env, _, frames = world()
		local api = env.Everlook.island
		local function rejected(label, payload)
			local handle, why = api.notify(payload)
			check("a resting status is rejected: " .. label, handle == nil and why == "invalid_rank")
		end
		rejected("on a toast", { source = "A", key = "k", text = "t", rank = "resting" })
		rejected("without a capsule", { source = "A", key = "k", text = "t", presentation = "status", rank = "resting" })
		local handle = api.notify({ source = "A", key = "k", text = "t", presentation = "status", rank = "resting", capsule = capsule_spec() })
		check("with a capsule it is held", type(handle) == "number" and addon.island.view().resting.source == "A")
	end

	do
		local addon, env, _, frames = world()
		local api = env.Everlook.island
		local shown = finder(frames)
		local view = addon.island.view()
		check("the level chip is the island's own resting status", view.resting and view.resting.source == "everlook.island_resting" and shown("12") ~= nil)
		check("it is no status, history row, toast or unread notice", view.status == nil and #view.notices == 0 and #view.toasts == 0 and view.unread_count == 0)

		local background = api.notify({ source = "A", key = "bg", text = "Quest", presentation = "status", rank = "background",
			capsule = { text = "Quest", labels = { "~5 yd" } } })
		check("a background status takes the capsule from the chip", shown("Quest") ~= nil and shown("12") == nil and addon.island.view().resting ~= nil)
		local status = api.notify({ source = "A", key = "s", text = "Trip", presentation = "status", capsule = { text = "Trip" } })
		check("a status takes it from both", shown("Trip") ~= nil and shown("Quest") == nil)
		api.dismiss(status)
		check("and the background status is back when it goes", shown("Quest") ~= nil)
		api.dismiss(background)
		check("and the chip when that goes", shown("12") ~= nil)

		addon.module.set("island", "enabled", false)
		check("turning the island off clears the chip", addon.island.view().resting == nil)
		addon.module.set("island", "enabled", true)
		check("and turning it on brings it back", addon.island.view().resting ~= nil and addon.island.view().resting.count == 1)
	end

	do
		local addon, env, state, frames = world()
		local shown = finder(frames)
		addon.module.set("island", "closed_xp", true)
		check("the experience percent is a label on the chip", shown("45%") ~= nil)
		check("with one resting status, however many times it changes", addon.island.view().resting.count == 1)
		addon.module.set("island", "closed_clock", true)
		state.bags = { [0] = 0, [1] = 0 }
		addon.island.pull()
		addon.module.set("island", "low_slots", 5)
		check("gear and bags share one label, so the chip keeps within three", shown("Bags 0") ~= nil and addon.island.view().resting.count == 1)
		check("an empty bag is in the error color", math.abs(shown("Bags 0").color[2] - 128 / 255) < 0.01 and shown("Bags 0").color[1] > 0.99)
	end

	do
		local addon, env, _, frames = world()
		addon.module.set("island", "reduced_motion", false)
		layout.settle(frames)
		-- Every region that says the level, with whether it is lent out and where it hangs.
		local function level_regions()
			local found = {}
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "12" and region.shown ~= false then
						found[#found + 1] = { region = region, frame = frame }
					end
				end
			end
			return found
		end
		local resting_count = #level_regions()
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		local travelling, lent = 0, 0
		for _, entry in ipairs(level_regions()) do
			if entry.frame.name == "EverlookIslandFace" then travelling = travelling + 1 end
			if entry.region.alpha == 0 then lent = lent + 1 end
			-- It starts where the row's title is: the middle of a 64 wide pill, half the 36 height down.
			if entry.frame.name == "EverlookIslandFace" then
				local point = entry.region.point
				check("it starts on the title it replaces", point and point[1] == "CENTER" and point[4] == 32 and point[5] == -18)
			end
		end
		check("opening, a copy of the level slides and the row's own title stands aside", resting_count >= 1 and travelling == 1 and lent >= 1)
		pill.scripts.OnLeave(pill)
		layout.settle(frames)
		local still = 0
		for _, entry in ipairs(level_regions()) do
			if entry.region.alpha == 0 then still = still + 1 end
		end
		check("closed again, the row has its title back", still == 0)
	end

	-- With the experience percent on, which is how the client starts, the title sits at the left and the
	-- other parts follow it. The copy starts on that title, and a resting status of someone else's does not slide.
	do
		local addon, env, _, frames = world()
		addon.module.set("island", "reduced_motion", false)
		addon.module.set("island", "closed_xp", true)
		layout.settle(frames)
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		local copy
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookIslandFace" then
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "12" and region.shown ~= false then copy = region end
				end
			end
		end
		-- The face is 72 wide here: 12 in, the title, a 12 gap and the percent. The title is "12", two glyphs of 7.
		check("with the percent on it starts on the title at the left, 12 in and half its width over", copy and copy.point and copy.point[4] == 12 + 14 / 2 and copy.point[5] == -18)
		pill.scripts.OnLeave(pill)
		layout.settle(frames)
	end

	do
		local addon, env, _, frames = world()
		addon.module.set("island", "reduced_motion", false)
		local api = env.Everlook.island
		api.notify({ source = "Other", key = "idle", text = "Standing by", presentation = "status", rank = "resting", capsule = { text = "Standing by" } })
		layout.settle(frames)
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		local copies, title = 0, nil
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == "12" and frame.name == "EverlookIslandFace" and region.shown ~= false then copies = copies + 1 end
				if region.text == "Standing by" and region.shown ~= false then title = region end
			end
		end
		check("a resting status of someone else's does not hand its title to the level", copies == 0 and title and title.alpha ~= 0)
	end

	-- Only a capsule centers a lone title. A title on its own in a section's row stays at the left.
	do
		local addon, env, _, frames = world()
		env.Everlook.island.section({ source = "Other", key = "lone", region = "pane_b", order = 100,
			blocks = { { kind = "row", row = { title = "Alone in a row" } } } })
		local pill
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then pill = frame end end
		pill.scripts.OnEnter(pill)
		layout.settle(frames)
		local title
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == "Alone in a row" then title = region end
			end
		end
		check("a section row's lone title is left aligned", title and title.justify == "LEFT")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		local marks = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.shown ~= false and (region.path == "Interface\\Icons\\inv_misc_coin_01" or region.atlas == "SpellIcon-256x256-RepairAll") then
					marks[#marks + 1] = region
				end
			end
		end
		check("the open summary marks money and durability", #marks >= 2)
	end
	do
		local addon, env, _, state, _, _, frames = island_world()
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("island", "enabled", true)
		-- Their cells carry a ring that fills to the share.
		env.everlook_island_key("down")
		local shares = {}
		for _, frame in ipairs(frames) do
			if frame.cooldown and frame.shown == true and frame.paused then
				shares[#shares + 1] = (env.GetTime() - frame.cooldown.start) / frame.cooldown.duration
			end
		end
		table.sort(shares)
		local function near(a, b) return a and math.abs(a - b) < 1e-9 end
		check("two rings show, one for gear and one for bags", #shares == 2)
		check("durability's ring fills to its percentage", near(shares[2], 0.5))
		check("the bags ring fills to the free share", near(shares[1], 8 / 40))
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		local function label(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return region end
				end
			end
		end
		local measure = lib.layout.new()
		local function cell(text) local found = label(text); return found and measure.rectangle(found.parent) end
		check("the open summary has a Status heading", label("STATUS") ~= nil)
		local money, gear, bags = cell("Money"), cell("Gear"), cell("Bags")
		local status = measure.rectangle(label("STATUS"))
		local island
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then island = measure.rectangle(frame) end end
		-- Worked from the scale by hand: edge 12, a 20 high level row, 16 to Status, 14 high Status, 8 to the cells.
		check("the Status heading is a section gap below the level row", status.top - island.top == 12 + 20 + 16)
		-- With no quest the island is 432 wide and stacked: 408 inside the edges,
		-- one gutter of 24, so two columns of 192. Cells fill a row left to right, so money and gear
		-- share the first row and bags start the second.
		check("the island is narrow with no quest, and its cells share one width and the summary's left edge",
			addon.island.view().width == 432 and money.width == 192 and gear.width == 192 and bags.width == 192
			and money.left - island.left == 12 and bags.left - island.left == 12)
		check("gear shares money's row, to its right, and bags start the row below",
			gear.top == money.top and gear.left - island.left == 12 + 192 + 24 and bags.top == money.top + 32 + 8)
		check("the cells begin one step below the Status heading", money.top == status.top + 14 + 8)
		local name, figure = measure.rectangle(label("Gear")), measure.rectangle(label("50%"))
		check("a value sits under its name on the cell's left edge", name.left == figure.left and figure.top - name.top == 14 + 4)
		check("the summary ends one edge below the last row",
			addon.island.view().summary_height == (bags.top - island.top) + 32 + 12)
		local clock, percent = label("14:05"), label("45%")
		check("the clock moved to the header beside the percent, which is purple as on the pill",
			clock ~= nil and percent ~= nil and cell("Time") == nil and math.abs(percent.color[1] - 173 / 255) < 0.01
			and measure.rectangle(clock).right < measure.rectangle(percent).left)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		local function text_of(match)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if type(region.text) == "string" and region.text:find(match, 1, true) and region.shown ~= false then return region.text end
				end
			end
		end
		local function swipes()
			local colors = {}
			for _, frame in ipairs(frames) do
				if frame.swipe_color and frame.shown == true then colors[#colors + 1] = frame.swipe_color end
			end
			return colors
		end
		check("a healthy figure is plain white, not green: colour is for attention",
			text_of("50%") == "50%" and not text_of("|cff80e6a6"))
		check("bags read as free of the total", text_of("8 free") == "8 free of 40")
		for _, color in ipairs(swipes()) do check("a healthy ring is the quiet grey, dimmer than the caption beside it", color[1] < 0.6) end
		state.slots[1] = { 10, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		local function tone_of(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return region.color end
				end
			end
		end
		local amber = tone_of("20%")
		check("a low figure takes the warning amber", amber ~= nil and amber[1] == 1 and math.abs(amber[2] - 0.62) < 0.01)
		local warned = false
		for _, color in ipairs(swipes()) do if color[1] == 1 and math.abs(color[2] - 0.62) < 0.01 and math.abs(color[3] - 0.25) < 0.01 then warned = true end end
		check("and so does its ring", warned)
		state.slots[1] = { 2, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		local red = tone_of("4%")
		check("a dire one takes the error red", red ~= nil and red[1] == 1 and math.abs(red[2] - 0.5) < 0.01)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.C_Container.GetContainerNumSlots = function(bag) return bag <= 1 and 20 or 0 end
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		local function rings()
			local count = 0
			for _, frame in ipairs(frames) do
				if frame.cooldown and frame.shown == true then count = count + 1 end
			end
			return count
		end
		check("gear and bags each carry a ring", rings() == 2)
	end
end
