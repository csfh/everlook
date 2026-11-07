-- Font tokens: Everlook's own font objects, one per role. An Everlook addon gives its own text a
-- role with `text:SetFontObject(Everlook.Font.Body)`, and every text on a token follows it when
-- EverlookFonts changes the token's font. Only EverlookFonts sets them (AGENTS.md's ownership
-- table); without it, each token is the game's own font for its role. The sizes are a fixed scale
-- that keeps Everlook's text in proportion: an addon picks the token whose size suits its text.
--
-- The game's own text doesn't use these objects: EverlookFonts gives it the token's font file and
-- leaves each text its own size.

Everlook.FONT_TOKENS = { "Heading", "Body", "Small", "Chat", "Number" }

-- Each token starts as a copy of the game's font for its role (Blizzard_Fonts_Shared, 12.0.0), at
-- its own size in the scale: 14, 12, 10, 13 and 12 points.
Everlook.FONT_TOKEN_DEFAULTS = {
	Heading = { from = "GameFontNormalLarge", size = 14 },
	Body = { from = "GameFontHighlight", size = 12 },
	Small = { from = "GameFontHighlightSmall", size = 10 },
	Chat = { from = "ChatFontNormal", size = 13 },
	Number = { from = "NumberFontNormal", size = 12 },
}

Everlook.Font = {}
local gameFiles = {} -- [token] = the file of the game's font it was copied from

-- Copies the game's font for a token's role, once it exists; it does by the time any addon loads.
local function fromGame(name)
	if gameFiles[name] then return end
	local default = Everlook.FONT_TOKEN_DEFAULTS[name]
	local source = _G[default.from]
	if not source then return end
	local font = Everlook.Font[name]
	font:CopyFontObject(source)
	local file, _, flags = font:GetFont()
	gameFiles[name] = file
	if file then font:SetFont(file, default.size, flags or "") end
end

for _, name in ipairs(Everlook.FONT_TOKENS) do
	Everlook.Font[name] = CreateFont("EverlookFont" .. name)
	fromGame(name)
end

-- The game's own font file for a token's role, as it was before any addon changed it.
function Everlook.FontTokenGameFile(name)
	fromGame(name)
	return gameFiles[name]
end

-- Sets a token's file, nil for the game's own, at the token's size. For EverlookFonts only.
function Everlook.SetFontToken(name, file)
	local font = Everlook.Font[name]
	if not font then return end
	fromGame(name)
	local current, _, flags = font:GetFont()
	file = file or gameFiles[name] or current
	if file then font:SetFont(file, Everlook.FONT_TOKEN_DEFAULTS[name].size, flags or "") end
end
