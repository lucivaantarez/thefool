script_key="YrMGlHVZJYWpvtBaeKtZJOAtEBmcQbkQ";
setfpscap(10)

getgenv().sailorPieceConfig = {  
    KICK_ITEM_LIMIT = { ["Secret Chest"] = 99999999, ["Cosmetic Chest"] = 99999999, ["Aura Chest"] = 99999999 }
}

loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/d63b8de750f34c5a2bc6920f3849c318.lua"))()
