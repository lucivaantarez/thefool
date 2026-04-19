script_key="YrMGlHVZJYWpvtBaeKtZJOAtEBmcQbkQ";
setfpscap(10)

getgenv().sailorPieceConfig = {  
    KICK_ITEM_LIMIT = { ["Secret Chest"] = 9999, ["Cosmetic Chest"] = 9999, ["Aura Chest"] = 9999, ["Clan Reroll"] = 1999999, ["Trait Reroll"] = 4999999, ["Race Reroll"] = 4999999 },
}

loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/d63b8de750f34c5a2bc6920f3849c318.lua"))()
