local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Grouped state/tables (keeps the main chunk under Luau's 200-local limit)
local S = {
	-- Main Locals
	lootHighlightsOn = true,
	entityHighlightsOn = true,
	playersHighlightsOn = true,
	includeSelf = false,
	playersActive = false,
	scanning = false,
	modelHighlightsOn = true,
	partThreshold = 50,
	ignoreAccessories = true,
	AllowToasts = true,
	-- Version Locals
	CURRENT_VERSION = "1.0.4",
	IsBeta = true,
	VERSION_URL = "https://raw.githubusercontent.com/AnyLisa/LOOT-StealOrDIe/refs/heads/main/version.json"
}


local F = {} -- forward-declared functions
local D = {} -- window dimensions
local TI = {} -- tween infos

----------------------------------------------------------------------
-- >>> CONFIG (these are only the defaults, everything is editable in the GUI) <<<
----------------------------------------------------------------------
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local RARITY_ATTRIBUTE = "Rarity"

-- Highlight color overrides. Anything not listed uses the game's own color.
-- (The game's Secret color is near-black, so it's overridden with white.)
local COLOR_OVERRIDES = {
	Secret = Color3.fromRGB(255, 255, 255),
}

local function OK_(TEXT_)
	print("[ ✓ ] " .. TEXT_)
end

local function INFO_(TEXT_)
	print("[ i ] " .. TEXT_)
end

local function WARN_(TEXT_)
	print("[ ⚠️ ] " .. TEXT_)
end

-- Which rarities are shown / highlighted (toggle them in the Loot page too)
local SHOW_RARITIES = {
	Common = false,
	Uncommon = false,
	Rare = false,
	Mythic = true,
	Legendary = true,
	Secret = true,
}

-- Entities. name = exact Instance name, enabled = scanned, color = highlight color
local ENTITIES = {
	{ name = "The Locust", enabled = true, color = Color3.fromRGB(70, 200, 255) },
	{ name = "The Maternal Wraith", enabled = true, color = Color3.fromRGB(70, 200, 255) },
	{ name = "The Hollow", enabled = true, color = Color3.fromRGB(70, 200, 255) },
	{ name = "The Rictus", enabled = true, color = Color3.fromRGB(70, 200, 255) },
	{ name = "The Wendell", enabled = true, color = Color3.fromRGB(70, 200, 255) },
}

-- Keep an immutable snapshot of source defaults. Older saved configs may not
-- contain entities added to this table later, so those defaults can be merged
-- into a loaded config instead of being silently lost.
local DEFAULT_ENTITIES = {}
for _, entity in ipairs(ENTITIES) do
	table.insert(DEFAULT_ENTITIES, {
		name = entity.name,
		enabled = entity.enabled,
		color = entity.color,
	})
end

-- Colors the entity swatch cycles through when you click it
local PALETTE = {
	Color3.fromRGB(255, 70, 70),
	Color3.fromRGB(255, 150, 30),
	Color3.fromRGB(255, 220, 60),
	Color3.fromRGB(90, 230, 120),
	Color3.fromRGB(70, 200, 255),
	Color3.fromRGB(90, 130, 255),
	Color3.fromRGB(190, 90, 255),
	Color3.fromRGB(255, 100, 200),
	Color3.fromRGB(255, 255, 255),
}

-- Default slider values (Settings page)
local SETTINGS = {
	maxHighlights = 31, -- Roblox only renders ~31 highlights at once
	maxRows = 100,
	fillTransparency = 0.65,
	minValue = 200,
}

local SCAN_ROOTS = { workspace }

-- Player highlight colors
local PLAYER_COLORS = {
	Survivor = Color3.fromRGB(90, 230, 120),
	Entity = Color3.fromRGB(235, 32, 24),
}

-- Pinned loot highlight color
local PIN_COLOR = Color3.fromRGB(255, 215, 0)

-- A player with MORE parts than this is marked as an Entity (editable in Settings)

-- Don't count Accessories / Hats / Tools when counting parts (big cause of false Entities)

-- Auto scan: runs <delay> seconds after workspace.ActiveMap is removed and added again
local MAP_NAME = "ActiveMap"
local autoScan = { enabled = false, delay = 10 }

-- Config files are saved in <executor workspace>/LootDash/<name>.json
local CONFIG_FOLDER = "LootDash"

-- Press this key to hide / show the window
local TOGGLE_KEY = Enum.KeyCode.Delete


-- Built from GameConfig.Rarities (lowest -> highest value)
local RARITIES = {}
local RARITY_INDEX = {}
for index, rarity in ipairs(GameConfig.Rarities) do
	RARITIES[index] = { name = rarity.name, color = COLOR_OVERRIDES[rarity.name] or rarity.colour }
	RARITY_INDEX[rarity.name] = index
end

----------------------------------------------------------------------
-- Theme
----------------------------------------------------------------------
D.WIDTH, D.HEIGHT, D.HEADER, D.SIDEBAR = 800, 520, 44, 170
D.FADE_ROWS = 20

local C = {
	bg = Color3.fromRGB(11, 11, 13),
	panel = Color3.fromRGB(18, 18, 21),
	panel2 = Color3.fromRGB(30, 30, 35),
	stroke = Color3.fromRGB(36, 36, 42),
	text = Color3.fromRGB(226, 226, 232),
	sub = Color3.fromRGB(112, 112, 124),
	accent = Color3.fromRGB(235, 32, 24),
	accentDark = Color3.fromRGB(110, 14, 10),
}

TI.FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TI.SMOOTH = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function tween(obj, info, props)
	local t = TweenService:Create(obj, info, props)
	t:Play()
	return t
end

local function make(class, props, parent)
	local obj = Instance.new(class)
	for key, value in pairs(props) do
		obj[key] = value
	end
	obj.Parent = parent
	return obj
end

local function round(parent, radius)
	return make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function outline(parent, color)
	return make("UIStroke", {
		Color = color or C.stroke,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(props, parent)
	local p = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}
	for key, value in pairs(props) do
		p[key] = value
	end
	return make("TextLabel", p, parent)
end

local function makeButton(props, parent, base)
	local p = {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		BackgroundColor3 = base,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = C.text,
		TextSize = 12,
		Text = "",
	}
	for key, value in pairs(props) do
		p[key] = value
	end

	local button = make("TextButton", p, parent)
	round(button, 5)

	local hover = base:Lerp(Color3.new(1, 1, 1), 0.12)
	button.MouseEnter:Connect(function()
		tween(button, TI.FAST, { BackgroundColor3 = hover })
	end)
	button.MouseLeave:Connect(function()
		tween(button, TI.FAST, { BackgroundColor3 = base })
	end)
	button.MouseButton1Down:Connect(function()
		tween(button, TI.FAST, { BackgroundColor3 = base:Lerp(Color3.new(0, 0, 0), 0.25) })
	end)
	button.MouseButton1Up:Connect(function()
		tween(button, TI.FAST, { BackgroundColor3 = hover })
	end)

	return button
end

----------------------------------------------------------------------
-- Controls: toggle, checkbox, slider
-- Every control returns { set = function(value, silent) } so configs can update them
----------------------------------------------------------------------
local activeSlider = nil -- set while a slider is being dragged

local function makeToggle(parent, value, onChange)
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(34, 16),
		BackgroundColor3 = value and C.accent or C.panel2,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	round(button, 8)

	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = value and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, button)
	round(knob, 6)

	local state = value
	local function set(v, silent)
		state = v
		tween(button, TI.FAST, { BackgroundColor3 = v and C.accent or C.panel2 })
		tween(knob, TI.FAST, { Position = v and UDim2.new(1, -14, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) })
		if onChange and not silent then
			onChange(v)
		end
	end

	button.Activated:Connect(function()
		set(not state)
	end)

	return { set = set }
end

local function makeCheckbox(parent, value, onChange, position)
	local button = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = position or UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = value and C.accent or C.panel2,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	round(button, 4)

	-- The check is drawn from two rotated bars, so it doesn't depend on any font
	local function leg(centerX, centerY, length, rotation)
		local bar = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(centerX, centerY),
			Size = UDim2.fromOffset(length, 2),
			Rotation = rotation,
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = value and 0 or 1,
			BorderSizePixel = 0,
		}, button)
		round(bar, 1)
		return bar
	end

	local shortLeg = leg(4.8, 9.6, 5.6, 45)
	local longLeg = leg(9.5, 8.5, 8.8, -45)

	local state = value
	local function set(v, silent)
		state = v
		tween(button, TI.FAST, { BackgroundColor3 = v and C.accent or C.panel2 })
		tween(shortLeg, TI.FAST, { BackgroundTransparency = v and 0 or 1 })
		tween(longLeg, TI.FAST, { BackgroundTransparency = v and 0 or 1 })
		if onChange and not silent then
			onChange(v)
		end
	end

	button.Activated:Connect(function()
		set(not state)
	end)

	return { set = set }
end

-- cfg: min, max, step, value, format, onChange
local function makeSlider(row, cfg)
	local valueText = label({
		TextSize = 11,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -150, 0, 0),
		Size = UDim2.fromOffset(36, 26),
	}, row)

	local track = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(104, 4),
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
	}, row)
	round(track, 2)

	local fill = make("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
	}, track)
	round(fill, 2)

	local hit = make("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 8, 0, 22),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
	}, track)

	local current = cfg.value

	local function setValue(v, silent)
		v = math.clamp(v, cfg.min, cfg.max)
		v = cfg.min + math.floor((v - cfg.min) / cfg.step + 0.5) * cfg.step
		v = math.clamp(v, cfg.min, cfg.max)

		fill.Size = UDim2.fromScale((v - cfg.min) / (cfg.max - cfg.min), 1)
		valueText.Text = string.format(cfg.format or "%d", v)

		if v ~= current then
			current = v
			if cfg.onChange and not silent then
				cfg.onChange(v)
			end
		end
	end

	local function fromX(x)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		setValue(cfg.min + alpha * (cfg.max - cfg.min))
	end

	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			activeSlider = fromX
			fromX(input.Position.X)
		end
	end)

	setValue(cfg.value, true)

	return { set = setValue }
end

----------------------------------------------------------------------
-- Layout components: card, rows, results table
----------------------------------------------------------------------
-- toggle (optional) = { value = bool, onChange = fn }
local function makeCard(parent, title, position, size, toggle)
	local card = make("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, parent)
	round(card, 6)
	outline(card)

	local header = make("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
	}, card)

	label({
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -90, 1, 0),
	}, header)

	make("Frame", {
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.stroke,
		BorderSizePixel = 0,
	}, header)

	local toggleObj
	if toggle then
		toggleObj = makeToggle(header, toggle.value, toggle.onChange)
	end

	local body = make("Frame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		BackgroundTransparency = 1,
	}, card)

	return card, body, header, toggleObj
end

local function listBody(body)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 12),
		PaddingRight = UDim.new(0, 12),
	}, body)
end

local function makeRow(body, text, order)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, body)

	local rowLabel = label({
		Text = text,
		RichText = true,
		Size = UDim2.new(0.55, 0, 1, 0),
	}, row)

	return row, rowLabel
end

-- Distance in studs as a number (math.huge when unknown)
local function distanceValue(item)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not rootPart or not item:IsA("PVInstance") then
		return math.huge
	end

	local ok, pivot = pcall(item.GetPivot, item)
	if not ok then
		return math.huge
	end

	return (pivot.Position - rootPart.Position).Magnitude
end

local function distanceText(item)
	local d = distanceValue(item)
	if d == math.huge then
		return "-"
	end
	return tostring(math.floor(d + 0.5))
end

-- cols = { { text, w, right? }, ... } with widths summing to 1
local function makeTable(body, header, cols)
	local T = { rowCount = 0 }

	local badge = label({
		Text = "0",
		TextSize = 11,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(80, 20),
	}, header)

	local layouts = {}
	local x = 0
	for i, col in ipairs(cols) do
		local left = (i == 1) and 12 or 0
		local right = (i == #cols) and 12 or 0
		layouts[i] = { UDim2.new(x, left, 0, 0), UDim2.new(col.w, -(left + right), 1, 0) }
		x += col.w
	end

	local columns = make("Frame", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
	}, body)

	for i, col in ipairs(cols) do
		label({
			Text = col.text,
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextColor3 = C.sub,
			TextXAlignment = col.right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left,
			Position = layouts[i][1],
			Size = layouts[i][2],
		}, columns)
	end

	make("Frame", {
		Position = UDim2.fromOffset(0, 26),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.stroke,
		BorderSizePixel = 0,
	}, body)

	local list = make("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(90, 90, 104),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, body)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local EMPTY = "Nothing here yet"
	local empty = label({
		Text = EMPTY,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -50),
	}, body)

	local footer = label({
		TextSize = 11,
		TextColor3 = C.sub,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -4),
		Size = UDim2.new(1, -24, 0, 16),
	}, body)

	function T.clear()
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		T.rowCount = 0
		badge.Text = "0"
		footer.Text = ""
		empty.Text = EMPTY
		empty.Visible = true
		list.CanvasPosition = Vector2.new(0, 0)
	end

	function T.setBadge(text)
		badge.Text = text
	end

	function T.setStatus(text, color)
		footer.Text = text
		footer.TextColor3 = color or C.sub
	end

	function T.setEmpty(text)
		empty.Text = text
		empty.Visible = T.rowCount == 0
	end

	-- cells = { { text, color?, bold?, onClick? }, ... }
	-- A cell with onClick becomes a small clickable button (used for Pin / Unpin)
	function T.add(cells, rowClick)
		if T.rowCount >= SETTINGS.maxRows then
			return
		end

		T.rowCount += 1
		empty.Visible = false

		local order = T.rowCount
		local rowTransparency = (order % 2 == 0) and 0.6 or 1
		local animate = order <= D.FADE_ROWS

		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = C.panel2,
			BackgroundTransparency = animate and 1 or rowTransparency,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, list)

		if rowClick then
			local rowButton = make("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "",
				AutoButtonColor = false,
			}, row)
			rowButton.Activated:Connect(rowClick)
		end

		local created = {}
		for i, cell in ipairs(cells) do
			local alignment = cols[i].right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left

			if cell.onClick then
				local button = make("TextButton", {
					Text = cell.text,
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextColor3 = cell.color or C.accent,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					TextXAlignment = alignment,
					TextTransparency = animate and 1 or 0,
					Position = layouts[i][1],
					Size = layouts[i][2],
				}, row)
				button.Activated:Connect(cell.onClick)
				created[i] = button
			else
				created[i] = label({
					Text = cell.text,
					Font = cell.bold and Enum.Font.GothamBold or Enum.Font.GothamMedium,
					TextColor3 = cell.color or C.text,
					TextXAlignment = alignment,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextTransparency = animate and 1 or 0,
					Position = layouts[i][1],
					Size = layouts[i][2],
				}, row)
			end
		end

		if animate then
			tween(row, TI.SMOOTH, { BackgroundTransparency = rowTransparency })
			for _, textLabel in ipairs(created) do
				tween(textLabel, TI.SMOOTH, { TextTransparency = 0 })
			end
		end
	end

	return T
end

----------------------------------------------------------------------
-- Forward declarations (logic is defined further down)
----------------------------------------------------------------------


-- Player page (workspace model scan)

-- Pinned loot: [instance] = true
local pinned = {}

-- Control references (so configs can update the GUI)
local controls = {}

-- Radar state (the radar itself is built near the bottom)
local radar = { on = false, range = 150 }

-- Loot ProximityPrompts: HoldDuration / BaseHold forced to 0 on scan
local promptState = { enabled = true, fixed = 0 }


-- Event-driven BaseHold monitor
local baseHoldConnections = setmetatable({}, { __mode = "k" })

