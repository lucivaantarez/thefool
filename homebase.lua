local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local NGROK_URL = "https://YOUR-URL.trycloudflare.com/api/ping"
local MY_ROLE = "PRIMARY" -- Change to SECONDARY for 2nd anchor

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(5)
local http_request = syn and syn.request or http and http.request or http_request or fluxus and fluxus.request or request

task.spawn(function()
    while true do
        local payload = {userid = tostring(Players.LocalPlayer.UserId), jobid = tostring(game.JobId), role = MY_ROLE, players = #Players:GetPlayers()}
        pcall(function() http_request({Url = NGROK_URL, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload)}) end)
        task.wait(60)
    end
end)
