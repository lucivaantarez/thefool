-- THE FOOL'S COURT: UNIVERSAL BEACON V3.5
-- ARCHITECTURE: PACKAGE-AGNOSTIC IDENTITY MAPPING

local HUB_URL = "https://your-master-hub.trycloudflare.com" -- Paste your Cloudflare link here
local LOCAL_HUB = "http://127.0.0.1:5000" -- Local Swarm Worker (No tunnel needed)

local HttpService = game:GetService("HttpService")
local Player = game.Players.LocalPlayer

local function sendPing()
    local data = {
        userid = tostring(Player.UserId),
        jobid = game.JobId,
        role = "ANCHOR" -- Master Hub identifies the package automatically
    }
    
    local encodedData = HttpService:JSONEncode(data)

    -- [1] SIGNAL MASTER HUB (Remote Mission Control)
    pcall(function()
        HttpService:PostAsync(HUB_URL .. "/api/ping", encodedData)
    end)

    -- [2] SIGNAL LOCAL GUARD (Prevents local Swarm reboots)
    pcall(function()
        HttpService:GetAsync(LOCAL_HUB .. "/local_ping?hopper_id=" .. data.jobid)
    end)
end

-- Engaging Heartbeat (30s interval)
task.spawn(function()
    while true do
        sendPing()
        task.wait(30)
    end
end)
