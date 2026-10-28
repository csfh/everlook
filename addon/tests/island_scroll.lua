-- Island scroll: the slim scroll bar of a list in the open island.
return function(check, lib)
	local island_world = lib.island_world
	do
		local addon = island_world()
		local metrics = addon.island_scroll.metrics
		check("a list that fits has no scroll bar", metrics(100, 100, 0) == nil and metrics(100, 40, 0) == nil)
		local top, bottom = metrics(100, 300, 0), metrics(100, 300, 200)
		check("the thumb is a third of the track for a list three times as long", top.thumb == 33 and top.travel == 67 and top.at == 0)
		check("scrolled to the end the thumb rests at the bottom of the track", bottom.at == 67)
		check("a very long list keeps a thumb you can grab", metrics(100, 100000, 0).thumb == 24)
	end
end
