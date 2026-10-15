local GameId = 155615604
local Tab, Toolx = ...

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local alive = true
local espOn = false
local highlights = {}

local function remoteNamed(name)
	local folder = workspace:FindFirstChild("Remote")
	return folder and folder:FindFirstChild(name)
end

local function clearHighlight(plr)
	if highlights[plr] then
		highlights[plr]:Destroy()
		highlights[plr] = nil
	end
end

---------------------------------------------------------------------
-- Teams
---------------------------------------------------------------------
Tab:Section("Teams")
local myTeamRow = Tab:InfoRow("Your team", "...")
local countsRow = Tab:InfoRow("Players", "...")

local function switchTeam(teamColor, label)
	local event = remoteNamed("TeamEvent")
	if not event then
		Toolx.Notify("Couldn't find the team remote", "error")
		return
	end
	event:FireServer(teamColor)
	Toolx.Notify("Asked to join " .. label, "info")
end

Tab:Button("Join Inmates", function()
	switchTeam("Bright orange", "Inmates")
end)
Tab:Button("Join Guards", function()
	switchTeam("Bright blue", "Guards")
end)

---------------------------------------------------------------------
-- ESP
---------------------------------------------------------------------
Tab:Section("ESP")
Tab:Toggle("Team ESP", false, function(on)
	espOn = on
	if not on then
		for plr in pairs(highlights) do
			clearHighlight(plr)
		end
	end
end, "prison.esp")
Tab:Label("Players are outlined in their team colour: orange inmates, blue guards, red criminals.")

---------------------------------------------------------------------
-- Weapons (read from the game, so the list always matches what is in the map)
---------------------------------------------------------------------
Tab:Section("Weapons")
Tab:Label("Tap a weapon to ask the game for it. Some need a gamepass or the right team.")
local weaponBox = Tab:LogBox(130, 30, "No weapons found. Tap Refresh.")

local function giverItems()
	local items = workspace:FindFirstChild("Prison_ITEMS")
	local giver = items and items:FindFirstChild("giver")
	return giver and giver:GetChildren() or {}
end

local function grab(item)
	local pickup = item:FindFirstChild("ITEMPICKUP")
	local handler = remoteNamed("ItemHandler")
	if not (pickup and handler) then
		return false
	end
	return (pcall(function()
		handler:InvokeServer(pickup)
	end))
end

local function refreshWeapons()
	weaponBox.Clear()
	for _, item in ipairs(giverItems()) do
		local name = item.Name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		weaponBox.Add(name, function()
			return grab(item) and "Requested!" or "Failed"
		end)
	end
end

Tab:Button("Refresh weapon list", refreshWeapons)
Tab:Button("Get all weapons", function()
	local count = 0
	for _, item in ipairs(giverItems()) do
		if grab(item) then
			count += 1
		end
	end
	Toolx.Notify("Requested " .. count .. " weapons", count > 0 and "success" or "warn")
end)
refreshWeapons()

---------------------------------------------------------------------
-- Update loop
---------------------------------------------------------------------
local function update()
	local counts = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local team = plr.Team
		local teamName = team and team.Name or "Neutral"
		counts[teamName] = (counts[teamName] or 0) + 1

		local char = plr.Character
		if plr ~= player and espOn and char and team then
			local h = highlights[plr]
			if not h or h.Parent ~= char then
				clearHighlight(plr)
				h = Instance.new("Highlight")
				h.Adornee = char
				h.FillTransparency = 0.5
				h.OutlineTransparency = 0
				h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				h.Parent = char
				highlights[plr] = h
			end
			h.FillColor = team.TeamColor.Color
			h.OutlineColor = team.TeamColor.Color
		else
			clearHighlight(plr)
		end
	end

	myTeamRow.Set(player.Team and player.Team.Name or "Neutral")
	local parts = {}
	for _, name in ipairs({ "Inmates", "Guards", "Criminals" }) do
		table.insert(parts, name:sub(1, 1) .. ":" .. (counts[name] or 0))
	end
	countsRow.Set(table.concat(parts, "  "))
end

local leaving = Players.PlayerRemoving:Connect(clearHighlight)

task.spawn(function()
	while alive do
		pcall(update)
		task.wait(0.5)
	end
end)

Tab:OnUnload(function()
	alive = false
	leaving:Disconnect()
	for plr in pairs(highlights) do
		clearHighlight(plr)
	end
end)
