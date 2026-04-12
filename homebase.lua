-- LANA UNIVERSAL ANCHOR BEACON V3.5
local HttpService = game:GetService("HttpService")
local Player = game.Players.LocalPlayer

local function sendPing()
    local data = {
        userid = tostring(Player.UserId),
        jobid = game.JobId,
        role = "ANCHOR" -- Hub maps the package automatically
    }
    
    pcall(function()
        HttpService:PostAsync("http://YOUR_CLOUDFLARE_URL/api/ping", HttpService:JSONEncode(data))
        -- If on Swarm Node, also ping local
        HttpService:GetAsync("http://127.0.0.1:5000/local_ping?hopper_id=" .. data.jobid)
    end)
end

spawn(function()
    while task.wait(30) do
        sendPing()
    end
end)
