script_key="YrMGlHVZJYWpvtBaeKtZJOAtEBmcQbkQ";
setfpscap(10)

getgenv().sailorPieceConfig = {  
    OPTIMIZATION = false, 
    AUTO_KICK = false,
    TRADE_USERNAME = { "aduhhhbrisik" },
    TRADE_ITEM = {
        "Abyss Sigil",
        "Aura Crate",
        "Battle Shard",
        "Battle Sigil",
        "Boss Key",
        "Boss Rush Ticket",
        "Boss Ticket",
        "Broken Sword",
        "Clan Reroll",
        "Cosmetic Crate",
        "Dark Grail",
        "Divine Grail",
        "Dungeon Key",
        "Dungeon Ticket",
        "Frost Brand",
        "Frost Relic",
        "Frozen Brand",
        "Frozen Will",
        "Fusion Ring",
        "Glacier Remnant",
        "Ice Core",
        "Mythical Chest",
        "Passive Shard",
        "Power Shard",
        "Race Reroll",
        "Rush Key",
        "Secret Chest",
        "Tempest Relic",
        "Tower Key",
        "Trait Reroll",
        "Upper Seal",
    },

    WEBHOOK_URL = "https://discord.com/api/webhooks/1481617340247576729/oNNhsQuK_3MoXArfADV6fv5_xk4nIuxMWPCarj5c-_fw6nav2BtOM60xh5232tegePUm",
    DISCORD_ID = "285071154300059648",
    WEBHOOK_NOTE = "",
    SHOW_WEBHOOK_USERNAME = true,
    SHOW_WEBHOOK_JOBID = true,
}

loadstring(game:HttpGet("https://api.luarmor.net/files/v4/loaders/eb9a467b35fe098d20677eb16ec559a4.lua"))()