-- Monitors if the loot BaseHold was changed >= 0.1.
local function monitorBaseHold(prompt)
    if not prompt:IsA("ProximityPrompt") then
        return
    end

    -- Prevent duplicate event connections.
    if baseHoldConnections[prompt] then
        return
    end

    local connections = {}
    baseHoldConnections[prompt] = connections

    local function enforceZero(valueObject)
        if not valueObject or not valueObject:IsA("ValueBase") then
            return
        end

        if not valueObject:IsA("NumberValue")
            and not valueObject:IsA("IntValue") then
            return
        end

        local function check()
            if promptState.enabled and valueObject.Value >= 0.1 then
                valueObject.Value = 0
                print("[BaseHold Monitor] Reset:", prompt:GetFullName())
            end
        end

        table.insert(connections,
            valueObject:GetPropertyChangedSignal("Value"):Connect(check)
        )

        check()
    end

    -- BaseHold stored as an attribute.
    local function checkAttribute()
        local value = prompt:GetAttribute("BaseHold")

        if promptState.enabled
            and typeof(value) == "number"
            and value >= 0.1 then
            prompt:SetAttribute("BaseHold", 0)
            print("[BaseHold Monitor] Reset attribute:", prompt:GetFullName())
        end
    end

    table.insert(connections,
        prompt:GetAttributeChangedSignal("BaseHold"):Connect(checkAttribute)
    )

    -- BaseHold stored as a NumberValue or IntValue child.
    local baseHold = prompt:FindFirstChild("BaseHold")
    enforceZero(baseHold)

    table.insert(connections, prompt.ChildAdded:Connect(function(child)
        if child.Name == "BaseHold" then
            enforceZero(child)
        end
    end))

    checkAttribute()
end


-- Auto-pin: loot of this rarity (or higher) is pinned on every scan
local autoPin = {
	enabled = false,
	minIndex = RARITY_INDEX["Legendary"] or #RARITIES,
	skip = setmetatable({}, { __mode = "k" }), -- items you unpinned yourself
}

-- Config helpers (filled in by the Configs section)
local configApi = {}

-- 2D ESP (entities / players / player models are drawn on screen instead of highlighted)
local esp = {}
local espSettings = {
	enabled = true,
	box = true,
	name = true,
	distance = true,
	health = true,
	tracers = false,
	highlights = false,
	maxDistance = 1500,
	textSize = 12,
	thickness = 1,
}

----------------------------------------------------------------------
-- Window
----------------------------------------------------------------------
local gui = make("ScreenGui", { Name = "LootDash", ResetOnSpawn = false }, playerGui)

local root = make("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(D.WIDTH, D.HEIGHT),
	BackgroundColor3 = C.bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Active = true,
}, gui)
round(root, 8)
outline(root)
local rootScale = make("UIScale", { Scale = 0.95 }, root)
----------------------------------------------------------------------
-- Loading overlay (covers the menu window only)
----------------------------------------------------------------------
do
	local ACCENT = Color3.fromRGB(235, 32, 24)
	local SUB = Color3.fromRGB(112, 112, 124)
	local DURATION = Random.new():NextNumber(1, 2) -- seconds the progress bar takes

	local function new(class, props, parent)
		local obj = Instance.new(class)
		for k, v in pairs(props) do
			obj[k] = v
		end
		obj.Parent = parent
		return obj
	end

	local overlay = new("Frame", {
		Name = "LoadingOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(11, 11, 13),
		BorderSizePixel = 0,
		Active = true, -- blocks clicks on the menu while loading
		ZIndex = 100,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, overlay)

	local title = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -30),
		Size = UDim2.fromOffset(500, 50),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 34,
		Text = "Welcome To Loot!",
		TextColor3 = ACCENT,
		TextStrokeColor3 = Color3.fromRGB(110, 14, 10),
		TextStrokeTransparency = 0.5,
		ZIndex = 101,
	}, overlay)

	local versionLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 8),
		Size = UDim2.fromOffset(500, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 15,
		Text = "V" .. S.CURRENT_VERSION,
		TextColor3 = SUB,
		ZIndex = 101,
	}, overlay)

	local track = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 46),
		Size = UDim2.fromOffset(240, 4),
		BackgroundColor3 = Color3.fromRGB(30, 30, 35),
		BorderSizePixel = 0,
		ZIndex = 101,
	}, overlay)
	new("UICorner", { CornerRadius = UDim.new(0, 2) }, track)

	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		ZIndex = 102,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(0, 2) }, fill)

	task.spawn(function()
		-- progress bar
		local bar = TweenService:Create(
			fill,
			TweenInfo.new(DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut),
			{ Size = UDim2.fromScale(1, 1) }
		)
		bar:Play()
		bar.Completed:Wait()
		task.wait(0.25)

		-- fade out, revealing the menu underneath
		local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(overlay, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(versionLabel, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(track, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(fill, fade, { BackgroundTransparency = 1 }):Play()
		task.wait(0.5)

		overlay:Destroy()
	end)
end

-- Added: in-game print console (session-only; it does not execute commands).
local consoleEnabled = false
local consoleMinimized = false
local consoleFrame
local consoleBody
local consoleOutput
local consoleLines = {}
local MAX_CONSOLE_LINES = 150
local originalPrint = print

local function consoleAddLog(...)
	local parts = {}
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		parts[index] = tostring(value)
	end

	local message = table.concat(parts, "\t")
	--table.insert(consoleLines, string.format("[%s] %s", os.date("%H:%M:%S"), message))
	table.insert(consoleLines, string.format(message))
	while #consoleLines > MAX_CONSOLE_LINES do
		table.remove(consoleLines, 1)
	end

	if consoleOutput then
		consoleOutput.Text = table.concat(consoleLines, "\n")
		task.defer(function()
			if consoleOutput and consoleOutput.Parent then
				consoleOutput.Size = UDim2.new(1, -12, 0, math.max(20, consoleOutput.TextBounds.Y + 8))
				if consoleBody then
					consoleBody.CanvasSize = UDim2.new(0, 0, 0, consoleOutput.AbsoluteSize.Y + 8)
					consoleBody.CanvasPosition = Vector2.new(0, math.max(0, consoleBody.AbsoluteCanvasSize.Y - consoleBody.AbsoluteSize.Y))
				end
			end
		end)
	end
end

-- Added: preserve the normal output while also copying print() calls into the GUI console.
print = function(...)
	consoleAddLog(...)
	return originalPrint(...)
end


local function createInGameConsole()
    consoleFrame = make("Frame", {
        Name = "LootDashCommandPrompt",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.fromOffset(640, 440),
        BackgroundColor3 = Color3.fromRGB(20, 20, 22),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 20,
    }, gui)

    round(consoleFrame, 6)
    outline(consoleFrame, Color3.fromRGB(65, 65, 70))

    local consoleHeader = make("Frame", {
        Name = "TitleBar",
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = Color3.fromRGB(32, 32, 35),
        BorderSizePixel = 0,
        ZIndex = 21,
    }, consoleFrame)

    round(consoleHeader, 6)

    make("Frame", {
        Position = UDim2.new(0, 0, 1, -5),
        Size = UDim2.new(1, 0, 0, 5),
        BackgroundColor3 = Color3.fromRGB(32, 32, 35),
        BorderSizePixel = 0,
        ZIndex = 21,
    }, consoleHeader)

    label({
        Text = "DEBUG  |  LOOT V" .. S.CURRENT_VERSION,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -48, 1, 0),
        ZIndex = 22,
    }, consoleHeader)

    local minimizeConsoleBtn = makeButton({
        Text = "-",
        Font = Enum.Font.Code,
        TextSize = 16,
        Size = UDim2.fromOffset(24, 22),
        Position = UDim2.new(1, -28, 0, 3),
        ZIndex = 22,
    }, consoleHeader, Color3.fromRGB(45, 45, 48))

    consoleBody = make("ScrollingFrame", {
        Name = "Output",
        Position = UDim2.fromOffset(6, 34),
        Size = UDim2.new(1, -12, 1, -40),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = Color3.fromRGB(110, 110, 115),
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 21,
    }, consoleFrame)

    consoleOutput = make("TextLabel", {
        Name = "LogText",
        Position = UDim2.fromOffset(4, 2),
        Size = UDim2.new(1, -12, 0, 20),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Font = Enum.Font.Code,
        TextSize = 15,
        TextColor3 = Color3.fromRGB(255, 255, 255),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        RichText = true,
        Text = "",
        ZIndex = 22,
    }, consoleBody)

    minimizeConsoleBtn.Activated:Connect(function()
        consoleMinimized = not consoleMinimized
        consoleBody.Visible = not consoleMinimized
        consoleFrame.Size = consoleMinimized
            and UDim2.fromOffset(640, 28)
            or UDim2.fromOffset(640, 440)
        minimizeConsoleBtn.Text = consoleMinimized and "+" or "-"
    end)

    consoleOutput.Text = table.concat(consoleLines, "\n")

    task.defer(function()
        if consoleOutput and consoleOutput.Parent then
            consoleOutput.Size = UDim2.new(
                1, -12, 0,
                math.max(20, consoleOutput.TextBounds.Y + 8)
            )

            consoleBody.CanvasSize = UDim2.new(
                0, 0, 0,
                consoleOutput.AbsoluteSize.Y + 8
            )

            consoleBody.CanvasPosition = Vector2.new(
                0,
                math.max(
                    0,
                    consoleBody.AbsoluteCanvasSize.Y
                        - consoleBody.AbsoluteSize.Y
                )
            )
        end
    end)
end


createInGameConsole()

local consoleToggleConnection = UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Insert and not UserInputService:GetFocusedTextBox() and consoleEnabled then
		consoleFrame.Visible = not consoleFrame.Visible
	end
end)

gui.Destroying:Connect(function()
	if consoleToggleConnection then
		consoleToggleConnection:Disconnect()
	end
end)


-- Soft red glow in the bottom-right corner
local glow = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = C.accent,
	BorderSizePixel = 0,
	ZIndex = 0,
}, root)
round(glow, 8)
make("UIGradient", {
	Rotation = 45,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.6, 1),
		NumberSequenceKeypoint.new(1, 0.9),
	}),
}, glow)

-- Header ---------------------------------------------------------------
local header = make("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, D.HEADER),
	BackgroundTransparency = 1,
	Active = true,
}, root)

make("Frame", {
	Position = UDim2.new(0, 0, 1, -1),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.stroke,
	BorderSizePixel = 0,
}, header)

label({
	Text = if S.IsBeta then "LOOT " .. S.CURRENT_VERSION .. "-BETA" else "LOOT " .. S.CURRENT_VERSION,
	Font = Enum.Font.GothamBlack,
	TextSize = 22,
	TextColor3 = C.accent,
	TextStrokeColor3 = C.accentDark,
	TextStrokeTransparency = 0.5,
	Position = UDim2.fromOffset(20, 0),
	Size = UDim2.fromOffset(D.SIDEBAR - 20, D.HEADER),
}, header)

local pageTitle = label({
	Text = "Loot",
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	Position = UDim2.fromOffset(D.SIDEBAR + 20, 0),
	Size = UDim2.new(1, -(D.SIDEBAR + 120), 1, 0),
}, header)

local foldBtn = makeButton({
	Text = "-",
	TextSize = 16,
	Font = Enum.Font.GothamBold,
	Size = UDim2.fromOffset(26, 26),
	Position = UDim2.new(1, -66, 0, 9),
}, header, C.panel2)

local closeBtn = makeButton({
	Text = "X",
	TextSize = 12,
	Font = Enum.Font.GothamBold,
	Size = UDim2.fromOffset(26, 26),
	Position = UDim2.new(1, -36, 0, 9),
}, header, C.accent)

-- Body (everything under the header, hidden when folded) ------------------
local bodyGroup = make("Frame", {
	Position = UDim2.fromOffset(0, D.HEADER),
	Size = UDim2.new(1, 0, 1, -D.HEADER),
	BackgroundTransparency = 1,
}, root)

make("Frame", {
	Position = UDim2.fromOffset(D.SIDEBAR, 0),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = C.stroke,
	BorderSizePixel = 0,
}, bodyGroup)

local sidebar = make("Frame", {
	Size = UDim2.new(0, D.SIDEBAR, 1, 0),
	BackgroundTransparency = 1,
}, bodyGroup)

local content = make("Frame", {
	Position = UDim2.fromOffset(D.SIDEBAR + 14, 14),
	Size = UDim2.new(1, -(D.SIDEBAR + 28), 1, -28),
	BackgroundTransparency = 1,
}, bodyGroup)

-- Sidebar navigation ------------------------------------------------------
local navItems = {}
local pages = {}

local function sectionLabel(text, y)
	label({
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = C.sub,
		Position = UDim2.fromOffset(18, y),
		Size = UDim2.new(1, -18, 0, 18),
	}, sidebar)
end

local function showPage(name)
	pageTitle.Text = name

	for pageName, page in pairs(pages) do
		local isActive = pageName == name
		page.Visible = isActive
		if isActive then
			page.Position = UDim2.fromOffset(0, 8)
			tween(page, TI.SMOOTH, { Position = UDim2.fromOffset(0, 0) })
		end
	end

	for itemName, item in pairs(navItems) do
		local isActive = itemName == name
		tween(item.button, TI.FAST, { BackgroundTransparency = isActive and 0 or 1 })
		tween(item.text, TI.FAST, { TextColor3 = isActive and C.text or C.sub })
		tween(item.bar, TI.FAST, { BackgroundTransparency = isActive and 0 or 1 })
		for _, part in ipairs(item.icon.parts) do
			tween(part[1], TI.FAST, { [part[2]] = isActive and C.text or C.sub })
		end
	end
end

-- Small vector icons built from frames (no image assets needed)
local function makeIcon(kind, parent)
	local holder = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
	}, parent)

	local parts = {} -- { instance, property } so showPage can recolor the icon

	local function solid(x, y, w, h, radius)
		local f = make("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = C.sub,
			BorderSizePixel = 0,
		}, holder)
		if radius then
			round(f, radius)
		end
		table.insert(parts, { f, "BackgroundColor3" })
		return f
	end

	local function ring(x, y, w, h, radius, thickness, rotation)
		local f = make("Frame", {
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(w, h),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = rotation or 0,
		}, holder)
		if radius then
			round(f, radius)
		end
		local stroke = make("UIStroke", {
			Color = C.sub,
			Thickness = thickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, f)
		table.insert(parts, { stroke, "Color" })
		return f
	end

	if kind == "players" then -- head + shoulders
		solid(5, 1, 6, 6, 3)
		solid(2, 9, 12, 6, 4)
	elseif kind == "loot" then -- gem
		ring(3.5, 3.5, 9, 9, 1, 1.5, 45)
		solid(7, 7, 2, 2, 1)
	elseif kind == "entity" then -- ghost
		solid(3, 1, 10, 14, 5)
		for _, eyeX in ipairs({ 5.5, 9 }) do
			make("Frame", {
				Position = UDim2.fromOffset(eyeX, 6),
				Size = UDim2.fromOffset(1.5, 3),
				BackgroundColor3 = C.bg,
				BorderSizePixel = 0,
			}, holder)
		end
	elseif kind == "settings" then -- sliders
		solid(1, 3, 14, 1.5)
		solid(1, 7.5, 14, 1.5)
		solid(1, 12, 14, 1.5)
		solid(9, 1.75, 4, 4, 2)
		solid(3, 6.25, 4, 4, 2)
		solid(10, 10.75, 4, 4, 2)
	elseif kind == "configs" then -- document
		ring(2.5, 1, 11, 14, 2, 1.5)
		solid(5, 5, 6, 1.5)
		solid(5, 8, 6, 1.5)
		solid(5, 11, 4, 1.5)
	end

	return { parts = parts }
end

-- Tab bar at the top of a page. Returns { [tabName] = pageFrame, selectTab = fn }
local function makeTabs(parent, names)
	local tabs = {}
	local entries = {}

	local bar = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
	}, parent)

	make("Frame", {
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.stroke,
		BorderSizePixel = 0,
	}, bar)

	local function selectTab(name)
		for tabName, entry in pairs(entries) do
			local isActive = tabName == name
			entry.page.Visible = isActive
			if isActive then
				entry.page.Position = UDim2.fromOffset(0, 48)
				tween(entry.page, TI.SMOOTH, { Position = UDim2.fromOffset(0, 40) })
			end
			tween(entry.button, TI.FAST, { TextColor3 = isActive and C.text or C.sub })
			tween(entry.underline, TI.FAST, { BackgroundTransparency = isActive and 0 or 1 })
		end
	end

	local x = 0
	for _, name in ipairs(names) do
		local width = #name * 8 + 28

		local button = make("TextButton", {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.fromOffset(width, 29),
			BackgroundTransparency = 1,
			Text = name,
			Font = Enum.Font.GothamSemibold,
			TextSize = 12,
			TextColor3 = C.sub,
			AutoButtonColor = false,
		}, bar)

		local underline = make("Frame", {
			Position = UDim2.new(0, 10, 1, -2),
			Size = UDim2.new(1, -20, 0, 2),
			BackgroundColor3 = C.accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, button)
		round(underline, 1)

		local page = make("Frame", {
			Name = name,
			Position = UDim2.fromOffset(0, 40),
			Size = UDim2.new(1, 0, 1, -40),
			BackgroundTransparency = 1,
			Visible = false,
		}, parent)

		entries[name] = { button = button, underline = underline, page = page }
		tabs[name] = page

		button.Activated:Connect(function()
			selectTab(name)
		end)

		x += width
	end

	tabs.selectTab = selectTab
	selectTab(names[1])

	return tabs
end

local function addNav(name, y, iconKind)
	local button = make("TextButton", {
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.fromOffset(8, y),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, sidebar)
	round(button, 6)

	local bar = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 18),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, button)
	round(bar, 2)

	local icon = makeIcon(iconKind, button)

	local text = label({
		Text = name,
		Font = Enum.Font.GothamSemibold,
		TextSize = 13,
		TextColor3 = C.sub,
		Position = UDim2.fromOffset(40, 0),
		Size = UDim2.new(1, -46, 1, 0),
	}, button)

	navItems[name] = { button = button, text = text, bar = bar, icon = icon }
	button.Activated:Connect(function()
		showPage(name)
	end)
