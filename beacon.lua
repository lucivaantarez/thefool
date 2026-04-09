-- ==========================================
-- THE FOOL'S COURT: BEACON SCRIPT
-- ==========================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Your permanent Ngrok Hub URL
local HUB_URL = "https://intersectant-unaffrightedly-somer.ngrok-free.dev/api/ping"

-- Change this to match the API key you create in Termux!
local API_KEY = "foolthefools"

local function sendPing()
    local payload = {
        userid = tostring(LocalPlayer.UserId),
        jobid = tostring(game.JobId)
    }
    
    local jsonData = HttpService:JSONEncode(payload)
    
    local requestParams = {
        Url = HUB_URL,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. API_KEY
        },
        Body = jsonData
    }
    
    -- Fire and forget using pcall. If your Hub is paused or rebooting, 
    -- this prevents the Roblox client from crashing or throwing errors.
    pcall(function()
        request(requestParams)
    end)
end

-- Send the first ping immediately upon joining the server
sendPing()

-- Ping the Master Hub every 60 seconds to prove the account is alive
while true do
    task.wait(60)
    sendPing()
end
