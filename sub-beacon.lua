local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- *** UPDATE THIS LINK FROM CLOUDFLARE ***
local HUB_URL = "https://appropriations-supervisor-knight-luxury.trycloudflare.com"
-- ***************************************

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(5)
local http_request = syn and syn.request or http and http.request or http_request or fluxus and fluxus.request or request

task.spawn(function()
    while true do
        local payload = {
            userid = tostring(Players.LocalPlayer.UserId), 
            jobid = tostring(game.JobId), 
            role = "TARGET", 
            players = #Players:GetPlayers()
        }
        pcall(function() 
            http_request({
                Url = HUB_URL, 
                Method = "POST", 
                Headers = {["Content-Type"] = "application/json"}, 
                Body = HttpService:JSONEncode(payload)
            }) 
        end)
        task.wait(60) 
    end
end)
