local HUB_URL = "https://neo-roommate-apparatus-chicken.trycloudflare.com" -- Put your actual link here

local HttpService = game:GetService("HttpService")
local Player = game.Players.LocalPlayer
local fetch = request or http_request or (http and http.request)

task.spawn(function()
    while true do
        local data = {
            userid = tostring(Player.UserId),
            jobid = game.JobId,
            role = "ANCHOR"
        }
        local encoded = HttpService:JSONEncode(data)

        if fetch then
            pcall(function() 
                fetch({
                    Url = HUB_URL .. "/api/ping", 
                    Method = "POST", 
                    Headers = {["Content-Type"] = "application/json"}, 
                    Body = encoded
                }) 
            end)
        end
        task.wait(30)
    end
end)