end

-- "Player" section sits above the "Scan" section
sectionLabel("Tracking", 14)
addNav("Players", 36, "players")
sectionLabel("Scanners", 88)
addNav("Loot", 110, "loot")
addNav("Entities", 148, "entity")
sectionLabel("Setup", 200)
addNav("Settings", 222, "settings")
addNav("Configs", 260, "configs")

local function makePage(name)
	local page = make("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, content)
	pages[name] = page
	return page
end

makePage("Loot")
makePage("Entities")
makePage("Players")
makePage("Settings")
makePage("Configs")

-- The Players page has a tab bar at the top: Players | ESP | Closets
local playerTabs = makeTabs(pages.Players, { "Players", "ESP", "Closets" })

----------------------------------------------------------------------
-- Closet scanner (scans workspace.ActiveMap for models named Closet)
----------------------------------------------------------------------
D.LEFT_W = 250

local modelScanBtn, modelUnloadBtn, modelTable
do
local _, modelScanBody = makeCard(playerTabs.Closets, "Scanner", UDim2.fromOffset(0, 0), UDim2.fromOffset(D.LEFT_W, 88))

modelScanBtn = makeButton({
	Text = "Scan",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0, 12, 0, 12),
}, modelScanBody, C.accent)

modelUnloadBtn = makeButton({
	Text = "Unload",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0.5, 4, 0, 12),
}, modelScanBody, C.panel2)

local _, modelFilterBody, _, modelToggle = makeCard(
	playerTabs.Closets,
	"Show on ESP",
	UDim2.fromOffset(0, 98),
	UDim2.fromOffset(D.LEFT_W, 34 + 12 + 28),
	{
		value = true,
		onChange = function(v)
			S.modelHighlightsOn = v
			F.renderPlayerModels()
		end,
	}
)
listBody(modelFilterBody)
controls.modelToggle = modelToggle

local _, modelResultsBody, modelResultsHeader = makeCard(
	playerTabs.Closets,
	"Closets",
	UDim2.fromOffset(D.LEFT_W + 10, 0),
	UDim2.new(1, -(D.LEFT_W + 10), 1, 0)
)

modelTable = makeTable(modelResultsBody, modelResultsHeader, {
	{ text = "OBJECT", w = 0.34 },
	{ text = "TYPE", w = 0.24 },
	{ text = "INFO", w = 0.18 },
	{ text = "DIST", w = 0.24, right = true },
})
modelTable.setEmpty("Press Scan to find closets")
end

----------------------------------------------------------------------
-- Loot page
----------------------------------------------------------------------
local lootScanBtn, lootUnloadBtn, rarityCounts, pinnedList, pinnedBadge, pinnedEmpty, lootTable
do
local _, lootScanBody = makeCard(pages.Loot, "Scanner", UDim2.fromOffset(0, 0), UDim2.fromOffset(D.LEFT_W, 116))

lootScanBtn = makeButton({
	Text = "Scan",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0, 12, 0, 12),
}, lootScanBody, C.accent)

lootUnloadBtn = makeButton({
	Text = "Unload",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0.5, 4, 0, 12),
}, lootScanBody, C.panel2)

local promptRow = makeRow(lootScanBody, "Instant prompts", 1)
promptRow.Position = UDim2.fromOffset(12, 48)
promptRow.Size = UDim2.new(1, -24, 0, 26)
controls.instantPrompts = makeCheckbox(promptRow, promptState.enabled, function(v)
	promptState.enabled = v
	F.applyInstantPrompts()
	F.renderLoot()
end)

local _, rarityBody, _, lootToggle = makeCard(
	pages.Loot,
	"Rarities",
	UDim2.fromOffset(0, 126),
	UDim2.fromOffset(D.LEFT_W, 34 + 12 + #RARITIES * 28),
	{
		value = true,
		onChange = function(v)
			S.lootHighlightsOn = v
			F.renderLoot()
		end,
	}
)
listBody(rarityBody)
controls.lootToggle = lootToggle

rarityCounts = {}
for index, rarity in ipairs(RARITIES) do
	local row, rowLabel = makeRow(
		rarityBody,
		'<font color="#' .. rarity.color:ToHex() .. '">●</font>  ' .. rarity.name,
		index
	)
	rowLabel.Size = UDim2.new(0.6, 0, 1, 0)

	rarityCounts[index] = label({
		Text = "0",
		TextSize = 11,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -62, 0, 0),
		Size = UDim2.fromOffset(36, 26),
	}, row)

	controls["rarity:" .. rarity.name] = makeCheckbox(row, SHOW_RARITIES[rarity.name] ~= false, function(v)
		SHOW_RARITIES[rarity.name] = v
		F.renderLoot()
	end)
end

-- Pinned card (below the rarities)
local PINNED_Y = 126 + (34 + 12 + #RARITIES * 28) + 10
local _, pinnedBody, pinnedHeader = makeCard(
	pages.Loot,
	"Pinned",
	UDim2.fromOffset(0, PINNED_Y),
	UDim2.new(0, D.LEFT_W, 1, -PINNED_Y)
)

pinnedBadge = label({
	Text = "0",
	TextSize = 11,
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -12, 0.5, 0),
	Size = UDim2.fromOffset(60, 20),
}, pinnedHeader)

pinnedList = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(90, 90, 104),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, pinnedBody)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, pinnedList)
make("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, pinnedList)

pinnedEmpty = label({
	Text = "Pin items from the results",
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Center,
	Size = UDim2.fromScale(1, 1),
}, pinnedBody)

local _, lootResultsBody, lootResultsHeader = makeCard(
	pages.Loot,
	"Results",
	UDim2.fromOffset(D.LEFT_W + 10, 0),
	UDim2.new(1, -(D.LEFT_W + 10), 1, 0)
)

lootTable = makeTable(lootResultsBody, lootResultsHeader, {
	{ text = "NAME", w = 0.32 },
	{ text = "RARITY", w = 0.2 },
	{ text = "VALUE", w = 0.14 },
	{ text = "DIST", w = 0.12, right = true },
	{ text = "PIN", w = 0.22, right = true },
})
lootTable.setEmpty("Press Scan to find items")
end

-----------------------------------------------------------------------
-- Toast notification (top left, stacks downward, slides in/out)
-- kind: "ok" | "info" | "warn" | "error"
-----------------------------------------------------------------------
F.toast = function(text, kind, duration)
    if not S.AllowToasts then return end
    duration = duration or 6

    local accent = ({
        ok = Color3.fromRGB(90, 230, 120),
        info = Color3.fromRGB(70, 200, 255),
        warn = Color3.fromRGB(255, 150, 30),
        error = C.accent,
    })[kind] or C.accent

    if not (F.toastGui and F.toastGui.Parent) then
        F.toastGui = make("ScreenGui", {
            Name = "LootDashToasts",
            ResetOnSpawn = false,
            IgnoreGuiInset = false,
            DisplayOrder = 999999,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        }, playerGui)

        local newHolder = make("Frame", {
            Name = "Toasts",
            Position = UDim2.fromOffset(16, 16),
            Size = UDim2.fromOffset(280, 400),
            BackgroundTransparency = 1,
            ZIndex = 50,
        }, F.toastGui)

        make("UIListLayout", {
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }, newHolder)
    end

    local holder = F.toastGui.Toasts

    -- Wrapper reserves the correct amount of space in the stack.
    local wrapper = make("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundTransparency = 1,
        LayoutOrder = os.clock() * 1000,
        ZIndex = 50,
    }, holder)

    local card = make("Frame", {
        Position = UDim2.fromOffset(-300, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = C.panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 50,
    }, wrapper)

    round(card, 6)
    outline(card)

    make("Frame", {
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, card)

    -- Text wraps onto multiple lines and grows vertically.
    local messageLabel = label({
        Text = tostring(text),
		Font = Enum.Font.Gotham,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Center,
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.fromOffset(14, 0),
        Size = UDim2.new(1, -22, 0, 0),
        ZIndex = 51,
    }, card)

    -- Expand the wrapper to match the message height.
    local function resizeToastToMessage()
        if not (wrapper.Parent and messageLabel.Parent) then
            return
        end

        local requiredHeight = math.max(
            34,
            messageLabel.AbsoluteSize.Y + 2
        )

        wrapper.Size = UDim2.new(1, 0, 0, requiredHeight)
    end

    messageLabel:GetPropertyChangedSignal("AbsoluteSize"):Connect(
        resizeToastToMessage
    )

    task.defer(resizeToastToMessage)

    -- Countdown bar.
    local bar = make("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, card)

    -- Slide in.
    tween(card, TI.SMOOTH, {
        Position = UDim2.fromOffset(0, 0),
    })

    TweenService:Create(
        bar,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { Size = UDim2.new(0, 0, 0, 2) }
    ):Play()

    -- Slide out and remove.
    task.delay(duration, function()
        if not wrapper.Parent then
            return
        end

        tween(card, TI.SMOOTH, {
            Position = UDim2.fromOffset(-300, 0),
        }).Completed:Wait()

        wrapper:Destroy()
    end)
end
F.toast("Toast loaded. Testing the extended version if text runs out of space.", "ok")


----------------------------------------------------------------------
-- Entities page
----------------------------------------------------------------------
local entityList, addBox, addBtn, entityScanBtn, entityUnloadBtn, entityTable
do
local _, entityListBody, _, entityToggle = makeCard(
	pages.Entities,
	"Entities",
	UDim2.fromOffset(0, 0),
	UDim2.new(0, D.LEFT_W, 1, -98),
	{
		value = true,
		onChange = function(v)
			S.entityHighlightsOn = v
			F.renderEntities()
		end,
	}
)
controls.entityToggle = entityToggle

entityList = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(90, 90, 104),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, entityListBody)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, entityList)
make("UIPadding", {
	PaddingTop = UDim.new(0, 6),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, entityList)

addBox = make("TextBox", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -8),
	Size = UDim2.new(1, -76, 0, 26),
	BackgroundColor3 = C.panel2,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = C.text,
	PlaceholderText = "Add entity name",
	PlaceholderColor3 = C.sub,
	Text = "",
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left,
}, entityListBody)
round(addBox, 5)
make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, addBox)

addBtn = makeButton({
	Text = "Add",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -12, 1, -8),
	Size = UDim2.fromOffset(52, 26),
}, entityListBody, C.panel2)

local _, entityScanBody = makeCard(
	pages.Entities,
	"Scanner",
	UDim2.new(0, 0, 1, -88),
	UDim2.fromOffset(D.LEFT_W, 88)
)

entityScanBtn = makeButton({
	Text = "Scan",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0, 12, 0, 12),
}, entityScanBody, C.accent)

entityUnloadBtn = makeButton({
	Text = "Unload",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0.5, 4, 0, 12),
}, entityScanBody, C.panel2)

local _, entityResultsBody, entityResultsHeader = makeCard(
	pages.Entities,
	"Results",
	UDim2.fromOffset(D.LEFT_W + 10, 0),
	UDim2.new(1, -(D.LEFT_W + 10), 1, 0)
)

entityTable = makeTable(entityResultsBody, entityResultsHeader, {
	{ text = "ENTITY", w = 0.5 },
	{ text = "TYPE", w = 0.3 },
	{ text = "DIST", w = 0.2, right = true },
})
entityTable.setEmpty("Press Scan to find entities")
end

----------------------------------------------------------------------
-- Players page (Players service list)
----------------------------------------------------------------------
local playerScanBtn, playerUnloadBtn, playerTable
do
local _, playerScanBody = makeCard(playerTabs.Players, "Scanner", UDim2.fromOffset(0, 0), UDim2.fromOffset(D.LEFT_W, 88))

playerScanBtn = makeButton({
	Text = "Refresh",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0, 12, 0, 12),
}, playerScanBody, C.accent)

playerUnloadBtn = makeButton({
	Text = "Unload",
	Size = UDim2.new(0.5, -16, 0, 30),
	Position = UDim2.new(0.5, 4, 0, 12),
}, playerScanBody, C.panel2)

local _, playerFilterBody, _, playersToggle = makeCard(
	playerTabs.Players,
	"Show on ESP",
	UDim2.fromOffset(0, 98),
	UDim2.fromOffset(D.LEFT_W, 34 + 12 + 28),
	{
		value = true,
		onChange = function(v)
			S.playersHighlightsOn = v
			F.renderPlayers()
		end,
	}
)
listBody(playerFilterBody)
controls.playersToggle = playersToggle

local includeSelfRow = makeRow(playerFilterBody, "Include myself", 1)
controls.includeSelf = makeCheckbox(includeSelfRow, false, function(v)
	S.includeSelf = v
	F.renderPlayers()
end)

local _, playerResultsBody, playerResultsHeader = makeCard(
	playerTabs.Players,
	"Results",
	UDim2.fromOffset(D.LEFT_W + 10, 0),
	UDim2.new(1, -(D.LEFT_W + 10), 1, 0)
)

playerTable = makeTable(playerResultsBody, playerResultsHeader, {
	{ text = "PLAYER", w = 0.30 },
	{ text = "ROLE", w = 0.22 },
	{ text = "PARTS", w = 0.16 },
	{ text = "HP", w = 0.14 },
	{ text = "DIST", w = 0.18, right = true },
})
playerTable.setEmpty("Press Refresh to list players")
end

----------------------------------------------------------------------
-- ESP page
----------------------------------------------------------------------
do
local _, espBody, _, espToggle = makeCard(
	playerTabs.ESP,
	"Overlay",
	UDim2.fromOffset(0, 0),
	UDim2.fromOffset(D.LEFT_W, 34 + 12 + 7 * 28),
	{
		value = espSettings.enabled,
		onChange = function(v)
			espSettings.enabled = v
		end,
	}
)
listBody(espBody)
controls["esp:enabled"] = espToggle

