-- Chat: the chat windows, their tabs and the input line. Each window becomes the dark solid with
-- the gold line along its bottom, the divider above the input line; the input line is a
-- solid with no line, and each tab a small solid whose line is the accent when it is selected.
local _, ns = ...
local Theme = ns.Theme
local KEY = "chat"

-- The window's border art (FloatingChatFrame.xml, 12.0.0). FCF_SetWindowAlpha sets the alpha of
-- all of these, so they are hidden rather than faded.
local BORDER = { "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
-- The tab's art (ChatTabArtTemplate). FCFTab_UpdateColors shows and hides the Active ones, so all
-- of these are faded instead.
local TAB_ART = { "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight" }
-- The input line's art (ChatFrameEditBox.xml); the focus pieces are shown and hidden by the game.
local EDIT_ART = { "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }

local function paintTab(tab, selected)
	local panel = Theme.Drawn(KEY, tab)
	if panel then Theme.Paint(panel, selected and Theme.ACCENT or Theme.ACCENT_IDLE) end
end

local function styleTab(tab)
	if not Theme.Usable(tab) then return end
	for _, key in ipairs(TAB_ART) do Theme.HideArt(KEY, tab[key], "alpha") end
	Theme.Draw(KEY, tab, function()
		-- The tab's art fills its lower part; the panel covers that.
		local panel = Theme.Panel(tab, true, true)
		panel:SetPoint("TOPLEFT", tab, "TOPLEFT", 6, -8)
		panel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 2)
		return panel
	end)
	paintTab(tab, tab.ActiveMiddle and tab.ActiveMiddle:IsShown())
end

local function styleWindow(frame)
	local name = frame:GetName()
	for _, key in ipairs(BORDER) do Theme.HideArt(KEY, _G[name .. key], "hide") end
	-- The window's dark area is its Background, which reaches past the frame over the scroll bar
	-- and the quick buttons (FloatingChatFrameMixin:UpdateBackground, 12.0.0). It gives way to
	-- the dark solid, so the window matches its tabs and input line; the window's opacity setting
	-- and its fade on mouse-out are the game's Background's, and go with it. The Background is
	-- hidden rather than faded, as FCF_SetWindowAlpha sets its alpha.
	local background = frame
	if Theme.Usable(frame.Background) then
		background = frame.Background
		Theme.HideArt(KEY, background, "hide")
	end
	Theme.Draw(KEY, frame, function()
		local panel = Theme.Panel(frame, true, true)
		panel:SetAllPoints(background)
		return panel
	end)
	local edit = _G[name .. "EditBox"]
	if Theme.Usable(edit) then
		local editName = edit:GetName()
		for _, key in ipairs(EDIT_ART) do Theme.HideArt(KEY, _G[editName .. key], "alpha") end
		Theme.Draw(KEY, edit, function()
			-- As wide as the window, right under its divider, with no line of its own. The input
			-- line is 32 tall from 4 above the Background's bottom (ChatFrameEditBox.xml,
			-- FloatingChatFrame.xml), so this solid, from that bottom to 24 below it, is centred
			-- on its text.
			local panel = Theme.Panel(edit, true, false)
			panel:SetPoint("TOPLEFT", background, "BOTTOMLEFT", 0, 0)
			panel:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", 0, -24)
			return panel
		end)
	end
	styleTab(_G[name .. "Tab"])
end

Theme:Surface({
	key = KEY,
	label = "Flat chat windows",
	help = "Replaces the chat windows' art with a gold line between the messages and the input line, "
		.. "and gives the windows, their tabs and the input line a dark solid background. "
		.. "The window's own color and opacity give way to it, and it no longer fades.",
	needs = { "CHAT_FRAMES", "FCFTab_UpdateColors" },
	optional = { "FCF_OpenTemporaryWindow" },
	frames = function()
		local list = {}
		for _, name in ipairs(CHAT_FRAMES or {}) do
			if _G[name] then list[#list + 1] = _G[name] end
		end
		return list
	end,
	style = styleWindow,
	enable = function()
		hooksecurefunc("FCFTab_UpdateColors", function(tab, selected) paintTab(tab, selected) end)
		-- A whisper window opened later is restyled with the rest.
		if FCF_OpenTemporaryWindow then
			hooksecurefunc("FCF_OpenTemporaryWindow", function() Theme:Apply(KEY) end)
		end
	end,
})
