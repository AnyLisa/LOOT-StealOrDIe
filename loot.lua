
-- StealOrDie License Loader

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local API_URL = "https://asedaskolannyheter.pythonanywhere.com"
local ENDPOINT = API_URL .. "/api/roblox/steal-or-die"

local player = Players.LocalPlayer

if not player then
    warn("[StealOrDie] Could not identify the local player.")
    return
end

local httpRequest =
    (syn and syn.request)
    or (http and http.request)
    or request
    or http_request

if type(httpRequest) ~= "function" then
    warn("[StealOrDie] Your executor does not support HTTP requests.")
    return
end

local function createInstance(className, properties, parent)
    local instance = Instance.new(className)

    for property, value in pairs(properties) do
        instance[property] = value
    end

    instance.Parent = parent
    return instance
end

local oldGui = CoreGui:FindFirstChild("StealOrDieKeySystem")
if oldGui then
    oldGui:Destroy()
end

local gui = createInstance("ScreenGui", {
    Name = "StealOrDieKeySystem",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, CoreGui)

local frame = createInstance("Frame", {
    Size = UDim2.fromOffset(360, 205),
    Position = UDim2.new(0.5, -180, 0.5, -102),
    BackgroundColor3 = Color3.fromRGB(15, 18, 28),
    BorderSizePixel = 0
}, gui)

createInstance("UICorner", {
    CornerRadius = UDim.new(0, 10)
}, frame)

createInstance("TextLabel", {
    Size = UDim2.new(1, -24, 0, 38),
    Position = UDim2.fromOffset(12, 10),
    BackgroundTransparency = 1,
    Text = "StealOrDie",
    TextColor3 = Color3.fromRGB(255, 255, 255),
    TextSize = 22,
    Font = Enum.Font.GothamBold
}, frame)

local keyBox = createInstance("TextBox", {
    Size = UDim2.new(1, -32, 0, 42),
    Position = UDim2.fromOffset(16, 55),
    BackgroundColor3 = Color3.fromRGB(30, 35, 49),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    PlaceholderColor3 = Color3.fromRGB(155, 160, 175),
    PlaceholderText = "Enter your license key",
    Text = "",
    TextSize = 14,
    Font = Enum.Font.Gotham,
    ClearTextOnFocus = false
}, frame)

createInstance("UICorner", {
    CornerRadius = UDim.new(0, 6)
}, keyBox)

local submit = createInstance("TextButton", {
    Size = UDim2.new(1, -32, 0, 38),
    Position = UDim2.fromOffset(16, 107),
    BackgroundColor3 = Color3.fromRGB(55, 105, 220),
    TextColor3 = Color3.fromRGB(255, 255, 255),
    Text = "Verify Key",
    TextSize = 14,
    Font = Enum.Font.GothamBold
}, frame)

createInstance("UICorner", {
    CornerRadius = UDim.new(0, 6)
}, submit)

local status = createInstance("TextLabel", {
    Size = UDim2.new(1, -32, 0, 34),
    Position = UDim2.fromOffset(16, 155),
    BackgroundTransparency = 1,
    Text = "Enter your key to continue.",
    TextColor3 = Color3.fromRGB(185, 190, 205),
    TextSize = 12,
    Font = Enum.Font.Gotham,
    TextWrapped = true
}, frame)

local busy = false

local function setStatus(message, color)
    status.Text = message
    status.TextColor3 = color or Color3.fromRGB(185, 190, 205)
end

local function decodeError(response)
    if type(response.Body) == "string" then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if ok and type(data) == "table" then
            return data.message or "Key validation failed."
        end
    end

    return "Server request failed."
end

submit.Activated:Connect(function()
    if busy then
        return
    end

    local key = keyBox.Text:match("^%s*(.-)%s*$")

    if key == "" then
        setStatus("Please enter your license key.", Color3.fromRGB(255, 100, 100))
        return
    end

    busy = true
    submit.Text = "Verifying..."
    setStatus("Contacting license server...")

    local requestOk, response = pcall(function()
        return httpRequest({
            Url = ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode({
                key = key,
                roblox_user_id = tostring(player.UserId)
            })
        })
    end)

    if not requestOk or type(response) ~= "table" then
        setStatus("Could not connect to the server.", Color3.fromRGB(255, 100, 100))
        busy = false
        submit.Text = "Verify Key"
        return
    end

    local statusCode = tonumber(response.StatusCode or response.Status)

    if statusCode ~= 200 or type(response.Body) ~= "string" then
        setStatus(decodeError(response), Color3.fromRGB(255, 100, 100))
        busy = false
        submit.Text = "Verify Key"
        return
    end

    local compileOk, loadedFunction = pcall(function()
        return loadstring(response.Body)
    end)

    if not compileOk or type(loadedFunction) ~= "function" then
        setStatus("The downloaded script could not be compiled.", Color3.fromRGB(255, 100, 100))
        busy = false
        submit.Text = "Verify Key"
        return
    end

    gui:Destroy()

    local runOk, runError = pcall(loadedFunction)

    if not runOk then
        warn("[StealOrDie] Execution error:", runError)
    end
end)
