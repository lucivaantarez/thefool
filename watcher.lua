local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

-- *** UPDATE THIS LINK FROM CLOUDFLARE ***
local HUB_URL = "https://YOUR-URL.trycloudflare.com/api/mission"
local SUB_HUB_URL = "http://127.0.0.1:5000/local_ping"
-- ***************************************

local MY_ID = tostring(Players.LocalPlayer.UserId)
local CURRENT_JOB = tostring(game.JobId)
local PLACE_ID = game.PlaceId

task.spawn(function()
    while true do
        pcall(function() game:HttpGet(SUB_HUB_URL .. "?hopper_id=" .. MY_ID) end)
        task.wait(30)
    end
end)

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(5)

local requestUrl = HUB_URL .. "?userid=" .. MY_ID .. "&current_jobid=" .. CURRENT_JOB
local success, response = pcall(function() return game:HttpGet(requestUrl) end)

if not success then
    task.wait(10)
    TeleportService:TeleportToPlaceInstance(PLACE_ID, CURRENT_JOB, Players.LocalPlayer)
    return
end

local orders = HttpService:JSONDecode(response)

if orders.action == "TELEPORT" then
    TeleportService:TeleportToPlaceInstance(PLACE_ID, orders.jobid, Players.LocalPlayer)
    return
end

if orders.mission == "REST" then
    task.wait(orders.dwell_time)
    TeleportService:TeleportToPlaceInstance(PLACE_ID, CURRENT_JOB, Players.LocalPlayer)
    return
end

if orders.mission == "HUNT" then
    task.wait(10) 
    local targetFound = false
    for _, player in pairs(Players:GetPlayers()) do
        if tostring(player.UserId) == tostring(orders.target_userid) then targetFound = true break end
    end
    
    if not targetFound then
        TeleportService:TeleportToPlaceInstance(PLACE_ID, CURRENT_JOB, Players.LocalPlayer)
        return
    end
    
    task.wait(orders.dwell_time)
    TeleportService:TeleportToPlaceInstance(PLACE_ID, CURRENT_JOB, Players.LocalPlayer)
end
