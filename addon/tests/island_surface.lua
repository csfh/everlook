-- Island surface: the rounded body, its opacity and the game's tooltip border.
return function(_, check, lib)
	local island_world = lib.island_world
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local function surface_alphas()
			local alphas = {}
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.color and region.color[1] == 13 / 255 then alphas[#alphas + 1] = region.color[4] end
				end
			end
			return alphas
		end
		local before = surface_alphas()
		check("the island surface starts at 96 percent", #before > 0 and before[1] == 0.96)
		addon.module.set("island", "opacity", 82)
		local after = surface_alphas()
		check("the opacity option retints the surfaces already built", #after == #before and after[1] == 0.82)
	end
	do
		local addon, env = island_world()
		local applied, centers = 0, {}
		env.NineSliceUtil = {
			GetLayout = function(name) return name == "TooltipDefaultLayout" and {} or nil end,
			ApplyLayoutByName = function(container, name)
				applied = applied + 1
				container.Center = { SetVertexColor = function(self, ...) self.color = { ... } end }
				centers[#centers + 1] = container.Center
			end,
		}
		addon.module.set("island", "enabled", true)
		check("the island borrows the game's tooltip border when it exists", applied >= 3 and centers[1].color ~= nil)
		addon.module.set("island", "opacity", 84)
		check("the opacity option tints the native fill", centers[1].color[4] == 0.84)
	end
end
