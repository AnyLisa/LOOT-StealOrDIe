
--[[
    STEAL OR DIE // LOOT LICENSE SYSTEM
    PythonAnywhere-backed key validation
    Draggable UI | Animated close | Hover effects
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FRAME_SIZE = 500

-- CONFIGURATION
local API_URL = "https://asedaskolannyheter.pythonanywhere.com"
local ENDPOINT = API_URL .. "/api/roblox/steal-or-die"

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local lootDashCheck = playerGui:FindFirstChild("LootDash")

if lootDashCheck then
    print("LOOT is already initialized.")
    return
else
    print("LOOT is not initialized.")
end

-- THEME
local COLORS = {
    Background = Color3.fromRGB(12, 12, 14),
    Panel = Color3.fromRGB(19, 19, 22),
    Surface = Color3.fromRGB(28, 28, 32),
    SurfaceHover = Color3.fromRGB(42, 30, 32),
    Border = Color3.fromRGB(60, 38, 40),

    White = Color3.fromRGB(255, 255, 255),

    Accent = Color3.fromRGB(255, 0, 0),
    AccentDark = Color3.fromRGB(190, 0, 0),

    Text = Color3.fromRGB(245, 245, 245),
    Muted = Color3.fromRGB(145, 140, 143),
    Error = Color3.fromRGB(255, 65, 65),
    Success = Color3.fromRGB(255, 0, 0),
}

local FONT = Enum.Font.Gotham
local FONT_BOLD = Enum.Font.GothamBold

local player = Players.LocalPlayer

if not player then
    warn("[STEAL OR DIE] Could not identify local player.")
    return
end

local httpRequest =
    (syn and syn.request)
    or (http and http.request)
    or request
    or http_request

if type(httpRequest) ~= "function" then
    warn("[STEAL OR DIE] HTTP requests are not supported by this executor.")
    return
end

if type(loadstring) ~= "function" then
    warn("[STEAL OR DIE] loadstring is not supported by this executor.")
    return
end

-- CLEAN UP PREVIOUS WINDOW
pcall(function()
    local oldGui = CoreGui:FindFirstChild("StealOrDieKeySystem")
    if oldGui then
        oldGui:Destroy()
    end
end)

-- HELPERS
local function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties) do
        object[property] = value
    end

    object.Parent = parent
    return object
end

local function tween(object, duration, properties, style, direction)
    local info = TweenInfo.new(
        duration,
        style or Enum.EasingStyle.Quint,
        direction or Enum.EasingDirection.Out
    )

    local animation = TweenService:Create(object, info, properties)
    animation:Play()

    return animation
end

local function corner(object, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius)
    }, object)
end

local function stroke(object, color, transparency, thickness)
    return create("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

-- ROOT GUI
local gui = create("ScreenGui", {
    Name = "StealOrDieKeySystem",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 999999,
}, CoreGui)

-- MAIN WINDOW
local frame = create("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    Size = UDim2.new(0, FRAME_SIZE, 0, 270),
    BackgroundColor3 = COLORS.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)

corner(frame, 12)
stroke(frame, COLORS.Border, 0.15, 1)

-- TOP ACCENT LINE
create("Frame", {
    Name = "AccentLine",
    Position = UDim2.fromOffset(18, 0),
    Size = UDim2.new(1, -36, 0, 3),
    BackgroundColor3 = COLORS.Accent,
    BorderSizePixel = 0,
}, frame)

-- TITLE BAR
local titleBar = create("Frame", {
    Name = "TitleBar",
    Position = UDim2.fromOffset(0, 3),
    Size = UDim2.new(1, 0, 0, 48),
    BackgroundColor3 = COLORS.Panel,
    BorderSizePixel = 0,
    Active = true,
}, frame)

-- BRAND MARK
local brandMark = create("Frame", {
    Position = UDim2.fromOffset(16, 12),
    Size = UDim2.fromOffset(24, 24),
    BackgroundColor3 = COLORS.Accent,
    BorderSizePixel = 0,
}, titleBar)

corner(brandMark, 6)

create("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "L",
    TextColor3 = COLORS.Background,
    TextSize = 16,
    Font = FONT_BOLD,
}, brandMark)

-- BRAND NAME
create("TextLabel", {
    Position = UDim2.fromOffset(49, 8),
    Size = UDim2.new(1, -105, 0, 19),
    BackgroundTransparency = 1,
    Text = "STEAL OR DIE",
    TextColor3 = COLORS.Text,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT_BOLD,
}, titleBar)

