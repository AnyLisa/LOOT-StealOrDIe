
--[[
    LOOT // LICENSE SYSTEM
    Game: [UP] Just a baseplate.
    Black / Red Theme
    Image placeholder | Draggable | Rounded UI
    PythonAnywhere API validation
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

--==================================================
-- CONFIGURATION
--==================================================

local API_URL = "https://asedaskolannyheter.pythonanywhere.com"
local ENDPOINT = API_URL .. "/api/roblox/steal-or-die"

-- Replace 0 with your Roblox image asset ID when ready.
local IMAGE_ID = "rbxassetid://0"

local player = Players.LocalPlayer

if not player then
    warn("[LOOT] Could not identify local player.")
    return
end

local httpRequest =
    (syn and syn.request)
    or (http and http.request)
    or request
    or http_request

if type(httpRequest) ~= "function" then
    warn("[LOOT] HTTP requests are not supported.")
    return
end

if type(loadstring) ~= "function" then
    warn("[LOOT] loadstring is not supported.")
    return
end

pcall(function()
    local old = CoreGui:FindFirstChild("StealOrDieKeySystem")
    if old then
        old:Destroy()
    end
end)

--==================================================
-- THEME
--==================================================

local C = {
    Background = Color3.fromRGB(8, 7, 9),
    LeftPanel = Color3.fromRGB(19, 10, 14),
    Surface = Color3.fromRGB(17, 14, 17),
    SurfaceHover = Color3.fromRGB(31, 15, 19),

    Border = Color3.fromRGB(75, 23, 30),
    Red = Color3.fromRGB(255, 0, 20),
    RedHover = Color3.fromRGB(205, 0, 16),

    White = Color3.fromRGB(245, 245, 248),
    Muted = Color3.fromRGB(145, 139, 149),

    Error = Color3.fromRGB(255, 85, 95),
    Success = Color3.fromRGB(255, 0, 20),
}

local FONT = Enum.Font.Gotham
local BOLD = Enum.Font.GothamBold

--==================================================
-- HELPERS
--==================================================

local function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties) do
        object[property] = value
    end

    object.Parent = parent
    return object
end

local function round(object, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius),
    }, object)
end

local function outline(object, color, thickness)
    return create("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

local function animate(object, duration, properties, style, direction)
    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration,
            style or Enum.EasingStyle.Quint,
            direction or Enum.EasingDirection.Out
        ),
        properties
    )

    animation:Play()
    return animation
end

--==================================================
-- GUI ROOT
--==================================================