local function espCheck(text, key, order)
	local row = makeRow(espBody, text, order)
	controls["esp:" .. key] = makeCheckbox(row, espSettings[key], function(v)
		espSettings[key] = v
	end)
end

espCheck("Boxes", "box", 1)
espCheck("Names", "name", 2)
espCheck("Distance", "distance", 3)
espCheck("Health bars", "health", 4)
espCheck("Tracers", "tracers", 5)
espCheck("Highlights", "highlights", 6)

local radarRow = makeRow(espBody, "Radar", 7)
controls.radar = makeCheckbox(radarRow, radar.on, function(v)
	radar.setEnabled(v)
end)

local _, espStyleBody = makeCard(
	playerTabs.ESP,
	"Style",
	UDim2.fromOffset(D.LEFT_W + 10, 0),
	UDim2.new(1, -(D.LEFT_W + 10), 0, 34 + 12 + 3 * 28)
)
listBody(espStyleBody)

local espRangeRow = makeRow(espStyleBody, "Max distance", 1)
controls["esp:maxDistance"] = makeSlider(espRangeRow, {
	min = 100,
	max = 3000,
	step = 50,
	value = espSettings.maxDistance,
	onChange = function(v)
		espSettings.maxDistance = v
	end,
})

local espTextRow = makeRow(espStyleBody, "Text size", 2)
controls["esp:textSize"] = makeSlider(espTextRow, {
	min = 10,
	max = 18,
	step = 1,
	value = espSettings.textSize,
	onChange = function(v)
		espSettings.textSize = v
	end,
})

local espThicknessRow = makeRow(espStyleBody, "Box thickness", 3)
controls["esp:thickness"] = makeSlider(espThicknessRow, {
	min = 1,
	max = 3,
	step = 1,
	value = espSettings.thickness,
	onChange = function(v)
		espSettings.thickness = v
	end,
})
end

----------------------------------------------------------------------
-- Settings page (one big scrolling card)
----------------------------------------------------------------------
do
local _, settingsBody = makeCard(pages.Settings, "Settings", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))

local settingsList = make("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(90, 90, 104),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, settingsBody)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, settingsList)
make("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 16), -- leaves room for the scrollbar
}, settingsList)

-- Small helpers so every entry is just one line
local order = 0
local function nextOrder()
	order += 1
	return order
end

local function section(text)
	local holder = make("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, settingsList)

	label({
		Text = string.upper(text),
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = C.sub,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 16),
	}, holder)

	make("Frame", {
		Position = UDim2.new(0, 0, 1, -1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.stroke,
		BorderSizePixel = 0,
	}, holder)
end

local function row(text)
	return (makeRow(settingsList, text, nextOrder()))
end

-- Highlights ------------------------------------------------------------
section("Highlights")

controls.maxHighlights = makeSlider(row("Max highlights"), {
	min = 1,
	max = 31,
	step = 1,
	value = SETTINGS.maxHighlights,
	onChange = function(v)
		SETTINGS.maxHighlights = v
		F.rerenderSoon()
	end,
})

controls.fill = makeSlider(row("Fill transparency"), {
	min = 0,
	max = 1,
	step = 0.05,
	value = SETTINGS.fillTransparency,
	format = "%.2f",
	onChange = function(v)
		SETTINGS.fillTransparency = v
		F.applyFillTransparency()
	end,
})

-- Results ---------------------------------------------------------------
section("Results")

controls.maxRows = makeSlider(row("Max rows"), {
	min = 25,
	max = 300,
	step = 25,
	value = SETTINGS.maxRows,
	onChange = function(v)
		SETTINGS.maxRows = v
		F.rerenderSoon()
	end,
})

-- Loot filter -----------------------------------------------------------
section("Loot filter")

local minValueRow = row("Min value ($)")
local minValueBox = make("TextBox", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(110, 22),
	BackgroundColor3 = C.panel2,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = C.text,
	PlaceholderText = "0",
	PlaceholderColor3 = C.sub,
	Text = tostring(SETTINGS.minValue),
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Center,
}, minValueRow)
round(minValueBox, 5)

local function setMinValue(v, silent)
	v = math.clamp(math.floor(v + 0.5), 0, 1000000)
	SETTINGS.minValue = v
	minValueBox.Text = tostring(v)
	if not silent then
		F.rerenderSoon()
	end
end

-- press Enter or click away to apply
minValueBox.FocusLost:Connect(function()
	local typed = tonumber((string.gsub(minValueBox.Text, "[^%d%.]", "")))
	setMinValue(typed or SETTINGS.minValue)
end)

controls.minValue = { set = setMinValue }

-- Auto pin --------------------------------------------------------------
section("Auto pin")

controls.autoPin = makeCheckbox(row("Pin on every scan"), autoPin.enabled, function(v)
	autoPin.enabled = v
	F.applyAutoPin()
	F.renderLoot()
end)

local autoPinRarityRow = row("Minimum rarity")
local autoPinRarityBtn = makeButton({
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(110, 22),
	TextSize = 11,
}, autoPinRarityRow, C.panel2)

local function showAutoPinRarity()
	local rarity = RARITIES[autoPin.minIndex]
	autoPinRarityBtn.Text = rarity.name .. " +"
	autoPinRarityBtn.TextColor3 = rarity.color
end
showAutoPinRarity()

controls.autoPinRarity = {
	set = function(index)
		autoPin.minIndex = index
		showAutoPinRarity()
	end,
}

autoPinRarityBtn.Activated:Connect(function()
	autoPin.minIndex = autoPin.minIndex % #RARITIES + 1
	showAutoPinRarity()
	F.applyAutoPin()
	F.renderLoot()
end)

-- Auto scan -------------------------------------------------------------
section("Auto scan")

controls.autoScan = makeCheckbox(row("Scan when map reloads"), autoScan.enabled, function(v)
	autoScan.enabled = v
end)

controls.autoDelay = makeSlider(row("Delay (seconds)"), {
	min = 1,
	max = 60,
	step = 1,
	value = autoScan.delay,
	format = "%ds",
	onChange = function(v)
		autoScan.delay = v
	end,
})

-- Entity detection ------------------------------------------------------
section("Entity detection")

controls.threshold = makeSlider(row("Entity part count"), {
	min = 5,
	max = 100,
	step = 1,
	value = S.partThreshold,
	onChange = function(v)
		S.partThreshold = v
		F.rerenderSoon()
	end,
})

controls.ignoreAcc = makeCheckbox(row("Ignore accessories"), S.ignoreAccessories, function(v)
	S.ignoreAccessories = v
	F.rerenderSoon()
end)

-- Radar -----------------------------------------------------------------
section("Radar")

controls.radarRange = makeSlider(row("Radar range"), {
	min = 50,
	max = 500,
	step = 10,
	value = radar.range,
	onChange = function(v)
		radar.range = v
	end,
})

-- Interface -------------------------------------------------------------
section("Interface")

controls.seeCmdPrompt = makeCheckbox(row("See cmd prompt"), false, function(v)
	consoleEnabled = v
	if consoleFrame then
		consoleFrame.Visible = v
	end
end)

controls.seeToasts = makeCheckbox(row("See toasts"), S.AllowToasts, function(v)
	S.AllowToasts = v

	-- Remove notifications already on screen when toasts are turned off.
	if not v and F.toastGui then
		F.toastGui:Destroy()
		F.toastGui = nil
	end
end)
end
----------------------------------------------------------------------
-- Highlight sets
----------------------------------------------------------------------
local lootSet = {}
local pinSet = {}
local lootLabels = {}
local pinLabels = {}
local labelFolder = make("Folder", { Name = "Labels" }, gui)

local function clearSet(set)
	for item, highlight in pairs(set) do
		highlight:Destroy()
		set[item] = nil
	end
end

-- Destroys every entry of `set` that was not touched (seen) during the last render
local function pruneSet(set, seen)
	for item, instance in pairs(set) do
		if not seen[item] then
			instance:Destroy()
			set[item] = nil
		end
	end
end

local function highlightItem(set, item, color, name, seen)
	if seen then
		seen[item] = true
	end

	local outlineColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
	local existing = set[item]

	if existing then
		if existing.FillColor ~= color then
			existing.FillColor = color
			existing.OutlineColor = outlineColor
		end
		existing.FillTransparency = SETTINGS.fillTransparency
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = name
	highlight.Adornee = item
	highlight.FillColor = color
	highlight.OutlineColor = outlineColor
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = item

	tween(highlight, TI.SMOOTH, { FillTransparency = SETTINGS.fillTransparency, OutlineTransparency = 0 })

	set[item] = highlight
	item.Destroying:Once(function()
		set[item] = nil
	end)
end

-- Small text above an object, e.g. "Loot - Rare"
local function labelItem(set, item, text, color, seen)
	if seen then
		seen[item] = true
	end

	local existing = set[item]
	if existing then
		local textLabel = existing:FindFirstChildOfClass("TextLabel")
		if textLabel and textLabel.Text ~= text then
			textLabel.Text = text
			textLabel.TextColor3 = color
		end
		return
	end

	local adornee = item
	if not item:IsA("BasePart") then
		adornee = (item:IsA("Model") and item.PrimaryPart) or item:FindFirstChildWhichIsA("BasePart", true)
	end
	if not adornee then
		return
	end

	local board = make("BillboardGui", {
		Name = "LootLabel",
		Adornee = adornee,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(150, 16),
		StudsOffset = Vector3.new(0, 2, 0),
		MaxDistance = 2000,
	}, labelFolder)

	make("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Text = text,
		TextColor3 = color,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.3,
	}, board)

	set[item] = board
	item.Destroying:Once(function()
		board:Destroy()
		set[item] = nil
	end)
end

F.applyFillTransparency = function()
	for _, set in ipairs({ lootSet, pinSet }) do
		for _, highlight in pairs(set) do
			highlight.FillTransparency = SETTINGS.fillTransparency
		end
	end

	if esp.applyFill then
		esp.applyFill()
	end
end

----------------------------------------------------------------------
-- Loot logic
----------------------------------------------------------------------

local function itemDisplayName(item)
	local key = item:GetAttribute("ItemKey")
	local config = type(key) == "string" and GameConfig.Items[key] or nil
	return config and config.displayName or item.Name
end

local function itemRarityColor(item)
	local index = RARITY_INDEX[item:GetAttribute(RARITY_ATTRIBUTE)]
	return index and RARITIES[index].color or C.text
end

local function belowMinValue(item)
	return (tonumber(item:GetAttribute("Value")) or 0) < SETTINGS.minValue
end

local function togglePin(item)
	if pinned[item] then
		pinned[item] = nil
		autoPin.skip[item] = true -- auto-pin won't re-pin something you unpinned
	else
		pinned[item] = true
		autoPin.skip[item] = nil
	end
	F.renderLoot()
end

-- Rebuilds the Pinned card + gold highlights. Returns how many highlights it used.
F.renderPinned = function()
	local seenH, seenL = {}, {}

	for _, child in ipairs(pinnedList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Forget pins whose item no longer exists (e.g. after a map reload)
	local entries = {}
	for item in pairs(pinned) do
		if item.Parent then
			if not belowMinValue(item) then
				table.insert(entries, { item = item, name = itemDisplayName(item) })
			end
		else
			pinned[item] = nil
		end
	end

	table.sort(entries, function(a, b)
		return a.name < b.name
	end)

	local highlighted = 0
	for order, entry in ipairs(entries) do
		if S.lootHighlightsOn and highlighted < SETTINGS.maxHighlights then
			highlightItem(pinSet, entry.item, PIN_COLOR, "PinHighlight", seenH)
			highlighted += 1
		end

		if S.lootHighlightsOn then
			local rarityName = entry.item:GetAttribute(RARITY_ATTRIBUTE)
			labelItem(pinLabels, entry.item, "Loot - " .. tostring(rarityName) .. " [Pinned]", PIN_COLOR, seenL)
		end

		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, pinnedList)

		label({
			Text = entry.name,
			Font = Enum.Font.GothamBold,
			TextColor3 = itemRarityColor(entry.item),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -100, 1, 0),
		}, row)

		label({
			Text = distanceText(entry.item),
			TextSize = 11,
			TextColor3 = C.sub,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -92, 0, 0),
			Size = UDim2.fromOffset(36, 24),
		}, row)

		local unpin = makeButton({
			Text = "Unpin",
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(50, 20),
		}, row, C.panel2)

		unpin.Activated:Connect(function()
			pinned[entry.item] = nil
			autoPin.skip[entry.item] = true
			F.renderLoot()
		end)
	end

	pruneSet(pinSet, seenH)
	pruneSet(pinLabels, seenL)

	pinnedBadge.Text = #entries .. " pinned"
	pinnedEmpty.Visible = #entries == 0

	return highlighted
end

