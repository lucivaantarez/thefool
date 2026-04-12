local HUB_URL = "https://neo-roommate-apparatus-chicken.trycloudflare.com" 

local HttpService = game:GetService("HttpService")
local Player = game.Players.LocalPlayer

-- [ The Luxury Bypass: Uses Executor-level HTTP to break out of Roblox ]
local fetch = request or http_request or (http and http.request)

local function sendPing()
    local data = {
        userid = tostring(Player.UserId),
        jobid = game.JobId,
        role = "ANCHOR"
    }
    local encodedData = HttpService:JSONEncode(data)

    if fetch then
        -- Uses the executor's secret network
        pcall(function()
            fetch({
                Url = HUB_URL .. "/api/ping",
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = encodedData
            })
        end)
    else
        -- Fallback if bypass is missing
        pcall(function() HttpService:PostAsync(HUB_URL .. "/api/ping", encodedData) end)
    end
end

-- [ The Heartbeat Loop ]
task.spawn(function()
    while true do
        sendPing()
        task.wait(30) -- Keeps the Sentinel happy every 30 seconds
    end
end)