local gui = create("ScreenGui", {
    Name = "StealOrDieKeySystem",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 999999,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, CoreGui)

--==================================================
-- MAIN WINDOW
--==================================================

local WINDOW_WIDTH = 540
local WINDOW_HEIGHT = 238
local LEFT_WIDTH = 176
local CORNER_RADIUS = 10

local frame = create("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
    BackgroundColor3 = C.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)

round(frame, CORNER_RADIUS)
outline(frame, C.Red, 1)

--==================================================
-- LEFT IMAGE PANEL
--==================================================

-- Inset by one pixel so it cannot cover the outer border.
local leftPanel = create("Frame", {
    Name = "ImagePanel",
    Position = UDim2.fromOffset(1, 1),
    Size = UDim2.new(
        0,
        LEFT_WIDTH - 1,
        1,
        -2
    ),
    BackgroundColor3 = C.LeftPanel,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, frame)

round(leftPanel, CORNER_RADIUS)

-- Square off ONLY the inner/right corners.
-- This strip doesn't cover the rounded outer/left corners.
create("Frame", {
    Name = "SquareInnerCorners",
    Position = UDim2.new(1, -CORNER_RADIUS, 0, 0),
    Size = UDim2.new(0, CORNER_RADIUS, 1, 0),
    BackgroundColor3 = C.LeftPanel,
    BorderSizePixel = 0,
}, leftPanel)

-- IMAGE PLACEHOLDER
local image = create("ImageLabel", {
    Name = "LogoImage",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.5, 0, 0.44, 0),
    Size = UDim2.fromOffset(126, 126),
    BackgroundTransparency = 1,
    Image = IMAGE_ID,
    ScaleType = Enum.ScaleType.Fit,
}, leftPanel)

-- Branding at the bottom of the image panel.
create("TextLabel", {
    Name = "BrandName",
    Position = UDim2.new(0, 20, 1, -47),
    Size = UDim2.new(1, -30, 0, 17),
    BackgroundTransparency = 1,
    Text = "STEAL OR DIE",
    TextColor3 = C.Red,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = BOLD,
}, leftPanel)

create("TextLabel", {
    Name = "BrandSubtitle",
    Position = UDim2.new(0, 20, 1, -29),
    Size = UDim2.new(1, -30, 0, 14),
    BackgroundTransparency = 1,
    Text = "LOOT SYSTEM",
    TextColor3 = C.Muted,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = BOLD,
}, leftPanel)

-- Vertical divider.
create("Frame", {
    Name = "PanelDivider",
    Position = UDim2.fromOffset(LEFT_WIDTH, 1),
    Size = UDim2.new(0, 1, 1, -2),
    BackgroundColor3 = C.Border,
    BorderSizePixel = 0,
}, frame)

--==================================================
-- RIGHT CONTENT
--==================================================

local content = create("Frame", {
    Name = "Content",
    Position = UDim2.fromOffset(LEFT_WIDTH + 1, 1),
    Size = UDim2.new(1, -(LEFT_WIDTH + 2), 1, -2),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, frame)

-- Get game name
local MarketplaceService = game:GetService("MarketplaceService")
local success, info = pcall(function()
    return MarketplaceService:GetProductInfo(game.PlaceId)
end)

local gameName = info.Name

if success then
    print("Spelnamn:", gameName)
else
    warn("Kunde inte hämta spelnamnet.")
end

-- GAME NAME
create("TextLabel", {
    Name = "GameName",
    Position = UDim2.fromOffset(25, 19),
    Size = UDim2.fromOffset(205, 15),
    BackgroundTransparency = 1,
    Text = gameName,
    TextColor3 = C.Muted,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT,
}, content)

-- AD KEY / PREMIUM LABEL
local premiumLabel = create("TextButton", {
    Name = "PremiumLabel",
    Position = UDim2.new(1, -143, 0, 17),
    Size = UDim2.fromOffset(112, 19),
    BackgroundTransparency = 1,
    Text = "AD KEY / PREMIUM",
    TextColor3 = C.Red,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Right,
    Font = BOLD,
    AutoButtonColor = false,
}, content)

-- CLOSE BUTTON NEXT TO THE LABEL
local closeButton = create("TextButton", {
    Name = "CloseButton",
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -12, 0, 14),
    Size = UDim2.fromOffset(20, 22),
    BackgroundTransparency = 1,
    Text = "×",
    TextColor3 = C.Muted,
    TextSize = 17,
    Font = FONT,
    AutoButtonColor = false,
}, content)

closeButton.MouseEnter:Connect(function()
    animate(closeButton, 0.12, {
        TextColor3 = C.Red,
    })
end)

closeButton.MouseLeave:Connect(function()
    animate(closeButton, 0.12, {
        TextColor3 = C.Muted,
    })
end)

-- LOOT TITLE
create("TextLabel", {
    Name = "Title",
    Position = UDim2.fromOffset(25, 43),
    Size = UDim2.fromOffset(200, 34),
    BackgroundTransparency = 1,
    Text = '<font color="#FF0014">L</font><font color="#F5F5F8">OOT</font>',
    RichText = true,
    TextColor3 = C.White,
    TextSize = 29,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT,
}, content)

-- SUBTITLE / STATUS
local status = create("TextLabel", {
    Name = "Status",
    Position = UDim2.fromOffset(26, 78),
    Size = UDim2.new(1, -51, 0, 20),
    BackgroundTransparency = 1,
    Text = "Paste your key - a free ad key or Premium.",
    TextColor3 = C.Muted,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Font = FONT,
}, content)

local function setStatus(message, color)
    status.Text = tostring(message)
    status.TextColor3 = color or C.Muted
end

--==================================================
-- KEY INPUT
--==================================================

local inputFrame = create("Frame", {
    Name = "KeyInput",
    Position = UDim2.fromOffset(25, 105),
    Size = UDim2.new(1, -49, 0, 42),
    BackgroundColor3 = C.Surface,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, content)

round(inputFrame, 6)

local inputStroke = outline(inputFrame, C.Border, 1)

local keyBox = create("TextBox", {
    Name = "LicenseKey",
    Position = UDim2.fromOffset(13, 0),
    Size = UDim2.new(1, -108, 1, 0),
    BackgroundTransparency = 1,
    Text = "",
    PlaceholderText = "key",
    PlaceholderColor3 = C.Muted,
    TextColor3 = C.White,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = FONT,
    ClearTextOnFocus = false,
}, inputFrame)

keyBox.Focused:Connect(function()
    animate(inputStroke, 0.12, {
        Color = C.Red,
    })
end)

keyBox.FocusLost:Connect(function()
    animate(inputStroke, 0.12, {
        Color = C.Border,
    })
end)

-- UNLOCK BUTTON
local unlockButton = create("TextButton", {
    Name = "Unlock",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -4, 0.5, 0),
    Size = UDim2.fromOffset(88, 33),
    BackgroundColor3 = C.Red,
    BorderSizePixel = 0,
    Text = "Unlock",
    TextColor3 = C.White,
    TextSize = 11,
    Font = BOLD,
    AutoButtonColor = false,
}, inputFrame)

round(unlockButton, 4)

unlockButton.MouseEnter:Connect(function()
    if unlockButton.Active then
        animate(unlockButton, 0.12, {
            BackgroundColor3 = C.RedHover,
        })
    end
end)

unlockButton.MouseLeave:Connect(function()
    if unlockButton.Active then
        animate(unlockButton, 0.12, {
            BackgroundColor3 = C.Red,
        })
    end
end)

--==================================================
-- BOTTOM BUTTONS
--==================================================

local freeKeyButton = create("TextButton", {
    Name = "FreeAdKey",
    Position = UDim2.fromOffset(25, 185),
    Size = UDim2.new(0.5, -29, 0, 32),
    BackgroundColor3 = C.Background,
    BorderSizePixel = 0,
    Text = "Free ad key",
    TextColor3 = C.Muted,
    TextSize = 10,
    Font = FONT,
    AutoButtonColor = false,
}, content)

round(freeKeyButton, 5)
outline(freeKeyButton, C.Border, 1)

local premiumButton = create("TextButton", {
    Name = "BuyPremium",
    Position = UDim2.new(0.5, 4, 0, 185),
    Size = UDim2.new(0.5, -29, 0, 32),
    BackgroundColor3 = C.Background,
    BorderSizePixel = 0,
    Text = "Buy Premium",
    TextColor3 = C.Muted,
    TextSize = 10,
    Font = FONT,
    AutoButtonColor = false,
}, content)

round(premiumButton, 5)
outline(premiumButton, C.Border, 1)

local function setButtonHover(button, hovering)
    animate(button, 0.12, {
        TextColor3 = hovering and C.White or C.Muted,
        BackgroundColor3 = hovering and C.SurfaceHover or C.Background,
    })
end

freeKeyButton.MouseEnter:Connect(function()
    setButtonHover(freeKeyButton, true)
end)

freeKeyButton.MouseLeave:Connect(function()
    setButtonHover(freeKeyButton, false)
end)

premiumButton.MouseEnter:Connect(function()
    setButtonHover(premiumButton, true)
end)

premiumButton.MouseLeave:Connect(function()
    setButtonHover(premiumButton, false)
end)

--==================================================
-- WINDOW STATE / CLOSE ANIMATION
--==================================================

local closing = false
local busy = false

local function closeWindow()
    if closing then
        return
    end

    closing = true
    unlockButton.Active = false
    closeButton.Active = false

    animate(frame, 0.20, {
        Size = UDim2.fromOffset(WINDOW_WIDTH - 20, 0),
        BackgroundTransparency = 1,
    }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

    task.wait(0.22)

    if gui.Parent then
        gui:Destroy()
    end
end

closeButton.Activated:Connect(closeWindow)

--==================================================
-- DRAGGING
--==================================================

local dragging = false
local dragStart
local startPosition
local dragInput

-- Dedicated top drag region. The close button remains clickable.
local dragBar = create("TextButton", {
    Name = "DragBar",
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.new(1, 0, 0, 39),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    Active = true,
    ZIndex = 1,
}, content)

-- Ensure the labels and controls render above the drag region.
for _, object in ipairs(content:GetChildren()) do
    if object ~= dragBar then
        object.ZIndex = 2
    end
end

-- Keep input controls above the background and drag surface.
inputFrame.ZIndex = 3
keyBox.ZIndex = 4
unlockButton.ZIndex = 5
closeButton.ZIndex = 5
premiumLabel.ZIndex = 5

dragBar.InputBegan:Connect(function(input)
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

dragBar.InputChanged:Connect(function(input)
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

--==================================================
-- SERVER ERROR PARSING
--==================================================

local function decodeError(response)
    if type(response.Body) == "string" then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if ok and type(data) == "table" then
            return tostring(data.message or "License validation failed.")
        end
    end

    return "Server request failed."
end

local function resetButton()
    busy = false
    unlockButton.Active = true
    unlockButton.Text = "Unlock"
    unlockButton.BackgroundColor3 = C.Red
end

--==================================================
-- LICENSE VALIDATION
--==================================================

unlockButton.Activated:Connect(function()
    if busy or closing then
        return
    end

    local key = keyBox.Text:match("^%s*(.-)%s*$")

    if key == "" then
        setStatus("Please enter your key.", C.Error)
        animate(inputStroke, 0.12, {
            Color = C.Error,
        })
        return
    end

    busy = true
    unlockButton.Active = false
    unlockButton.Text = "Checking..."
    setStatus("Connecting to license server...", C.Muted)

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
        setStatus("Connection failed. Try again.", C.Error)
        resetButton()
        return
    end

    local statusCode = tonumber(response.StatusCode or response.Status)
    local body = response.Body

    if statusCode ~= 200 or type(body) ~= "string" then
        setStatus(decodeError(response), C.Error)
        resetButton()
        return
    end

    if body == "" then
        setStatus("Empty server response.", C.Error)
        resetButton()
        return
    end

    -- Handle JSON error responses returned with HTTP 200.
    local jsonOk, decoded = pcall(function()
        return HttpService:JSONDecode(body)
    end)

    if jsonOk and type(decoded) == "table" and decoded.ok == false then
        setStatus(decoded.message or "License rejected.", C.Error)
        resetButton()
        return
    end

    local compileOk, loadedFunction = pcall(function()
        return loadstring(body)
    end)

    if not compileOk or type(loadedFunction) ~= "function" then
        setStatus("Script compilation failed.", C.Error)
        resetButton()
        return
    end

    setStatus("Key accepted. Loading...", C.Success)

    closeWindow()

    local runOk, runError = pcall(loadedFunction)

    if not runOk then
        warn("[LOOT] Script execution error:", runError)
    end
end)

--==================================================
-- BUTTON PLACEHOLDERS
--==================================================

-- Replace these with your actual ad-key and premium URLs.
local canPress = true
local canPressPrem = true

freeKeyButton.Activated:Connect(function()
    if not closing and canPress then
        canPress = false
        if setclipboard then
            setclipboard("https://work.ink/37LB/loot-key-free-ad")
            freeKeyButton.Text = "Link copied!"
            task.wait(2)
            freeKeyButton.Text = "Free ad key"
        end
        canPress = true
    end
end)

premiumButton.Activated:Connect(function()
    if not closing then
        canPressPrem = false
        if setclipboard then
            setclipboard("https://ezlock.mykomerza.com/product/ezlock-lifetime")
            premiumButton.Text = "Link copied!"
            task.wait(2)
            premiumButton.Text = "Buy Platinum"
        end
        canPressPrem = true
    end
end)

premiumLabel.Activated:Connect(function()
    if not closing then
        setStatus("Ad-key / Premium links are not configured.", C.Muted)
    end
end)

--==================================================
-- ENTRANCE ANIMATION
--==================================================

frame.Size = UDim2.fromOffset(
    WINDOW_WIDTH - 25,
    WINDOW_HEIGHT - 15
)

frame.BackgroundTransparency = 1

animate(frame, 0.30, {
    Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
    BackgroundTransparency = 0,
}, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

print("[LOOT] License interface initialized.")