F.renderLoot = function()
	local seenH, seenL = {}, {}
	lootTable.clear()

	local highlighted = F.renderPinned()

	for _, countLabel in ipairs(rarityCounts) do
		countLabel.Text = "0"
	end

	if not S.lootData then
		pruneSet(lootSet, seenH)
		pruneSet(lootLabels, seenL)
		lootTable.setEmpty("Press Scan to find items")
		return
	end

	local counts = {}
	local pinnedRows = {}
	local otherRows = {}

	for _, result in ipairs(S.lootData) do
		if result.item.Parent and not belowMinValue(result.item) then
			counts[result.index] = (counts[result.index] or 0) + 1

			if pinned[result.item] then
				table.insert(pinnedRows, result) -- pinned items are always listed
			elseif SHOW_RARITIES[RARITIES[result.index].name] ~= false then
				table.insert(otherRows, result)
			end
		end
	end

	for index, countLabel in ipairs(rarityCounts) do
		countLabel.Text = tostring(counts[index] or 0)
	end

	-- Pinned first, then everything else (already sorted by rarity / value)
	local visible = {}
	for _, result in ipairs(pinnedRows) do
		table.insert(visible, result)
	end
	for _, result in ipairs(otherRows) do
		table.insert(visible, result)
	end

	for _, result in ipairs(visible) do
		local rarity = RARITIES[result.index]
		local item = result.item
		local isPinned = pinned[item] == true

		-- Pinned items already got their gold highlight in F.renderPinned
		if not isPinned and S.lootHighlightsOn and highlighted < SETTINGS.maxHighlights then
			highlightItem(lootSet, item, rarity.color, "RarityHighlight", seenH)
			highlighted += 1
		end

		-- Every listed loot object gets a label (not limited by the highlight cap)
		if not isPinned and S.lootHighlightsOn then
			labelItem(lootLabels, item, "Loot - " .. rarity.name, rarity.color, seenL)
		end

		lootTable.add({
			{ text = (isPinned and "[P] " or "") .. itemDisplayName(item), color = isPinned and PIN_COLOR or nil },
			{ text = rarity.name, color = rarity.color, bold = true },
			{ text = "$" .. math.floor(result.value + 0.5), color = C.sub },
			{ text = distanceText(item), color = C.sub },
			{
				text = isPinned and "Unpin" or "Pin",
				color = isPinned and PIN_COLOR or C.sub,
				onClick = function()
					togglePin(item)
				end,
			},
		}, function()
			togglePin(item) -- clicking anywhere on the row also pins / unpins
		end)
	end

	pruneSet(lootSet, seenH)
	pruneSet(lootLabels, seenL)

	lootTable.setBadge(#visible .. " items")
	lootTable.setEmpty("Nothing to show with these filters")
	local status = string.format("%d shown  ·  %d highlighted  ·  %d pinned", #visible, highlighted, #pinnedRows)
	if promptState.enabled and promptState.fixed > 0 then
		status ..= string.format("  ·  %d prompts", promptState.fixed)
	end
	if SETTINGS.minValue > 0 then
		status ..= string.format("  ·  min $%d", SETTINGS.minValue)
	end
	lootTable.setStatus(status)
end

-- Pins every scanned item of the chosen rarity (or higher)
F.applyAutoPin = function()
	if not autoPin.enabled or not S.lootData then
		return
	end

	for _, result in ipairs(S.lootData) do
		local item = result.item
		if result.index >= autoPin.minIndex and item.Parent and not pinned[item] and not autoPin.skip[item] and not belowMinValue(item) then
			pinned[item] = true
		end
	end
end

-- Finds every ProximityPrompt inside the scanned loot objects and sets its hold time to 0
F.applyInstantPrompts = function()
    promptState.fixed = 0

    if not promptState.enabled or not S.lootData then
        return
    end

    local function fix(prompt)
        prompt.HoldDuration = 0

        -- Start monitoring BaseHold changes for this prompt.
        monitorBaseHold(prompt)

        -- Games that keep a base value to restore the hold time from
        if prompt:GetAttribute("BaseHold") ~= nil then
            prompt:SetAttribute("BaseHold", 0)
        end

        local baseHold = prompt:FindFirstChild("BaseHold")
        if baseHold and baseHold:IsA("ValueBase") then
            pcall(function()
                baseHold.Value = 0
            end)
        end

        promptState.fixed += 1
    end

    for _, result in ipairs(S.lootData) do
        local item = result.item

        if item.Parent then
            if item:IsA("ProximityPrompt") then
                fix(item)
            end

            for _, descendant in ipairs(item:GetDescendants()) do
                if descendant:IsA("ProximityPrompt") then
                    fix(descendant)
                end
            end
        end
    end
end

F.unloadLoot = function()
	S.lootData = nil
	F.renderLoot()
	OK_("Loot scan data unloaded.")
end

----------------------------------------------------------------------
-- Entity logic
----------------------------------------------------------------------
local entityShown = 0

F.renderEntities = function()
	entityTable.clear()

	if not S.entityData then
		esp.set("entities", {})
		entityTable.setEmpty("Press Scan to find entities")
		return
	end
	entityShown = 0
	local drawn = {}

	for _, result in ipairs(S.entityData) do
		local entity = result.entity
		if result.item.Parent and entity.enabled and table.find(ENTITIES, entity) then
			entityShown += 1

			if S.entityHighlightsOn then
				table.insert(drawn, { model = result.item, name = entity.name, color = entity.color })
			end

			entityTable.add({
				{ text = entity.name, color = entity.color, bold = true },
				{ text = result.item.ClassName, color = C.sub },
				{ text = distanceText(result.item), color = C.sub },
			})
		end
	end

	esp.set("entities", drawn)

	entityTable.setBadge(entityShown .. " found")
	entityTable.setEmpty("No enabled entities found")
	entityTable.setStatus(string.format("%d shown  ·  %d on ESP", entityShown, #drawn))
end

-- One pass over the workspace for everything being scanned (much cheaper than separate
-- passes). It yields by time, so the game never stutters while S.scanning.
F.scanWorld = function(wantLoot, wantEntities)
	if S.scanning then
		return
	end
	S.scanning = true

	if wantLoot then
		lootScanBtn.Text = "Scanning..."
		lootTable.setStatus("Scanning...", C.accent)
	end
	if wantEntities then
		entityScanBtn.Text = "Scanning..."
		entityTable.setStatus("Scanning...", C.accent)
	end

	local nameMap = {}
	for _, entity in ipairs(ENTITIES) do
		nameMap[entity.name] = entity
	end

	local items, found = {}, {}
	local processed, lastYield = 0, os.clock()

	local totalValue = 0
	local lootScan = false
	local entityScan = false

	for _, scanRoot in ipairs(SCAN_ROOTS) do
		for _, obj in ipairs(scanRoot:GetDescendants()) do
			processed += 1

			if wantLoot then
				lootScan = true
				local rarityName = obj:GetAttribute(RARITY_ATTRIBUTE)
				if type(rarityName) == "string" then
					local index = RARITY_INDEX[rarityName]
					if index then

						table.insert(items, {
							item = obj,
							index = index,
							value = tonumber(obj:GetAttribute("Value")) or 0,
						})

						if not belowMinValue(items[#items].item) then
							totalValue += items[#items].value
							--INFO_("Total Value: " .. totalValue)
						end
					end
				end
			end

			if wantEntities then
				entityScan = true
				local entity = nameMap[obj.Name]

				-- Skip parts that just repeat their parent's name (avoids double results)
				if entity and obj:IsA("PVInstance") and not (obj.Parent and obj.Parent.Name == obj.Name) then
					table.insert(found, { item = obj, entity = entity })
				end
			end

			if processed % 256 == 0 and os.clock() - lastYield > 0.006 then
				task.wait()
				lastYield = os.clock()
				if not gui.Parent then
					S.scanning = false
					return
				end
			end
		end
	end

	if lootScan == true then

		F.toast("Loot scan complete. Total value: " .. totalValue, "ok")
		INFO_("Total Value: " .. totalValue)
		lootScan = false
	elseif entityScan == true then
		F.toast("Entity scan complete: " .. entityShown, "ok")
	end

	if wantLoot then
		-- Highest rarity first, then highest value
		table.sort(items, function(x, y)
			if x.index ~= y.index then
				return x.index > y.index
			end
			return x.value > y.value
		end)

		S.lootData = items
		OK_("Loot scan completed: " .. #items .. " item(s) found.")
		F.applyAutoPin()
		F.applyInstantPrompts()
		F.renderLoot()
		lootScanBtn.Text = "Scan"
	end

	if wantEntities then
		S.entityData = found
		OK_("Entity scan completed: " .. #found .. " matching object(s) found.")
		F.renderEntities()
		entityScanBtn.Text = "Scan"
	end

	S.scanning = false
end

F.scanLoot = function()
	F.scanWorld(true, false)
end

F.scanEntities = function()
	F.scanWorld(false, true)
end

F.unloadEntities = function()
	S.entityData = nil
	F.renderEntities()
	OK_("Entity scan data unloaded.")
end

F.renderEntityList = function()
	for _, child in ipairs(entityList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	for index, entity in ipairs(ENTITIES) do
		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, entityList)

		local swatch = make("TextButton", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = entity.color,
			Text = "",
			AutoButtonColor = false,
			BorderSizePixel = 0,
		}, row)
		round(swatch, 4)

		label({
			Text = entity.name,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -78, 1, 0),
		}, row)

		makeCheckbox(row, entity.enabled, function(v)
			entity.enabled = v
			F.renderEntities()
		end, UDim2.new(1, -24, 0.5, 0))

		local remove = make("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			Text = "x",
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			TextColor3 = C.sub,
			AutoButtonColor = false,
		}, row)

		remove.MouseEnter:Connect(function()
			tween(remove, TI.FAST, { TextColor3 = C.accent })
		end)
		remove.MouseLeave:Connect(function()
			tween(remove, TI.FAST, { TextColor3 = C.sub })
		end)

		swatch.Activated:Connect(function()
			local current = table.find(PALETTE, entity.color) or 0
			entity.color = PALETTE[current % #PALETTE + 1]
			tween(swatch, TI.FAST, { BackgroundColor3 = entity.color })
			F.renderEntities()
		end)

		remove.Activated:Connect(function()
			table.remove(ENTITIES, table.find(ENTITIES, entity))
			F.renderEntityList()
			F.renderEntities()
		end)
	end
end

local function addEntity()
	local name = string.match(addBox.Text, "^%s*(.-)%s*$")
	addBox.Text = ""

	if name == "" then
		return
	end

	for _, entity in ipairs(ENTITIES) do
		if entity.name == name then
			return
		end
	end

	table.insert(ENTITIES, {
		name = name,
		enabled = true,
		color = PALETTE[#ENTITIES % #PALETTE + 1],
	})

	F.renderEntityList()
	entityTable.setStatus("Added " .. name .. "  ·  scan again to find it")
	OK_("Entity added to the scan list: " .. name)
end

----------------------------------------------------------------------
-- Player logic (Players service list)
----------------------------------------------------------------------
-- Entity = IsEntity attribute, or a character with more than `S.partThreshold` parts.
-- Accessories / Hats / Tools are not counted (when "Ignore accessories" is on), which is
-- what normally pushes survivors over the limit. Returns isEntity, partCount.
local isEntityPlayer
do
	local cache = setmetatable({}, { __mode = "k" }) -- [character] = { count, time, skip }

	F.countCharacterParts = function(parent, skipExtras)
		local count = 0
		for _, child in ipairs(parent:GetChildren()) do
			if skipExtras and (child:IsA("Accoutrement") or child:IsA("Tool")) then
				continue
			end
			if child:IsA("BasePart") then
				count += 1
			end
			count += F.countCharacterParts(child, skipExtras)
		end
		return count
	end


	isEntityPlayer = function(other)
		if other:GetAttribute("IsEntity") == true then
			return true, nil
		end

		local character = other.Character
		if not character then
			return false, nil
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return false, nil
		end

		local isEntity = humanoid.Health == math.huge
		local parts = F.countCharacterParts(character, S.ignoreAccessories)

		return isEntity, parts
	end
end

F.renderPlayers = function()
	playerTable.clear()

	if not S.playersActive then
		esp.set("players", {})
		playerTable.setEmpty("Press Refresh to list players")
		return
	end

	local myCharacter = player.Character
	local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
	local entries = {}

	for _, other in ipairs(Players:GetPlayers()) do
		if S.includeSelf or other ~= player then
			local character = other.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local otherRoot = character and character:FindFirstChild("HumanoidRootPart")

			local isEntity, parts = isEntityPlayer(other)
			--print("INSIDE SCRIPT INFO: " .. isEntity)
			table.insert(entries, {
				player = other,
				character = character,
				humanoid = humanoid,
				isEntity = isEntity,
				parts = parts,
				away = (myRoot and otherRoot) and (otherRoot.Position - myRoot.Position).Magnitude or math.huge,
			})
		end
	end

	table.sort(entries, function(a, b)
		return a.away < b.away
	end)

	local drawn = {}
	for _, entry in ipairs(entries) do

		local success, err = pcall(function()

			if entry.humanoid.Health == math.huge then
				entry.isEntity = true
				INFO_("Player " .. entry.player.Name .. " was set to be entity | Reason: Inf health")
			end
		end)

		if not success then
			WARN_(err)
		end
		
		local color = entry.isEntity and PLAYER_COLORS.Entity or PLAYER_COLORS.Survivor

		if S.playersHighlightsOn and entry.character and entry.character.Parent then
			table.insert(drawn, {
				model = entry.character,
				name = entry.player.Name,
				color = color,
				humanoid = entry.humanoid,
				fixed = not entry.isEntity, -- survivors get a steady fixed-size box
			})
		end

		playerTable.add({
			{ text = entry.player.Name },
			{ text = entry.isEntity and "Entity" or "Survivor", color = color, bold = true },
			{ text = entry.parts and tostring(entry.parts) or "-", color = C.sub },
			{ text = entry.humanoid and tostring(math.floor(entry.humanoid.Health + 0.5)) or "-", color = C.sub },
			{ text = entry.away == math.huge and "-" or tostring(math.floor(entry.away + 0.5)), color = C.sub },
		})
	end

	esp.set("players", drawn)

	playerTable.setBadge(#entries .. " players")
	playerTable.setEmpty("No other players")
	playerTable.setStatus(string.format("%d listed  ·  %d on ESP", #entries, #drawn))
end

-- Keep the list up to date when players join, leave or respawn (event-based, no loops)
local playerConnections = {}

local function refreshPlayersSoon()
	task.delay(0.5, function()
		if S.playersActive and gui.Parent then
			F.renderPlayers()
		end
	end)
end

local function watchPlayer(other)
	table.insert(playerConnections, other.CharacterAdded:Connect(refreshPlayersSoon))
end

for _, other in ipairs(Players:GetPlayers()) do
	watchPlayer(other)
end

table.insert(playerConnections, Players.PlayerAdded:Connect(function(other)
	watchPlayer(other)
	refreshPlayersSoon()
end))
table.insert(playerConnections, Players.PlayerRemoving:Connect(refreshPlayersSoon))

----------------------------------------------------------------------
-- Closet scanner logic
----------------------------------------------------------------------

local closetHighlights = {}

F.renderPlayerModels = function()
	modelTable.clear()

	local found = S.modelData or {}
	local seen = {}
	local shown = 0

	for _, closet in ipairs(found) do
		if closet and closet.Parent and closet:IsA("Model") and closet.Name == "Closet" then
			seen[closet] = true
			shown += 1

			if S.modelHighlightsOn then
				local highlight = closetHighlights[closet]

				if not highlight or not highlight.Parent then
					highlight = Instance.new("Highlight")
					highlight.Name = "LOOT_ClosetHighlight"
					highlight.Adornee = closet
					highlight.FillColor = Color3.fromRGB(235, 32, 24)
					highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
					highlight.FillTransparency = 0.65
					highlight.OutlineTransparency = 0
					highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					highlight.Parent = gui
					closetHighlights[closet] = highlight
				end
			end

			modelTable.add({
				{ text = "Closet", bold = true },
				{ text = "Model", color = C.accent, bold = true },
				{ text = "-", color = C.sub },
				{ text = distanceText(closet), color = C.sub },
			})
		end
	end

	for closet, highlight in pairs(closetHighlights) do
		if not seen[closet] or not S.modelHighlightsOn then
			highlight:Destroy()
			closetHighlights[closet] = nil
		end
	end

	modelTable.setBadge(shown .. " closets")
	modelTable.setEmpty("No closets found")
	modelTable.setStatus(tostring(shown) .. " closets found  ·  " .. tostring(math.min(shown, 31)) .. " maximum highlights supported")
end

F.scanPlayerModels = function()
	if S.scanning then
		return
	end

	S.scanning = true
	F.toast("Closet scanning...", "ok")
	modelScanBtn.Text = "Scanning..."
	modelTable.setStatus("Scanning ActiveMap...", C.accent)

	local found = {}
	local activeMap = workspace:FindFirstChild("ActiveMap")

	if not activeMap then
		S.modelData = {}
		F.renderPlayerModels()
		WARN_("ActiveMap was not found in Workspace.")
		modelScanBtn.Text = "Scan"
		S.scanning = false
		F.toast("Scan failed", "warn")
		return
	end

	local descendants = activeMap:GetDescendants()
	for i, obj in ipairs(descendants) do
		if obj:IsA("Model") and obj.Name == "Closet" then
			table.insert(found, obj)
		end

		if i % 500 == 0 then
			task.wait()
			if not gui.Parent then
				S.scanning = false
				modelScanBtn.Text = "Scan"
				return
			end
		end
	end

	S.modelData = found
	F.renderPlayerModels()
	OK_("Closet scan completed: " .. #found .. " model(s) found.")

	F.toast("Closet scan completed: " .. #found .. " model(s) found.", "ok")

	modelScanBtn.Text = "Scan"
	S.scanning = false
end

-- Re-render shortly after a slider stops changing (avoids rebuilding every step)
local rerenderPending = false
F.rerenderSoon = function()
	if rerenderPending then
		return
	end
	rerenderPending = true

	task.delay(0.15, function()
		rerenderPending = false
		if gui.Parent then
			F.renderLoot()
			F.renderEntities()
			F.renderPlayers()
			F.renderPlayerModels()
		end
	end)
end

----------------------------------------------------------------------
-- Auto scan: runs <delay> seconds after workspace.ActiveMap is removed AND added again
----------------------------------------------------------------------
local autoToken = 0
local mapRemoved = workspace:FindFirstChild(MAP_NAME) == nil
local mapConnections = {}

local function runAutoScan()
	-- wait for a manual scan that is still running, then do one combined pass
	while S.scanning and gui.Parent do
		task.wait(0.25)
	end
	if gui.Parent then
		F.scanWorld(true, true)
	end
end

table.insert(mapConnections, workspace.ChildRemoved:Connect(function(child)
	if child.Name == MAP_NAME then
		mapRemoved = true
		autoToken += 1 -- cancels a pending auto scan
	end
end))

table.insert(mapConnections, workspace.ChildAdded:Connect(function(child)
	if child.Name ~= MAP_NAME or not mapRemoved then
		return
	end
	mapRemoved = false

	if not autoScan.enabled then
		return
	end

	autoToken += 1
	local token = autoToken
	lootTable.setStatus(string.format("Auto scan in %ds...", autoScan.delay), C.accent)

	task.delay(autoScan.delay, function()
		if token == autoToken and autoScan.enabled and gui.Parent then
			runAutoScan()
		end
	end)
end))

----------------------------------------------------------------------
-- Configs (save / load settings)
-- Uses writefile / readfile / listfiles when your environment has them.
-- Otherwise configs are kept in memory for the current session only.
----------------------------------------------------------------------
do
local hasFiles = type(writefile) == "function"
	and type(readfile) == "function"
	and type(listfiles) == "function"
	and type(isfolder) == "function"
	and type(makefolder) == "function"

local memoryConfigs = {}

local function cleanConfigName(text)
	local name = string.gsub(text or "", "[^%w_%- ]", "")
	return (string.gsub(string.match(name, "^%s*(.-)%s*$"), "^_+", ""))
end

local function collectConfig()
	OK_("Collecting config...")
	local entities = {}
	for _, entity in ipairs(ENTITIES) do
		table.insert(entities, { name = entity.name, enabled = entity.enabled, color = entity.color:ToHex() })
	end

	local rarities = {}
	for _, rarity in ipairs(RARITIES) do
		rarities[rarity.name] = SHOW_RARITIES[rarity.name] ~= false
	end

	return {
		version = 2,
		rarities = rarities,
		entities = entities,
		settings = {
			maxHighlights = SETTINGS.maxHighlights,
			maxRows = SETTINGS.maxRows,
			fillTransparency = SETTINGS.fillTransparency,
			minValue = SETTINGS.minValue,
		},
		toggles = {
			loot = S.lootHighlightsOn,
			entity = S.entityHighlightsOn,
			players = S.playersHighlightsOn,
			includeSelf = S.includeSelf,
			models = S.modelHighlightsOn,
		},
		partThreshold = S.partThreshold,
		seeCmdPrompt = consoleEnabled,
		allowToasts = S.AllowToasts,
		autoScan = { enabled = autoScan.enabled, delay = autoScan.delay },
		radar = { enabled = radar.on, range = radar.range },
		instantPrompts = promptState.enabled,
		ignoreAccessories = S.ignoreAccessories,
		autoPin = { enabled = autoPin.enabled, minRarity = RARITIES[autoPin.minIndex].name },
		esp = {
			enabled = espSettings.enabled,
			box = espSettings.box,
			name = espSettings.name,
			distance = espSettings.distance,
			health = espSettings.health,
			tracers = espSettings.tracers,
			highlights = espSettings.highlights,
			maxDistance = espSettings.maxDistance,
			textSize = espSettings.textSize,
			thickness = espSettings.thickness,
		},
	}
end

local function applyConfig(data)
	if type(data) ~= "table" then
		return false
	end

	-- Rarity filters
	if type(data.rarities) == "table" then
		for _, rarity in ipairs(RARITIES) do
			local v = data.rarities[rarity.name]
			if type(v) == "boolean" then
				SHOW_RARITIES[rarity.name] = v
				controls["rarity:" .. rarity.name].set(v, true)
			end
		end
	end

	-- Entities
	if type(data.entities) == "table" then
		table.clear(ENTITIES)
		local loadedNames = {}

		for _, saved in ipairs(data.entities) do
			if type(saved) == "table" and type(saved.name) == "string" then
				local ok, color = pcall(Color3.fromHex, tostring(saved.color))
				local name = saved.name

				-- Migrate the previous spelling to the current default name.
				if name == "The Locus" then
					name = "The Locust"
				end

				if not loadedNames[name] then
					table.insert(ENTITIES, {
						name = name,
						enabled = saved.enabled ~= false,
						color = ok and color or PALETTE[#ENTITIES % #PALETTE + 1],
					})
					loadedNames[name] = true
				end
			end
		end

		-- Merge source defaults only when migrating an older config. This makes
		-- newly added default entities visible without undoing entity removals
		-- that a user makes in configs saved by this updated version.
		if (tonumber(data.version) or 1) < 2 then
			for _, default in ipairs(DEFAULT_ENTITIES) do
				if not loadedNames[default.name] then
					table.insert(ENTITIES, {
						name = default.name,
						enabled = default.enabled,
						color = default.color,
					})
					loadedNames[default.name] = true
				end
			end
		end

		F.renderEntityList()
	end

	-- Sliders
	local s = data.settings
	if type(s) == "table" then
		if type(s.maxHighlights) == "number" then
			SETTINGS.maxHighlights = math.clamp(math.floor(s.maxHighlights), 1, 31)
			controls.maxHighlights.set(SETTINGS.maxHighlights, true)
		end
		if type(s.maxRows) == "number" then
			SETTINGS.maxRows = math.clamp(math.floor(s.maxRows), 25, 300)
			controls.maxRows.set(SETTINGS.maxRows, true)
		end
		if type(s.fillTransparency) == "number" then
			SETTINGS.fillTransparency = math.clamp(s.fillTransparency, 0, 1)
			controls.fill.set(SETTINGS.fillTransparency, true)
		end
		if type(s.minValue) == "number" then
			controls.minValue.set(s.minValue, true)
		end
	end

	-- Toggles
	local t = data.toggles
	if type(t) == "table" then
		if type(t.loot) == "boolean" then
			S.lootHighlightsOn = t.loot
			controls.lootToggle.set(t.loot, true)
		end
		if type(t.entity) == "boolean" then
			S.entityHighlightsOn = t.entity
			controls.entityToggle.set(t.entity, true)
		end
		if type(t.players) == "boolean" then
			S.playersHighlightsOn = t.players
			controls.playersToggle.set(t.players, true)
		end
		if type(t.includeSelf) == "boolean" then
			S.includeSelf = t.includeSelf
			controls.includeSelf.set(t.includeSelf, true)
		end
		if type(t.models) == "boolean" then
			S.modelHighlightsOn = t.models
			controls.modelToggle.set(t.models, true)
		end
	end

	if type(data.seeCmdPrompt) == "boolean" then
		consoleEnabled = data.seeCmdPrompt
		if consoleFrame then
			consoleFrame.Visible = data.seeCmdPrompt
		end
		controls.seeCmdPrompt.set(data.seeCmdPrompt, true)
	end

	if type(data.allowToasts) == "boolean" then
		S.AllowToasts = data.allowToasts
		controls.seeToasts.set(data.allowToasts, true)
		if not data.allowToasts and F.toastGui then
			F.toastGui:Destroy()
			F.toastGui = nil
		end
	end

	if type(data.partThreshold) == "number" then
		S.partThreshold = math.clamp(math.floor(data.partThreshold), 5, 100)
		if controls.threshold then
			controls.threshold.set(S.partThreshold, true)
		end
	end

	-- Auto scan
	local a = data.autoScan
	if type(a) == "table" then
		if type(a.enabled) == "boolean" then
			autoScan.enabled = a.enabled
			controls.autoScan.set(a.enabled, true)
		end
		if type(a.delay) == "number" then
			autoScan.delay = math.clamp(math.floor(a.delay), 1, 60)
			controls.autoDelay.set(autoScan.delay, true)
		end
	end

	if type(data.ignoreAccessories) == "boolean" then
		S.ignoreAccessories = data.ignoreAccessories
		controls.ignoreAcc.set(S.ignoreAccessories, true)
	end

	local ap = data.autoPin
	if type(ap) == "table" then
		if type(ap.minRarity) == "string" and RARITY_INDEX[ap.minRarity] then
			controls.autoPinRarity.set(RARITY_INDEX[ap.minRarity])
		end
		if type(ap.enabled) == "boolean" then
			autoPin.enabled = ap.enabled
			controls.autoPin.set(ap.enabled, true)
		end
		F.applyAutoPin()
	end

	-- ESP
	local e = data.esp
	if type(e) == "table" then
		for _, key in ipairs({ "enabled", "box", "name", "distance", "health", "tracers", "highlights" }) do
			if type(e[key]) == "boolean" then
				espSettings[key] = e[key]
				controls["esp:" .. key].set(e[key], true)
			end
		end
		if type(e.maxDistance) == "number" then
			espSettings.maxDistance = math.clamp(math.floor(e.maxDistance), 100, 3000)
			controls["esp:maxDistance"].set(espSettings.maxDistance, true)
		end
		if type(e.textSize) == "number" then
			espSettings.textSize = math.clamp(math.floor(e.textSize), 10, 18)
			controls["esp:textSize"].set(espSettings.textSize, true)
		end
		if type(e.thickness) == "number" then
			espSettings.thickness = math.clamp(math.floor(e.thickness), 1, 3)
			controls["esp:thickness"].set(espSettings.thickness, true)
		end
	end

	if type(data.instantPrompts) == "boolean" then
		promptState.enabled = data.instantPrompts
		controls.instantPrompts.set(data.instantPrompts, true)
		F.applyInstantPrompts()
	end

	-- Radar
	local r = data.radar
	if type(r) == "table" then
		if type(r.range) == "number" then
			radar.range = math.clamp(math.floor(r.range), 50, 500)
			controls.radarRange.set(radar.range, true)
		end
		if type(r.enabled) == "boolean" then
			radar.setEnabled(r.enabled)
			controls.radar.set(r.enabled, true)
		end
	end

	F.applyFillTransparency()
	F.renderLoot()
	F.renderEntities()
	F.renderPlayers()
	F.renderPlayerModels()
	OK_("Configuration settings applied successfully.")

	return true
end

local function listConfigs()
	local names, seen = {}, {}

	-- every file is listed once, even if the executor returns it twice
	-- (different path separators / upper-lower case of the same name)
	local function add(name)
		local key = string.lower(name)
		if not seen[key] and string.sub(name, 1, 1) ~= "_" then
			seen[key] = true
			table.insert(names, name)
		end
	end

	if hasFiles then
		local ok, files = pcall(listfiles, CONFIG_FOLDER)
		if ok and type(files) == "table" then
			for _, path in ipairs(files) do
				local name = string.match(path, "([^/\\]+)%.json$")
				if name then
					add(name)
				end
			end
		end
	else
		for name in pairs(memoryConfigs) do
			add(name)
		end
	end

	table.sort(names, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	return names
end

local function writeConfig(name, json)
	if hasFiles then
		return pcall(function()
			if not isfolder(CONFIG_FOLDER) then
				makefolder(CONFIG_FOLDER)
			end
			writefile(CONFIG_FOLDER .. "/" .. name .. ".json", json)
		end)
	end

	memoryConfigs[name] = json
	return true
end

local function readConfig(name)
	if hasFiles then
		local ok, result = pcall(readfile, CONFIG_FOLDER .. "/" .. name .. ".json")
		return ok and result or nil
	end
	return memoryConfigs[name]
end

local function removeConfig(name)
	if hasFiles then
		if type(delfile) == "function" then
			return pcall(delfile, CONFIG_FOLDER .. "/" .. name .. ".json")
		end
		return false
	end

	memoryConfigs[name] = nil
	return true
end

-- Names of the saved configs (refreshed whenever the list is redrawn or before saving)
local cachedNames = {}

local function refreshNames()
	cachedNames = listConfigs()
	return cachedNames
end

-- The exact saved name that matches `name` (ignoring upper / lower case), or nil
local function findConfig(name)
	local key = string.lower(name)
	for _, existing in ipairs(cachedNames) do
		if string.lower(existing) == key then
			return existing
		end
	end
	return nil
end

-- Configs page UI ---------------------------------------------------------
local _, cfgBody = makeCard(pages.Configs, "Configs", UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))

local cfgBox = make("TextBox", {
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.new(1, -112, 0, 26),
	BackgroundColor3 = C.panel2,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamMedium,
	TextSize = 12,
	TextColor3 = C.text,
	PlaceholderText = "Config name",
	PlaceholderColor3 = C.sub,
	Text = "",
	ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left,
}, cfgBody)
round(cfgBox, 5)
make("UIPadding", { PaddingLeft = UDim.new(0, 8) }, cfgBox)

local cfgSaveBtn = makeButton({
	Text = "Save",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(88, 26),
}, cfgBody, C.accent)

-- Tells you whether the typed name is new or will overwrite a saved config
local cfgHint = label({
	TextSize = 11,
	TextColor3 = C.sub,
	Position = UDim2.fromOffset(12, 39),
	Size = UDim2.new(1, -24, 0, 14),
}, cfgBody)

-- Settings that belong to the config system itself (autoload / auto-save), kept in
-- LootDash/_settings.json so they survive between sessions
local META_PATH = CONFIG_FOLDER .. "/_settings.json"
local meta = { autoload = nil, autosave = false, active = nil }
local lastSavedJson = nil

local function saveMeta()
	if not hasFiles then
		return
	end
	pcall(function()
		if not isfolder(CONFIG_FOLDER) then
			makefolder(CONFIG_FOLDER)
		end
		writefile(META_PATH, HttpService:JSONEncode(meta))
	end)
end

local function loadMeta()
	if not hasFiles then
		return
	end
	local ok, raw = pcall(readfile, META_PATH)
	if not ok or type(raw) ~= "string" then
		return
	end
	local decoded, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if decoded and type(data) == "table" then
		meta.autoload = type(data.autoload) == "string" and data.autoload or nil
		meta.active = type(data.active) == "string" and data.active or nil
		meta.autosave = data.autosave == true
	end
end

local cfgAutosaveRow = makeRow(cfgBody, "Auto-save changes to the active config", 1)
cfgAutosaveRow.Position = UDim2.fromOffset(12, 58)
cfgAutosaveRow.Size = UDim2.new(1, -24, 0, 26)
controls.autosave = makeCheckbox(cfgAutosaveRow, meta.autosave, function(v)
	meta.autosave = v
	saveMeta()
end)

local cfgListHeader = label({
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextColor3 = C.sub,
	Text = "SAVED CONFIGS",
	Position = UDim2.fromOffset(12, 90),
	Size = UDim2.new(1, -24, 0, 16),
}, cfgBody)

make("Frame", {
	Position = UDim2.fromOffset(0, 108),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = C.stroke,
	BorderSizePixel = 0,
}, cfgBody)

local cfgList = make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 110),
	Size = UDim2.new(1, 0, 1, -132),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = Color3.fromRGB(90, 90, 104),
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, cfgBody)
make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, cfgList)
make("UIPadding", {
	PaddingTop = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, cfgList)

local cfgEmpty = label({
	Text = "No saved configs yet",
	TextColor3 = C.sub,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(0, 110),
	Size = UDim2.new(1, 0, 1, -132),
}, cfgBody)

local cfgStatus = label({
	TextSize = 11,
	TextColor3 = C.sub,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 12, 1, -4),
	Size = UDim2.new(1, -24, 0, 16),
	Text = hasFiles and ("Saved to workspace/" .. CONFIG_FOLDER .. "/")
		or "No file access here - configs last until you close the script",
}, cfgBody)

local function setCfgStatus(text, color)
	cfgStatus.Text = text
	cfgStatus.TextColor3 = color or C.sub
end

-- Confirmation popup ("This will overwrite the file ...") ---------------------
local confirmFrame = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Active = true, -- blocks clicks on everything underneath
	Visible = false,
	ZIndex = 20,
}, cfgBody)

local confirmBox = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(360, 124),
	BackgroundColor3 = C.panel2,
	BorderSizePixel = 0,
	ZIndex = 21,
}, confirmFrame)
round(confirmBox, 6)
outline(confirmBox, C.accent)

local confirmText = label({
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 13,
	Position = UDim2.fromOffset(18, 14),
	Size = UDim2.new(1, -36, 0, 54),
	ZIndex = 22,
}, confirmBox)

local confirmYes = makeButton({
	Text = "Overwrite",
	Position = UDim2.new(0.5, -112, 1, -42),
	Size = UDim2.fromOffset(104, 28),
	ZIndex = 22,
}, confirmBox, C.accent)

local confirmNo = makeButton({
	Text = "Cancel",
	Position = UDim2.new(0.5, 8, 1, -42),
	Size = UDim2.fromOffset(104, 28),
	ZIndex = 22,
}, confirmBox, C.panel)

local pendingConfirm = nil

local function askOverwrite(name, onConfirm)
	pendingConfirm = onConfirm
	confirmText.Text = "This will overwrite the file '" .. name .. "'. Are you sure?"
	confirmFrame.Visible = true
end

confirmYes.Activated:Connect(function()
	confirmFrame.Visible = false
	local action = pendingConfirm
	pendingConfirm = nil
	if action then
		action()
	end
end)

confirmNo.Activated:Connect(function()
	confirmFrame.Visible = false
	pendingConfirm = nil
	setCfgStatus("Cancelled - nothing was overwritten")
end)

local function updateHint()
	local name = cleanConfigName(cfgBox.Text)
	local existing = name ~= "" and findConfig(name) or nil

	if name == "" then
		cfgHint.Text = "Type a name to save, or click a saved config below to reuse its name"
		cfgHint.TextColor3 = C.sub
		cfgSaveBtn.Text = "Save"
	elseif existing then
		cfgHint.Text = "'" .. existing .. "' already exists - saving will overwrite it"
		cfgHint.TextColor3 = C.accent
		cfgSaveBtn.Text = "Overwrite"
	else
		cfgHint.Text = "New config '" .. name .. "'"
		cfgHint.TextColor3 = C.sub
		cfgSaveBtn.Text = "Save"
	end
end

cfgBox:GetPropertyChangedSignal("Text"):Connect(updateHint)

local function encodedConfig()
	local ok, json = pcall(HttpService.JSONEncode, HttpService, collectConfig())
	return ok and json or nil
end

local function loadConfigByName(name)
	local json = readConfig(name)
	if not json then
		return false, "Could not read '" .. name .. "'"
	end

	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or not applyConfig(data) then
		return false, "'" .. name .. "' is not a valid config"
	end

	meta.active = name
	lastSavedJson = encodedConfig()

	-- Persist a one-time migration so the new entity list survives future runs.
	if (tonumber(data.version) or 1) < 2 and lastSavedJson then
		writeConfig(name, lastSavedJson)
	end

	saveMeta()
	OK_("Configuration loaded successfully: " .. name)
	return true
end

F.renderConfigList = function()
	for _, child in ipairs(cfgList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local names = refreshNames()
	cfgEmpty.Visible = #names == 0
	cfgListHeader.Text = "SAVED CONFIGS (" .. #names .. ")"

	for index, name in ipairs(names) do
		local isAutoload = meta.autoload == name
		local suffix = (meta.active == name and "  (active)" or "") .. (isAutoload and "  [autoload]" or "")

		local row = make("Frame", {
			Size = UDim2.new(1, 0, 0, 28),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, cfgList)

		-- clicking the name copies it into the name box (handy for overwriting)
		local nameBtn = make("TextButton", {
			Text = name .. suffix,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = meta.active == name and C.text or C.sub,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, -190, 1, 0),
		}, row)

		local autoBtn = makeButton({
			Text = isAutoload and "Autoload: on" or "Autoload",
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -116, 0.5, 0),
			Size = UDim2.fromOffset(84, 22),
		}, row, isAutoload and C.accent or C.panel2)

		local loadBtn = makeButton({
			Text = "Load",
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -58, 0.5, 0),
			Size = UDim2.fromOffset(52, 22),
		}, row, C.panel2)

		local deleteBtn = makeButton({
			Text = "Delete",
			TextSize = 11,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(52, 22),
		}, row, C.accentDark)

		nameBtn.Activated:Connect(function()
			cfgBox.Text = name
		end)

		autoBtn.Activated:Connect(function()
			meta.autoload = (meta.autoload == name) and nil or name
			saveMeta()
			setCfgStatus(meta.autoload and ("'" .. name .. "' loads automatically on start") or "Autoload turned off")
			F.renderConfigList()
		end)

		loadBtn.Activated:Connect(function()
			local ok, err = loadConfigByName(name)
			if ok then
				cfgBox.Text = name
				setCfgStatus("Loaded '" .. name .. "'")
				F.renderConfigList()
			else
				setCfgStatus(err, C.accent)
			end
		end)

		deleteBtn.Activated:Connect(function()
			if removeConfig(name) then
				if meta.autoload == name then
					meta.autoload = nil
				end
				if meta.active == name then
					meta.active = nil
				end
				saveMeta()
				setCfgStatus("Deleted '" .. name .. "'")
				OK_("Configuration deleted successfully: " .. name)
			else
				setCfgStatus("Could not delete (no delfile here)", C.accent)
			end
			F.renderConfigList()
			updateHint()
		end)
	end

	updateHint()
end

local function saveCurrentConfig()
	local name = cleanConfigName(cfgBox.Text)
	if name == "" then
		setCfgStatus("Type a config name first", C.accent)
		return
	end

	-- same name = same file: reuse the saved name instead of making a second copy
	refreshNames()
	local existing = findConfig(name)
	local target = existing or name

	local function doSave()
		local json = encodedConfig()
		if not json then
			setCfgStatus("Could not encode config", C.accent)
			return
		end

		if writeConfig(target, json) then
			meta.active = target
			lastSavedJson = json
			saveMeta()
			cfgBox.Text = target
			setCfgStatus((existing and "Overwrote '" or "Saved '") .. target .. "'")
			OK_((existing and "Configuration overwritten successfully: " or "Configuration saved successfully: ") .. target)
			F.renderConfigList()
		else
			setCfgStatus("Could not write the file", C.accent)
		end
	end

	if existing then
		askOverwrite(existing, doSave)
	else
		doSave()
	end
end

cfgSaveBtn.Activated:Connect(saveCurrentConfig)
cfgBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		saveCurrentConfig()
	end
end)

-- Writes the active config if anything changed since it was last saved
local function autosaveNow()
	if not (meta.autosave and meta.active) then
		return
	end
	local json = encodedConfig()
	if json and json ~= lastSavedJson and writeConfig(meta.active, json) then
		lastSavedJson = json
	end
end

task.spawn(function()
	while gui.Parent do
		task.wait(15)
		if gui.Parent then
			autosaveNow()
		end
	end
end)

configApi.flush = autosaveNow

-- Called once at the end of the script: reads _settings.json and loads the autoload config
configApi.autoload = function()
	loadMeta()
	controls.autosave.set(meta.autosave, true)

	if meta.autoload then
		local ok, err = loadConfigByName(meta.autoload)
		if ok then
			cfgBox.Text = meta.autoload
			setCfgStatus("Auto-loaded '" .. meta.autoload .. "'")
			OK_("Startup autoload completed successfully: " .. meta.autoload)
		else
			setCfgStatus(err, C.accent)
		end
	end

	F.renderConfigList()
end

end

----------------------------------------------------------------------
-- Radar (movable, toggled with the "Radar" checkbox on the Players page)
-- Up = where your camera looks. Red = Entity, green = Survivor.
----------------------------------------------------------------------
do
	local SIZE = 180
	local HALF = SIZE / 2
	local LIMIT = HALF - 6

	local frame = make("Frame", {
		Name = "Radar",
		Position = UDim2.new(1, -SIZE - 30, 0, 80),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Active = true,
		Visible = false,
	}, gui)
	round(frame, HALF)
	outline(frame, C.accent)

	local ring = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(SIZE / 2, SIZE / 2),
		BackgroundTransparency = 1,
	}, frame)
	round(ring, SIZE / 4)
	outline(ring, C.stroke)

	make("Frame", {
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.stroke,
		BorderSizePixel = 0,
	}, frame)
	make("Frame", {
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = C.stroke,
		BorderSizePixel = 0,
	}, frame)

	local center = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, frame)
	round(center, 3)

	local rangeLabel = label({
		TextSize = 10,
		TextColor3 = C.sub,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 1, -30),
		Size = UDim2.new(1, 0, 0, 14),
	}, frame)

	local dots = {}
	local lastRange

	local function getDot(other)
		local dot = dots[other]
		if not dot then
			dot = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BorderSizePixel = 0,
				Visible = false,
			}, frame)
			round(dot, 5)
			dots[other] = dot
		end
		return dot
	end

	radar.setEnabled = function(v)
		radar.on = v
		frame.Visible = v
	end

	local function update()
		if not radar.on then
			return
		end

		if radar.range ~= lastRange then
			lastRange = radar.range
			rangeLabel.Text = radar.range .. " studs"
		end

		local camera = workspace.CurrentCamera
		local myCharacter = player.Character
		local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")

		for other, dot in pairs(dots) do
			if not other.Parent then
				dot:Destroy()
				dots[other] = nil
			elseif not myRoot or not camera then
				dot.Visible = false
			end
		end

		if not myRoot or not camera then
			return
		end

		local look = camera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, -1)
		local right = flat:Cross(Vector3.yAxis)

		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local character = other.Character
				local otherRoot = character and character:FindFirstChild("HumanoidRootPart")

				if otherRoot then
					local dot = getDot(other)
					local delta = otherRoot.Position - myRoot.Position
					local x = delta:Dot(right) / radar.range * LIMIT
					local y = -delta:Dot(flat) / radar.range * LIMIT

					local distance = math.sqrt(x * x + y * y)
					local atEdge = distance > LIMIT
					if atEdge then
						x, y = x / distance * LIMIT, y / distance * LIMIT
					end

					local entity = isEntityPlayer(other)
					local dotSize = entity and 10 or 7
					dot.Size = UDim2.fromOffset(dotSize, dotSize)
					dot.Position = UDim2.fromOffset(HALF + x, HALF + y)
					dot.BackgroundColor3 = entity and PLAYER_COLORS.Entity or PLAYER_COLORS.Survivor
					dot.BackgroundTransparency = atEdge and 0.5 or 0
					dot.Visible = true
				elseif dots[other] then
					dots[other].Visible = false
				end
			end
		end
	end

	-- ~30 updates per second is plenty for a radar
	local radarClock = 0
	table.insert(mapConnections, RunService.RenderStepped:Connect(function(dt)
		if not radar.on then
			return
		end
		radarClock += dt
		if radarClock >= 1 / 30 then
			radarClock = 0
			update()
		end
	end))

	-- Dragging the radar around
	local radarDragging = false
	local radarDragStart, radarStartPosition

	frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			radarDragging = true
			radarDragStart = input.Position
			radarStartPosition = frame.Position
		end
	end)

	table.insert(mapConnections, UserInputService.InputChanged:Connect(function(input)
		if radarDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - radarDragStart
			frame.Position = UDim2.new(
				radarStartPosition.X.Scale,
				radarStartPosition.X.Offset + delta.X,
				radarStartPosition.Y.Scale,
				radarStartPosition.Y.Offset + delta.Y
			)
		end
	end))

	table.insert(mapConnections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			radarDragging = false
		end
	end))
