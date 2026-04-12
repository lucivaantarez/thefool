local HUB_URL = "https://your-master-hub.trycloudflare.com" 
local LOCAL_HUB = "http://127.0.0.1:5000" 

local HttpService = game:GetService("HttpService")
local Player = game.Players.LocalPlayer

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

task.spawn(function()
    while true do
        sendPing()
        task.wait(30)
    end
end)