create("TextLabel", {
    Position = UDim2.fromOffset(50, 26),
    Size = UDim2.new(1, -110, 0, 13),
    BackgroundTransparency = 1,
    Text = "LOOT SYSTEM  /  LICENSE GATE",
    TextColor3 = COLORS.Muted,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT_BOLD,
}, titleBar)

-- CLOSE BUTTON
local closeButton = create("TextButton", {
    Name = "Close",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -13, 0.5, 0),
    Size = UDim2.fromOffset(29, 29),
    BackgroundColor3 = COLORS.Surface,
    BorderSizePixel = 0,
    Text = "×",
    TextColor3 = COLORS.Muted,
    TextSize = 23,
    Font = FONT,
    AutoButtonColor = false,
}, titleBar)

corner(closeButton, 7)


-- DIVIDER
create("Frame", {
    Position = UDim2.fromOffset(16, 51),
    Size = UDim2.new(1, -32, 0, 1),
    BackgroundColor3 = COLORS.Border,
    BackgroundTransparency = 0.35,
    BorderSizePixel = 0,
}, frame)

-- CONTENT
create("TextLabel", {
    Position = UDim2.fromOffset(22, 67),
    Size = UDim2.new(1, -44, 0, 25),
    BackgroundTransparency = 1,
    Text = "Access your loadout.",
    TextColor3 = COLORS.Text,
    TextSize = 19,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT_BOLD,
}, frame)

create("TextLabel", {
    Position = UDim2.fromOffset(23, 94),
    Size = UDim2.new(1, -46, 0, 19),
    BackgroundTransparency = 1,
    Text = "When activating your key, it will bind to your UserID. DO NOT SPOOF YOUR ID!",
    TextColor3 = COLORS.Muted,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT,
}, frame)

-- KEY FIELD CONTAINER
local inputFrame = create("Frame", {
    Name = "KeyInput",
    Position = UDim2.fromOffset(22, 128),
    Size = UDim2.new(1, -44, 0, 43),
    BackgroundColor3 = COLORS.Surface,
    BorderSizePixel = 0,
}, frame)

corner(inputFrame, 7)

local inputStroke = stroke(inputFrame, COLORS.Border, 0.15, 1)

-- KEY ICON
create("TextLabel", {
    Position = UDim2.fromOffset(12, 0),
    Size = UDim2.fromOffset(24, 43),
    BackgroundTransparency = 1,
    Text = "›",
    TextColor3 = COLORS.Accent,
    TextSize = 25,
    Font = FONT_BOLD,
}, inputFrame)

