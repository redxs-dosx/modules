local GameId = 10563114921 -- Steal An Egg (universe id; Settings > Info shows the ids of the game you're in)
--[[
	Toolx module: Steal An Egg
	Loaded by the Module tab as  fn(Tab, Toolx, info)  when you join the game (first line = GameId).

	I don't have the game's real object / remote names, so this finds eggs by NAME: anything in workspace whose name
	contains one of the keywords (default "egg"). If it picks up the wrong things or misses the real eggs, change the
	keywords in the tab, then run "Scan game" and look at what the game actually calls things.
]]

local Tab, Toolx = ...

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local alive = true
local keywords = { "egg" }
local espOn, autoOn = false, false
local grabRange = 15
local eggs = {} -- { { obj = Instance, pos = Vector3 } }, refreshed by the scanner
local espItems = {} -- egg instance -> { gui, label, hl }
local lastFire = {} -- prompt -> os.clock() of the last time we fired it
local lastReport = ""

local GOLD = Color3.fromRGB(255, 214, 10)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function notify(text, kind)
	if Toolx and Toolx.Notify then
		Toolx.Notify(text, kind)
	end
end

local function flash(lbl, text)
	if not lbl or not lbl.Parent then
		return
	end
	local original = lbl.Text
	lbl.Text = text
	task.delay(1.2, function()
		if lbl.Parent then
			lbl.Text = original
		end
	end)
end

local function esc(s)
	s = tostring(s)
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function posOf(obj)
	if obj:IsA("Model") then
		local ok, cf = pcall(obj.GetPivot, obj)
		return ok and cf.Position or nil
	elseif obj:IsA("BasePart") then
		return obj.Position
	end
	return nil
end

local function setKeywords(text)
	local list = {}
	for word in string.gmatch(tostring(text), "[^,]+") do
		word = string.lower(string.match(word, "^%s*(.-)%s*$"))
		if word ~= "" then
			table.insert(list, word)
		end
	end
	if #list == 0 then
		list = { "egg" }
	end
	keywords = list
end

local function nameMatches(name)
	name = string.lower(name)
	for _, k in ipairs(keywords) do
		if string.find(name, k, 1, true) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------
-- Finding eggs (by name, outermost match only)
---------------------------------------------------------------------
local function scanEggs()
	local found = {}
	local camera = workspace.CurrentCamera
	local myChar = player.Character
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		n += 1
		if n % 1500 == 0 then
			task.wait() -- spread the work over a few frames so it doesn't hitch
			if not alive then
				return nil
			end
		end
		if (d:IsA("Model") or d:IsA("BasePart")) and nameMatches(d.Name) and d ~= myChar then
			local skip = false
			local p = d.Parent
			while p and p ~= workspace do
				if p == camera or p == myChar or (p:IsA("Model") and nameMatches(p.Name)) then
					skip = true
					break
				end
				p = p.Parent
			end
			if not skip then
				local pos = posOf(d)
				if pos then
					table.insert(found, { obj = d, pos = pos })
				end
			end
		end
	end
	return found
end

local function rescan()
	local found = scanEggs()
	if found and alive then
		eggs = found
	end
end

local function nearestEgg()
	local root = getRoot()
	if not root then
		return nil
	end
	local best, bestDist
	for _, item in ipairs(eggs) do
		if item.obj.Parent then
			local pos = posOf(item.obj)
			if pos then
				item.pos = pos
				local dist = (pos - root.Position).Magnitude
				if not bestDist or dist < bestDist then
					best, bestDist = item, dist
				end
			end
		end
	end
	return best, bestDist
end

local function teleportToNearest()
	if #eggs == 0 then
		rescan()
	end
	local item = nearestEgg()
	local root = getRoot()
	if not item or not root then
		return false
	end
	root.CFrame = CFrame.new(item.pos + Vector3.new(0, 4, 0))
	return true
end

---------------------------------------------------------------------
-- ESP
---------------------------------------------------------------------
local espFolder = Instance.new("Folder")
espFolder.Name = "ToolxEggESP"
do
	local host = Toolx and Toolx.Gui
	espFolder.Parent = (host and host.Parent) or host or game:GetService("CoreGui")
end

local function destroyEsp(e)
	if e then
		e.gui:Destroy()
		if e.hl then
			e.hl:Destroy()
		end
	end
end

local function makeEsp(obj)
	local adornee = obj
	if obj:IsA("Model") then
		adornee = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
	end
	if not adornee then
		return nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "EggTag"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(170, 34)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.Parent = espFolder

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.4
	label.Text = obj.Name
	label.Parent = gui

	local hl
	pcall(function()
		hl = Instance.new("Highlight")
		hl.Adornee = obj
		hl.FillColor = GOLD
		hl.OutlineColor = GOLD
		hl.FillTransparency = 0.75
		hl.Parent = espFolder
	end)

	return { gui = gui, label = label, hl = hl }
end

-- creates / updates tags for the eggs we know about, removes the rest (everything goes when ESP is off)
local function refreshEsp(root)
	local seen = {}
	if espOn then
		for _, item in ipairs(eggs) do
			local obj = item.obj
			if obj.Parent then
				seen[obj] = true
				local e = espItems[obj]
				if not e then
					e = makeEsp(obj)
					espItems[obj] = e
				end
				if e then
					local pos = posOf(obj)
					local dist = (root and pos) and math.floor((pos - root.Position).Magnitude + 0.5)
					e.label.Text = obj.Name .. (dist and ("\n" .. dist .. " studs") or "")
				end
			end
		end
	end
	for obj, e in pairs(espItems) do
		if not seen[obj] then
			destroyEsp(e)
			espItems[obj] = nil
		end
	end
end

---------------------------------------------------------------------
-- Auto grab: fires the ProximityPrompts that belong to nearby eggs
---------------------------------------------------------------------
local function promptPosition(prompt)
	local parent = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function autoGrab(root)
	if not autoOn or not root then
		return
	end
	local now = os.clock()
	for _, item in ipairs(eggs) do
		local obj = item.obj
		if obj.Parent then
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.Enabled then
					local ppos = promptPosition(d)
					if ppos and (ppos - root.Position).Magnitude <= grabRange and (now - (lastFire[d] or 0)) > 0.6 then
						lastFire[d] = now
						pcall(fireproximityprompt, d)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Scan report (so the module can be tailored to the real game)
---------------------------------------------------------------------
local log -- LogBox, created below

local function runScan()
	local lines = {}
	local function add(text)
		table.insert(lines, text)
	end

	add("Place " .. game.PlaceId .. " / Game " .. game.GameId)

	-- player values
	local stats = {}
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, v in ipairs(leaderstats:GetChildren()) do
			if v:IsA("ValueBase") then
				table.insert(stats, v.Name .. "=" .. tostring(v.Value))
			end
		end
	end
	for name, value in pairs(player:GetAttributes()) do
		table.insert(stats, name .. "=" .. tostring(value))
	end
	add("Player values: " .. (#stats > 0 and table.concat(stats, ", ") or "none"))

	-- things matching the keywords
	local found = scanEggs()
	if found then
		eggs = found
	end
	add("Eggs (" .. table.concat(keywords, ", ") .. "): " .. #eggs)
	for i, item in ipairs(eggs) do
		if i > 25 then
			add("  ...")
			break
		end
		add("  " .. item.obj.ClassName .. " " .. item.obj:GetFullName())
	end

	-- proximity prompts, grouped by their text
	local groups, order, total, n = {}, {}, 0, 0
	for _, d in ipairs(workspace:GetDescendants()) do
		n += 1
		if n % 1500 == 0 then
			task.wait()
		end
		if d:IsA("ProximityPrompt") then
			total += 1
			local key = d.ActionText .. " | " .. d.ObjectText
			local g = groups[key]
			if not g then
				g = { count = 0, example = d:GetFullName(), hold = d.HoldDuration }
				groups[key] = g
				table.insert(order, key)
			end
			g.count += 1
		end
	end
	add("ProximityPrompts: " .. total)
	for i, key in ipairs(order) do
		if i > 20 then
			add("  ...")
			break
		end
		local g = groups[key]
		add(string.format("  x%d [%s] hold %.1fs  e.g. %s", g.count, key, g.hold, g.example))
	end

	-- remotes
	local remotes = {}
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
			table.insert(remotes, d.ClassName .. " " .. d:GetFullName())
		end
	end
	add("Remotes in ReplicatedStorage: " .. #remotes)
	for i, text in ipairs(remotes) do
		if i > 50 then
			add("  ...")
			break
		end
		add("  " .. text)
	end

	-- what sits directly in workspace
	local top, topOrder = {}, {}
	for _, c in ipairs(workspace:GetChildren()) do
		local key = c.Name .. " (" .. c.ClassName .. ")"
		if not top[key] then
			top[key] = 0
			table.insert(topOrder, key)
		end
		top[key] += 1
	end
	add("Workspace children:")
	for i, key in ipairs(topOrder) do
		if i > 40 then
			add("  ...")
			break
		end
		add("  " .. key .. (top[key] > 1 and (" x" .. top[key]) or ""))
	end

	lastReport = table.concat(lines, "\n")
	if log then
		log.Clear()
		for _, line in ipairs(lines) do
			log.Add(esc(line))
		end
	end
end

---------------------------------------------------------------------
-- Gui
---------------------------------------------------------------------
Tab:Section("Eggs")
local nearestRow = Tab:InfoRow("Nearest egg", "scanning...")
local countRow = Tab:InfoRow("Eggs found", "0")

local espToggle = Tab:Toggle("Egg ESP", false, function(state)
	espOn = state
end, "stealegg.esp")

Tab:Button("Teleport to nearest egg", function(lbl)
	flash(lbl, teleportToNearest() and "Teleported" or "No egg found")
end)

local autoToggle
autoToggle = Tab:Toggle("Auto grab nearby eggs", false, function(state)
	if state and typeof(fireproximityprompt) ~= "function" then
		notify("Your executor has no fireproximityprompt", "error")
		autoOn = false
		task.defer(function()
			if alive and autoToggle then
				autoToggle.Set(false, true)
			end
		end)
		return
	end
	autoOn = state
end, "stealegg.auto")

Tab:Slider("Grab range (studs)", 5, 40, 15, function(v)
	grabRange = v
end, "stealegg.range")

local words = Tab:TextInput("Egg keywords", "egg, nest", function(text)
	setKeywords(text)
	task.spawn(rescan)
end)
words.Set("egg")
Tab:Label("Eggs are found by name: anything in workspace whose name contains one of these words (comma separated). Auto grab fires the ProximityPrompts inside nearby eggs, it needs an executor with fireproximityprompt.")

Tab:Section("Debug")
Tab:Button("Scan game", function(lbl)
	flash(lbl, "Scanning...")
	runScan()
	flash(lbl, "Done")
end)
Tab:Button("Copy scan", function(lbl)
	local setclip = setclipboard or toclipboard
	if lastReport == "" then
		flash(lbl, "Run a scan first")
	elseif typeof(setclip) == "function" and pcall(setclip, lastReport) then
		flash(lbl, "Copied!")
	else
		flash(lbl, "No clipboard access")
	end
end)
log = Tab:LogBox(170, 120, "Run a scan to see eggs, prompts and remotes")
Tab:Label("Scan lists what matches the keywords, every ProximityPrompt, the remotes in ReplicatedStorage and what sits in workspace. Copy it and send it over to tailor this module to the game.")

---------------------------------------------------------------------
-- Cmdbar commands
---------------------------------------------------------------------
if Toolx and typeof(Toolx.AddCommand) == "function" then
	local function guard(fn)
		return function(args)
			if not alive then
				notify("The Steal An Egg module isn't loaded", "warn")
				return
			end
			fn(args)
		end
	end
	Toolx.AddCommand("eggesp", "", "Toggle the egg ESP", guard(function()
		espToggle.Set(not espToggle.Get())
	end), { "eesp" })
	Toolx.AddCommand("autoegg", "", "Toggle auto grab for nearby eggs", guard(function()
		autoToggle.Set(not autoToggle.Get())
	end))
	Toolx.AddCommand("gotoegg", "", "Teleport to the nearest egg", guard(function()
		if not teleportToNearest() then
			notify("No egg found", "warn")
		end
	end), { "egg" })
	Toolx.AddCommand("eggscan", "", "Scan the game for eggs, prompts and remotes", guard(function()
		runScan()
		notify("Scan done, see the module tab", "success")
	end))
end

---------------------------------------------------------------------
-- Loops + cleanup
---------------------------------------------------------------------
task.spawn(function()
	while alive do
		rescan()
		-- scanning walks the whole workspace, so it runs less often when nothing needs fresh results
		local waited, interval = 0, (espOn or autoOn) and 2.5 or 10
		while alive and waited < interval do
			task.wait(0.5)
			waited += 0.5
		end
	end
end)

task.spawn(function()
	local warned = false
	while alive do
		local ok, err = pcall(function()
			local root = getRoot()
			local item, dist = nearestEgg()
			nearestRow.Set(item and (item.obj.Name .. "  (" .. math.floor(dist + 0.5) .. " studs)") or "none")
			countRow.Set(tostring(#eggs))
			refreshEsp(root)
			autoGrab(root)
		end)
		if not ok and not warned then
			warned = true
			warn("[Toolx] Steal An Egg module: " .. tostring(err))
		end
		task.wait(0.25)
	end
end)

Tab:OnUnload(function()
	alive = false
	for _, e in pairs(espItems) do
		destroyEsp(e)
	end
	table.clear(espItems)
	espFolder:Destroy()
end)
