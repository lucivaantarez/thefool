local HUB_URL = "https://appropriations-supervisor-knight-luxury.trycloudflare.com" 
local LOCAL_HUB = "http://127.0.0.1:5000" 

local HttpService = game:GetService("HttpService")
local Player = game.Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")

local function sendPing()
    local data = {
        userid = tostring(Player.UserId),
        jobid = game.JobId,
        role = "ANCHOR"
    }
    local encodedData = HttpService:JSONEncode(data)

    pcall(function() HttpService:PostAsync(HUB_URL .. "/api/ping", encodedData) end)
    pcall(function() HttpService:GetAsync(LOCAL_HUB .. "/local_ping?hopper_id=" .. data.jobid) end)
end

local function fetchOrders()
    local success, response = pcall(function()
        return HttpService:GetAsync(HUB_URL .. "/api/mission?userid=" .. tostring(Player.UserId))
    end)
    if success then
        local orders = HttpService:JSONDecode(response)
        if orders.action == "EXECUTE" and orders.mission == "HUNT" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, orders.target_jobid, Player)
        end
    end
end

task.spawn(function()
    while true do
        sendPing()
        fetchOrders()
        task.wait(30)
    end
end)