local keyBox = create("TextBox", {
    Name = "LicenseKey",
    Position = UDim2.fromOffset(38, 0),
    Size = UDim2.new(1, -50, 1, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "XXXX-XXXX-XXXX-XXXX",
    PlaceholderColor3 = COLORS.Muted,
    TextColor3 = COLORS.Text,
    TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT,
    ClearTextOnFocus = false,
}, inputFrame)

keyBox.Focused:Connect(function()
    tween(inputStroke, 0.18, {
        Color = COLORS.Accent,
        Transparency = 0,
    })
end)

keyBox.FocusLost:Connect(function()
    tween(inputStroke, 0.18, {
        Color = COLORS.Border,
        Transparency = 0.15,
    })
end)

-- VERIFY BUTTON
local submit = create("TextButton", {
    Name = "Verify",
    Position = UDim2.fromOffset(22, 183),
    Size = UDim2.new(1, -44, 0, 39),
    BackgroundColor3 = COLORS.Accent,
    BorderSizePixel = 0,
    Text = "VERIFY LICENSE",
    TextColor3 = COLORS.White,
    TextSize = 12,
    Font = FONT_BOLD,
    AutoButtonColor = false,
}, frame)

corner(submit, 7)

submit.MouseEnter:Connect(function()
    if not submit.Active then
        return
    end
end)


-- STATUS
local statusDot = create("Frame", {
    Position = UDim2.fromOffset(24, 239),
    Size = UDim2.fromOffset(6, 6),
    BackgroundColor3 = COLORS.Muted,
    BorderSizePixel = 0,
}, frame)

corner(statusDot, 10)

local status = create("TextLabel", {
    Position = UDim2.fromOffset(37, 232),
    Size = UDim2.new(1, -60, 0, 20),
    BackgroundTransparency = 1,
    Text = "READY  /  WAITING FOR LICENSE",
    TextColor3 = COLORS.Muted,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT_BOLD,
}, frame)

local function setStatus(message, color)
    status.Text = string.upper(message)
    status.TextColor3 = color or COLORS.Muted

    tween(statusDot, 0.15, {
        BackgroundColor3 = color or COLORS.Muted,
    })
end

-- ANIMATED CLOSE
local closing = false

local function closeWindow()
    if closing then
        return
    end

    closing = true
    submit.Active = false
    closeButton.Active = false

    -- Fade out the contents.
    for _, object in ipairs(frame:GetDescendants()) do
        if object:IsA("TextLabel") or object:IsA("TextButton")
            or object:IsA("TextBox") then
            tween(object, 0.16, {
                TextTransparency = 1,
                BackgroundTransparency = 1,
            })
        elseif object:IsA("Frame") then
            tween(object, 0.16, {
                BackgroundTransparency = 1,
            })
        elseif object:IsA("UIStroke") then
            tween(object, 0.16, {
                Transparency = 1,
            })
        end
    end

    tween(frame, 0.22, {
        Size = UDim2.fromOffset(340, 0),
        BackgroundTransparency = 1,
        Position = frame.Position + UDim2.fromOffset(0, 14),
    }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

    task.wait(0.24)

    if gui and gui.Parent then
        gui:Destroy()
    end
end

closeButton.Activated:Connect(closeWindow)

-- DRAGGING
local dragging = false
local dragStart
local startPosition
local dragInput

titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPosition = frame.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

titleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput and dragStart and startPosition then
        local delta = input.Position - dragStart

        frame.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

-- SERVER RESPONSE HELPERS
local function decodeError(response)
    if type(response.Body) == "string" then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if ok and type(data) == "table" then
            return data.message or "License validation failed."
        end
    end

    return "Server request failed."
end

-- LICENSE VALIDATION
local busy = false

local function resetButton()
    busy = false
    submit.Active = true
    submit.AutoButtonColor = false
    submit.Text = "VERIFY LICENSE"
    submit.BackgroundColor3 = COLORS.Accent
    submit.TextColor3 = COLORS.White
end

submit.Activated:Connect(function()
    if busy or closing then
        return
    end

    local key = keyBox.Text:match("^%s*(.-)%s*$")

    if key == "" then
        setStatus("ENTER A LICENSE KEY", COLORS.Error)
        tween(inputStroke, 0.15, {
            Color = COLORS.Error,
            Transparency = 0,
        })
        return
    end

    busy = true
    submit.Active = false
    submit.Text = "VERIFYING..."
    setStatus("CONTACTING LICENSE SERVER", COLORS.Accent)

    local requestOk, response = pcall(function()
        return httpRequest({
            Url = ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = HttpService:JSONEncode({
                key = key,
                roblox_user_id = tostring(player.UserId),
            }),
        })
    end)

    if closing then
        return
    end

    if not requestOk or type(response) ~= "table" then
        setStatus("CONNECTION FAILED", COLORS.Error)
        resetButton()
        return
    end

    local statusCode = tonumber(response.StatusCode or response.Status)

    if statusCode ~= 200 then
        setStatus(decodeError(response), COLORS.Error)
        resetButton()
        return
    end

    if type(response.Body) ~= "string" or response.Body == "" then
        setStatus("EMPTY SCRIPT RESPONSE", COLORS.Error)
        resetButton()
        return
    end

    local compileOk, loadedFunction = pcall(function()
        return loadstring(response.Body)
    end)

    if not compileOk or type(loadedFunction) ~= "function" then
        setStatus("SCRIPT COMPILATION FAILED", COLORS.Error)
        resetButton()
        return
    end

    setStatus("LICENSE ACCEPTED / LOADING", COLORS.Success)

    closeWindow()

    local runOk, runError = pcall(loadedFunction)

    if not runOk then
        warn("[STEAL OR DIE] Script execution error:", runError)
    end
end)

-- ENTRANCE ANIMATION
local finalSize = UDim2.new(0, FRAME_SIZE, 0, 270)

frame.Size = UDim2.new(0, 560, 0, 230)
frame.BackgroundTransparency = 1

tween(frame, 0.35, {
    Size = finalSize,
    BackgroundTransparency = 0,
}, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
