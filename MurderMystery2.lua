local GameId = 142823291
local Tab, Toolx = ...

local Players = game:GetService("Players")
local player = Players.LocalPlayer

local COLORS = {
	Murderer = Color3.fromRGB(235, 60, 60),
	Sheriff = Color3.fromRGB(70, 130, 255),
	Innocent = Color3.fromRGB(80, 200, 120),
}

local espOn = false
local showInnocents = true
local highlights = {}
local alive = true

-- Murderer holds the Knife, Sheriff holds the Gun (either in the backpack or equipped)
local function hasTool(plr, name)
	local backpack = plr:FindFirstChild("Backpack")
	return (backpack and backpack:FindFirstChild(name) ~= nil)
		or (plr.Character and plr.Character:FindFirstChild(name) ~= nil)
end

local function roleOf(plr)
	if hasTool(plr, "Knife") then
		return "Murderer"
	elseif hasTool(plr, "Gun") then
		return "Sheriff"
	end
	return "Innocent"
end

local function clearHighlight(plr)
	if highlights[plr] then
		highlights[plr]:Destroy()
		highlights[plr] = nil
	end
end

Tab:Section("Roles")
local murdererRow = Tab:InfoRow("Murderer", "Unknown")
local sheriffRow = Tab:InfoRow("Sheriff", "Unknown")

Tab:Section("ESP")
Tab:Toggle("Role ESP", false, function(on)
	espOn = on
	if not on then
		for plr in pairs(highlights) do
			clearHighlight(plr)
		end
	end
end, "mm2.esp")
Tab:Toggle("Show innocents", true, function(on)
	showInnocents = on
end, "mm2.innocents")

Tab:Section("Utilities")
Tab:Button("Teleport to dropped gun", function()
	local gun = workspace:FindFirstChild("GunDrop", true)
	local char = player.Character
	if gun and gun:IsA("BasePart") and char then
		char:PivotTo(gun.CFrame + Vector3.new(0, 3, 0))
		Toolx.Notify("Teleported to the gun", "success")
	else
		Toolx.Notify("No gun has been dropped", "warn")
	end
end)

local function update()
	local murderer, sheriff
	for _, plr in ipairs(Players:GetPlayers()) do
		local role = roleOf(plr)
		if role == "Murderer" then
			murderer = plr.DisplayName
		elseif role == "Sheriff" then
			sheriff = plr.DisplayName
		end

		local char = plr.Character
		if plr ~= player and espOn and char and (showInnocents or role ~= "Innocent") then
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
			h.FillColor = COLORS[role]
			h.OutlineColor = COLORS[role]
		else
			clearHighlight(plr)
		end
	end
	murdererRow.Set(murderer or "Unknown")
	sheriffRow.Set(sheriff or "Unknown")
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
