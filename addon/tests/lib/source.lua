-- Finds an addon file in the addon folder that ships it, and lists the Lua files in the order the game loads them.
-- A Lua file named on its own must be listed in that folder's TOC. Other files, such as an asset, only have to be
-- in a folder. A name that starts with a folder is used as is.
return function(root)
	local folders, where, tocs = {}, {}, {}
	local listing = assert(io.popen('ls "' .. root .. '"'))
	for folder in listing:lines() do
		if folder:match("^Everlook[%w_]*$") then
			folders[#folders + 1] = folder
			local toc = { dependencies = {}, files = {} }
			for line in io.lines(root .. "/" .. folder .. "/" .. folder .. ".toc") do
				local dependencies = line:match("^## Dependencies:%s*(.-)%s*$")
				if dependencies then
					for name in dependencies:gmatch("[^,%s]+") do toc.dependencies[#toc.dependencies + 1] = name end
				end
				local file = line:match("^([%w_]+)%.lua%s*$")
				if file then
					where[file] = folder
					toc.files[#toc.files + 1] = file
				end
			end
			tocs[folder] = toc
		end
	end
	listing:close()

	-- The game loads addons by folder name, ignoring case, each after the addons it depends on, and an addon's
	-- files in the order of its TOC.
	table.sort(folders, function(left, right) return left:lower() < right:lower() end)
	local load_order, seen = {}, {}
	local function visit(folder)
		if seen[folder] then return end
		seen[folder] = true
		for _, dependency in ipairs(tocs[folder].dependencies) do visit(dependency) end
		for _, file in ipairs(tocs[folder].files) do load_order[#load_order + 1] = file end
	end
	for _, folder in ipairs(folders) do visit(folder) end

	local function source(name)
		local folder_name = name:match("^(Everlook[%w_]*)/")
		if folder_name then return root .. "/" .. name, folder_name end
		local lua = name:match("^([%w_]+)$") or name:match("^([%w_]+)%.lua$")
		if lua then
			local folder = assert(where[lua], "No addon TOC lists " .. lua .. ".lua")
			return root .. "/" .. folder .. "/" .. lua .. ".lua", folder
		end
		for _, folder in ipairs(folders) do
			local path = root .. "/" .. folder .. "/" .. name
			local handle = io.open(path, "r")
			if handle then
				handle:close()
				return path, folder
			end
		end
		error("No addon folder has " .. name)
	end
	return source, load_order
end