end

----------------------------------------------------------------------
-- 2D ESP: boxes, names, distance, health bars and tracers drawn on screen.
-- Entities / players / player models register their targets with esp.set(group, list)
-- (each target: model, name, color, humanoid?, fixed?). A separate ScreenGui sits
-- behind the window and keeps drawing even while the window is hidden with DEL.
----------------------------------------------------------------------
do
	local BIND_NAME = "LootDashESP"
	local FIXED_SIZE = Vector3.new(3.6, 5.8, 2) -- steady box for normal characters
	local CORNERS = {
		{ -1, -1, -1 }, { -1, -1, 1 }, { -1, 1, -1 }, { -1, 1, 1 },
		{ 1, -1, -1 }, { 1, -1, 1 }, { 1, 1, -1 }, { 1, 1, 1 },
	}
	local INFO_COLOR = Color3.fromRGB(225, 225, 235)

	local espGui = make("ScreenGui", {
		Name = "LootDashESP",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = -10,
	}, playerGui)

	local groups = {}
	local pool = {} -- [model] = ui
	local present = {}
	local highlights = {} -- [model] = Highlight (only when the Highlights option is on)
	local keepHighlight = {}

	local function textLabel(anchorY, font)
		return make("TextLabel", {
			AnchorPoint = Vector2.new(0.5, anchorY),
			Size = UDim2.fromOffset(260, 16),
			BackgroundTransparency = 1,
			Font = font,
			TextSize = 12,
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.4,
			Visible = false,
		}, espGui)
	end

	local function createUI()
		local ui = {}

		ui.box = make("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, espGui)
		ui.stroke = make("UIStroke", {
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, ui.box)

		ui.name = textLabel(1, Enum.Font.GothamBold)
		ui.info = textLabel(0, Enum.Font.GothamMedium)
		ui.info.TextColor3 = INFO_COLOR

		ui.healthBg = make("Frame", {
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Visible = false,
		}, espGui)
		ui.healthFill = make("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 1),
			BorderSizePixel = 0,
		}, ui.healthBg)

		ui.tracer = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			BackgroundTransparency = 0.25,
			Visible = false,
		}, espGui)

		return ui
	end

	local function destroyUI(ui)
		ui.box:Destroy()
		ui.name:Destroy()
		ui.info:Destroy()
		ui.healthBg:Destroy()
		ui.tracer:Destroy()
	end

	local function setVisible(obj, v)
		if obj.Visible ~= v then
			obj.Visible = v
		end
	end

	local function hideUI(ui)
		if ui.shown then
			ui.shown = false
			ui.box.Visible = false
			ui.name.Visible = false
			ui.info.Visible = false
			ui.healthBg.Visible = false
			ui.tracer.Visible = false
		end
	end

	local function setText(textObj, text, color, size)
		if textObj.Text ~= text then
			textObj.Text = text
		end
		if color and textObj.TextColor3 ~= color then
			textObj.TextColor3 = color
		end
		if textObj.TextSize ~= size then
			textObj.TextSize = size
		end
	end

	-- Returns true when the target was drawn
	local function drawTarget(ui, target, camera, camPos, viewport)
		local model = target.model

		local cf, size
		local rootPart = target.fixed and model:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			cf = rootPart.CFrame * CFrame.new(0, -0.1, 0)
			size = FIXED_SIZE
		elseif model:IsA("Model") then
			cf, size = model:GetBoundingBox()
		elseif model:IsA("BasePart") then
			cf, size = model.CFrame, model.Size
		else
			return false
		end

		local distance = (cf.Position - camPos).Magnitude
		if distance > espSettings.maxDistance then
			return false
		end

		-- project the 8 corners of the box onto the screen
		local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		local inFront = false

		for i = 1, 8 do
			local sign = CORNERS[i]
			local point = camera:WorldToViewportPoint(cf * Vector3.new(hx * sign[1], hy * sign[2], hz * sign[3]))
			if point.Z > 0 then
				inFront = true
				if point.X < minX then minX = point.X end
				if point.X > maxX then maxX = point.X end
				if point.Y < minY then minY = point.Y end
				if point.Y > maxY then maxY = point.Y end
			end
		end

		if not inFront then
			return false
		end
		if maxX < 0 or minX > viewport.X or maxY < 0 or minY > viewport.Y then
			return false
		end

		minX, minY = math.floor(minX + 0.5), math.floor(minY + 0.5)
		maxX, maxY = math.floor(maxX + 0.5), math.floor(maxY + 0.5)
		local width = math.max(maxX - minX, 2)
		local height = math.max(maxY - minY, 2)
		local centerX = minX + width / 2

		local color = target.color
		local textSize = espSettings.textSize
		ui.shown = true

		-- box
		local showBox = espSettings.box
		setVisible(ui.box, showBox)
		if showBox then
			ui.box.Position = UDim2.fromOffset(minX, minY)
			ui.box.Size = UDim2.fromOffset(width, height)
			if ui.stroke.Color ~= color then
				ui.stroke.Color = color
			end
			if ui.stroke.Thickness ~= espSettings.thickness then
				ui.stroke.Thickness = espSettings.thickness
			end
		end

		-- name above the box
		local showName = espSettings.name
		setVisible(ui.name, showName)
		if showName then
			ui.name.Position = UDim2.fromOffset(centerX, minY - 2)
			setText(ui.name, target.name, color, textSize)
		end

		-- distance below the box
		local showDistance = espSettings.distance
		setVisible(ui.info, showDistance)
		if showDistance then
			ui.info.Position = UDim2.fromOffset(centerX, maxY + 2)
			setText(ui.info, string.format("%d studs", math.floor(distance + 0.5)), nil, textSize)
		end

		-- health bar on the left of the box
		local humanoid = target.humanoid
		local showHealth = espSettings.health
			and humanoid ~= nil
			and humanoid.Parent ~= nil
			and humanoid.MaxHealth > 0
		setVisible(ui.healthBg, showHealth)
		if showHealth then
			local fraction = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
			ui.healthBg.Position = UDim2.fromOffset(minX - 6, minY)
			ui.healthBg.Size = UDim2.fromOffset(3, height)
			ui.healthFill.Size = UDim2.fromScale(1, fraction)
			ui.healthFill.BackgroundColor3 = Color3.fromHSV(fraction * 0.33, 1, 1)
		end

		-- tracer from the bottom centre of the screen to the bottom of the box
		local showTracer = espSettings.tracers
		setVisible(ui.tracer, showTracer)
		if showTracer then
			local fromX, fromY = viewport.X / 2, viewport.Y
			local dx, dy = centerX - fromX, maxY - fromY
			ui.tracer.Position = UDim2.fromOffset((fromX + centerX) / 2, (fromY + maxY) / 2)
			ui.tracer.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), 1)
			ui.tracer.Rotation = math.deg(math.atan2(dy, dx))
			if ui.tracer.BackgroundColor3 ~= color then
				ui.tracer.BackgroundColor3 = color
			end
		end
		return true
	end

	-- Optional Highlight on top of the 2D drawings (capped by "Max highlights")
	local function updateHighlights()
		table.clear(keepHighlight)

		if espSettings.enabled and espSettings.highlights then
			local count = 0
			for _, list in pairs(groups) do
				for _, target in ipairs(list) do
					if count >= SETTINGS.maxHighlights then
						break
					end

					local model = target.model
					if model.Parent and not keepHighlight[model] then
						count += 1
						keepHighlight[model] = true

						local color = target.color
						local highlight = highlights[model]

						if not highlight then
							highlight = Instance.new("Highlight")
							highlight.Name = "ESPHighlight"
							highlight.Adornee = model
							highlight.FillColor = color
							highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
							highlight.FillTransparency = 1
							highlight.OutlineTransparency = 1
							highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
							highlight.Parent = model
							tween(highlight, TI.SMOOTH, {
								FillTransparency = SETTINGS.fillTransparency,
								OutlineTransparency = 0,
							})
							highlights[model] = highlight
						elseif highlight.FillColor ~= color then
							highlight.FillColor = color
							highlight.OutlineColor = color:Lerp(Color3.new(1, 1, 1), 0.5)
						end
					end
				end
			end
		end

		for model, highlight in pairs(highlights) do
			if not keepHighlight[model] then
				highlight:Destroy()
				highlights[model] = nil
			end
		end
	end

	local function update()
		table.clear(present)
		for _, list in pairs(groups) do
			for _, target in ipairs(list) do
				present[target.model] = target
			end
		end

		-- remove the drawings of targets that are gone
		for model, ui in pairs(pool) do
			if not present[model] then
				destroyUI(ui)
				pool[model] = nil
			end
		end

		updateHighlights()

		if next(present) == nil then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera or not espSettings.enabled then
			for _, ui in pairs(pool) do
				hideUI(ui)
			end
			return
		end

		local viewport = camera.ViewportSize
		local camPos = camera.CFrame.Position

		for model, target in pairs(present) do
			local ui = pool[model]
			if not ui then
				ui = createUI()
				pool[model] = ui
			end

			if not (model.Parent and drawTarget(ui, target, camera, camPos, viewport)) then
				hideUI(ui)
			end
		end
	end

	esp.set = function(group, list)
		groups[group] = list
	end

	esp.applyFill = function()
		for _, highlight in pairs(highlights) do
			highlight.FillTransparency = SETTINGS.fillTransparency
		end
	end

	esp.destroy = function()
		pcall(RunService.UnbindFromRenderStep, RunService, BIND_NAME)
		for _, highlight in pairs(highlights) do
			highlight:Destroy()
		end
		table.clear(highlights)
		table.clear(groups)
		espGui:Destroy()
	end

	-- runs right after the camera updates so boxes never lag behind the view
	RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 1, update)
