-- Minimap coordinates: shows where you are on the current map, under the minimap, as the horizontal position and then the vertical one, each with one decimal, and keeps that line current while you move.
return function(root, check, lib)
	local load_files = lib.load_files
	local addon, play, fire = load_files({ "world", "module", "minimap_coordinates" })
	check("coordinates format a map position", addon.minimap_coordinates.format(0.5, 0.25) == "50.0, 25.0")
	check("coordinates stay blank without a position", addon.minimap_coordinates.format(nil, 0.2) == "")
	play.C_Map = {}
	check("coordinates stay blank without a map position", addon.minimap_coordinates.player_text() == "")
	play.C_Map = {
		GetBestMapForUnit = function() return 37 end,
		GetPlayerMapPosition = function()
			return { x = 0.5, y = 0.25 }
		end,
	}
	check("coordinates read a table position", addon.minimap_coordinates.player_text() == "50.0, 25.0")
	play.C_Map.GetPlayerMapPosition = function()
		return { GetXY = function() return 0.2, 0.4 end }
	end
	check("coordinates read a vector position", addon.minimap_coordinates.player_text() == "20.0, 40.0")
	play.C_Map.GetPlayerMapPosition = function() return nil end
	check("coordinates are blank when the client gives no position", addon.minimap_coordinates.player_text() == "")
	play.C_Map.GetPlayerMapPosition = function()
		return { GetXY = function() return nil, nil end }
	end
	check("coordinates are blank when the position has no numbers", addon.minimap_coordinates.player_text() == "")
	play.C_Map = nil
	play.Minimap = {}
	addon.module.set("minimap_coordinates", "enabled", true)
	addon.module.set("minimap_coordinates", "enabled", false)
	check("turning coordinates off stops the ticker", play.tickers[#play.tickers].cancelled)
end
