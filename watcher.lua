-- THE FOOL'S COURT: WATCHER V3.6
-- MISSION: TARGET INTERCEPTION & LOCAL GUARD

local HUB_URL = "https://appropriations-supervisor-knight-luxury.trycloudflare.com" -- CLOUDFLARE LINK
local LOCAL_GUARD = "http://127.0.0.1:5000/local_ping" -- NO TUNNEL NEEDED

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local MY_ID = tostring(Players.LocalPlayer.UserId)
local CURRENT_JOB = tostring(game.JobId)
local PLACE_ID = game.PlaceId

-- [1] THE LOCAL HEARTBEAT (Prevents Sentinel Relaunch)
task.spawn(function()
    while true do
        pcall(function()
            HttpService:GetAsync(LOCAL_GUARD .. "?hopper_id=" .. MY_ID)
        end)
        task.wait(30)
    end
end)

-- [2] MISSION EXECUTION
local function fetchOrders()
    local success, response = pcall(function()
        return HttpService:GetAsync(HUB_URL .. "/api/mission?userid=" .. MY_ID)
    end)

    if not success then return end
    local orders = HttpService:JSONDecode(response)

    if orders.action == "EXECUTE" then
        if orders.mission == "HUNT" then
            -- HUNT LOGIC: Jump to the target's server
            TeleportService:TeleportToPlaceInstance(PLACE_ID, orders.target_jobid, Players.LocalPlayer)
        elseif orders.mission == "REST" then
            -- REST LOGIC: Stay or go to Homebase
            print("LANA: Resting the Fool.")
        end
    end
end

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(5)

while true do
    fetchOrders()
    task.wait(60) -- Checks for new missions every minute
end