end

----------------------------------------------------------------------
-- Dragging (smooth, and idle when the window isn't moving)
----------------------------------------------------------------------
local dragging = false
local dragStart, startPosition, dragConnection
local targetPosition = root.Position

header.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then

		dragging = true
		dragStart = input.Position
		startPosition = root.Position
		targetPosition = root.Position

		if dragConnection then
			dragConnection:Disconnect()
		end

		dragConnection = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				if dragConnection then
					dragConnection:Disconnect()
					dragConnection = nil
				end
			end
		end)
	end
end)

local inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement
		and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if dragging then
		local delta = input.Position - dragStart
		targetPosition = UDim2.new(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end

	if activeSlider then
		activeSlider(input.Position.X)
	end
end)

local inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		activeSlider = nil
	end
end)

local renderConnection = RunService.RenderStepped:Connect(function(dt)
	local current = root.Position

	if not dragging
		and math.abs(current.X.Offset - targetPosition.X.Offset) < 0.05
		and math.abs(current.Y.Offset - targetPosition.Y.Offset) < 0.05
		and current.X.Scale == targetPosition.X.Scale
		and current.Y.Scale == targetPosition.Y.Scale then
		return
	end

	root.Position = current:Lerp(targetPosition, 1 - math.exp(-dt * 22))
end)

----------------------------------------------------------------------
-- Fold / close / wiring
----------------------------------------------------------------------
local folded = false

foldBtn.Activated:Connect(function()
	folded = not folded

	if folded then
		foldBtn.Text = "+"
		tween(root, TI.SMOOTH, { Size = UDim2.fromOffset(D.WIDTH, D.HEADER) })
		task.delay(0.3, function()
			if folded then
				bodyGroup.Visible = false
			end
		end)
	else
		foldBtn.Text = "-"
		bodyGroup.Visible = true
		tween(root, TI.SMOOTH, { Size = UDim2.fromOffset(D.WIDTH, D.HEIGHT) })
	end
end)

lootScanBtn.Activated:Connect(function()
	F.scanLoot()
end)
lootUnloadBtn.Activated:Connect(function()
	F.unloadLoot()
end)
entityScanBtn.Activated:Connect(function()
	F.scanEntities()
end)
entityUnloadBtn.Activated:Connect(function()
	F.unloadEntities()
end)

modelScanBtn.Activated:Connect(function()
	F.scanPlayerModels()
end)
modelUnloadBtn.Activated:Connect(function()
	S.modelData = nil
	F.renderPlayerModels()
end)

playerScanBtn.Activated:Connect(function()
	S.playersActive = true
	F.renderPlayers()
	F.toast("Players ESP on.", "ok")
end)
playerUnloadBtn.Activated:Connect(function()
	S.playersActive = false
	F.renderPlayers()
	F.toast("Players ESP off.", "ok")
end)

addBtn.Activated:Connect(addEntity)
addBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		addEntity()
	end
end)

-- Hide / show with the toggle key (the X button still closes it for good)
local hidden = false
local visibilityToken = 0

local function setHidden(state)
	hidden = state
	visibilityToken += 1
	local token = visibilityToken

	if hidden then
		dragging = false
		activeSlider = nil
		tween(rootScale, TI.FAST, { Scale = 0.95 })
		task.delay(0.15, function()
			if hidden and token == visibilityToken then
				root.Visible = false
			end
		end)
	else
		root.Visible = true
		tween(rootScale, TI.SMOOTH, { Scale = 1 })
	end
end

local toggleKeyConnection = UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == TOGGLE_KEY and not UserInputService:GetFocusedTextBox() then
		setHidden(not hidden)
	end
end)

local closing = false
closeBtn.Activated:Connect(function()
	if closing then
		return
	end
	closing = true

	configApi.flush() -- save the active config if auto-save is on
	print = originalPrint
	consoleToggleConnection:Disconnect()

	autoToken += 1 -- cancel any pending auto scan

	clearSet(lootSet)
	esp.destroy()
	clearSet(pinSet)
	clearSet(lootLabels)
	clearSet(pinLabels)

	for _, connection in ipairs(playerConnections) do
		connection:Disconnect()
	end
	for _, connection in ipairs(mapConnections) do
		connection:Disconnect()
	end

	renderConnection:Disconnect()
	inputChangedConnection:Disconnect()
	inputEndedConnection:Disconnect()
	toggleKeyConnection:Disconnect()

	tween(rootScale, TI.FAST, { Scale = 0.95 })
	tween(root, TI.FAST, { BackgroundTransparency = 1 })

	task.delay(0.18, function()
		gui:Destroy()
	end)
end)

----------------------------------------------------------------------
-- Start
----------------------------------------------------------------------
F.renderEntityList()
F.renderPinned()
configApi.autoload()
showPage("Loot")
tween(rootScale, TI.SMOOTH, { Scale = 1 })
task.wait(2)
OK_("LootDash initialized successfully.")



----------------------------------------------------------------------
-- VERSION CHECKING
----------------------------------------------------------------------
local function parseVersion(version)
    local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")

    if not major then
        return nil
    end

    return {
        tonumber(major),
        tonumber(minor),
        tonumber(patch)
    }
end

local function compareVersions(a, b)
    local versionA = parseVersion(a)
    local versionB = parseVersion(b)

    if not versionA or not versionB then
        return nil
    end

    for i = 1, 3 do
        if versionA[i] > versionB[i] then
            return 1
        elseif versionA[i] < versionB[i] then
            return -1
        end
    end

    return 0
end

local success, response = pcall(function()
    return game:HttpGet(S.VERSION_URL, true)
end)

if not success then
    WARN_("Version check failed: " .. tostring(response))
	F.toast("Version check failed; check debug terminal window for more info.", "warn")
else
    local decodedSuccess, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not decodedSuccess
        or type(data) ~= "table"
        or type(data.version) ~= "string"
        or type(data.minimumVersion) ~= "string" then
        WARN_("Invalid version information received")
		F.toast("Invalid version information received", "warn")
    else
        local comparison = compareVersions(S.CURRENT_VERSION, data.version)
        local minimumComparison = compareVersions(S.CURRENT_VERSION, data.minimumVersion)
		local IsBetaToString = tostring(data.IsBeta)
		
		--INFO_("Is Beta: " .. IsBetaToString)

        if comparison == nil or minimumComparison == nil then
            WARN_("Invalid version format")
			F.toast("Invalid version format", "warn")
        elseif minimumComparison < 0 then
            WARN_("Your script is outdated and must be updated.")
			F.toast("Your script is outdated and must be updated.", "warn")
            return
        elseif comparison < 0 then
            WARN_("A new version is available: V" .. data.version)
			F.toast("A new version is available: V" .. data.version, "warn")
        elseif comparison == 0 then
            OK_("Your script is up to date: V" .. S.CURRENT_VERSION)
			F.toast("Your script is up to date: V" .. S.CURRENT_VERSION, "ok")
        else
            OK_("You are running a newer version than the version server.")
			F.toast("You are running a newer version than the version server.", "ok")
        end
    end
end

----------------------------------------------------------------------
-- Owners and admins (fail-safe)
----------------------------------------------------------------------
do

-- !WARNING! This is 3/6 admins. I could not find the ID's of the others.
local TARGET_USER_IDS = {
	1847428505, -- Owner
	173533177, -- Game Moderator 1
	557995809 -- Game Moderator 2
}

local function isTargetUser(userId)
	return table.find(TARGET_USER_IDS, userId) ~= nil
end

local function onPresenceChanged(player, isHere)
	WARN_(player.Name .. (isHere and " is in the server." or " left the server."))
	F.toast(player.Name .. (isHere and " is in the server." or " left the server."), "warn")
end

for _, player in ipairs(Players:GetPlayers()) do
	if isTargetUser(player.UserId) then
		onPresenceChanged(player, true)
	end
end

Players.PlayerAdded:Connect(function(player)
	if isTargetUser(player.UserId) then
		onPresenceChanged(player, true)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if isTargetUser(player.UserId) then
		onPresenceChanged(player, false)
	end
end)

----------------------------------------------------------------------
-- Server hop
----------------------------------------------------------------------
local function serverHop()
	OK_("Teleporting player.")
    local player = Players.LocalPlayer
    local placeId = game.PlaceId
    local jobId = game.JobId

    TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.End then
        serverHop()
    end
end)
end
F.toast("Server hop fail-safe working. See debug terminal for more info.", "ok")
OK_("Server hop fail-safe working: 'End' key to hop servers - made incase an admin or owner joins the server. 3/6 admin ID's were collected, keep an eye on who joins.")



-----------------------------------------------------------------------
-- GUI VISIBILITY DEBUGGER
-- Suppresses normal visibility changes caused by user interaction.
-- Warns if GUI elements become hidden unexpectedly during interaction.
-----------------------------------------------------------------------

local UserInputService = game:GetService("UserInputService")

local INTERACTION_WINDOW = 1.0
local lastInteraction = 0
local watchedGui = setmetatable({}, { __mode = "k" })

local function markInteraction()
    lastInteraction = os.clock()
end

UserInputService.InputBegan:Connect(markInteraction)
UserInputService.InputEnded:Connect(markInteraction)

local function getVisibilityInfo(obj)
    local reasons = {}
    local current = obj

    while current and current ~= playerGui.Parent do
        if current:IsA("GuiObject") and not current.Visible then
            table.insert(
                reasons,
                current:GetFullName() .. " has Visible = false"
            )
        elseif current:IsA("LayerCollector") and not current.Enabled then
            table.insert(
                reasons,
                current:GetFullName() .. " has Enabled = false"
            )
        end

        current = current.Parent
    end

    return #reasons == 0 and obj:IsDescendantOf(playerGui), reasons
end

local function watchGuiObject(obj)
    if watchedGui[obj] then return end

    if not (obj:IsA("GuiObject") or obj:IsA("LayerCollector")) then
        return
    end

    watchedGui[obj] = true

    local function report(property)
        local actuallyVisible, reasons = getVisibilityInfo(obj)

        -- Ignore normal changes immediately following user input.
        if os.clock() - lastInteraction <= INTERACTION_WINDOW then
            return
        end

        if not actuallyVisible then
            warn(
                "[GUI HIDDEN]",
                obj:GetFullName(),
                "| Changed:", property
            )

            for _, reason in ipairs(reasons) do
                warn("  -> " .. reason)
            end
        end
    end

    if obj:IsA("GuiObject") then
        obj:GetPropertyChangedSignal("Visible"):Connect(function()
            report("Visible")
        end)
    end

    if obj:IsA("LayerCollector") then
        obj:GetPropertyChangedSignal("Enabled"):Connect(function()
            report("Enabled")
        end)
    end
end

for _, obj in ipairs(playerGui:GetDescendants()) do
    watchGuiObject(obj)
end

playerGui.DescendantAdded:Connect(watchGuiObject)

print("[GUI CHECK] Visibility monitoring enabled.")
