# LANA SYSTEM ARCHITECTURE: THE FOOL'S COURT V3.5
--------------------------------------------------
A centralized command suite for automated Roblox infrastructure, 
featuring Sentinel auto-relaunch, dynamic window bounds (1x1/1x2), 
and package-agnostic identity mapping.

### [1] INITIALIZATION (THE INJECTOR)
Run this command in a fresh Termux session to install dependencies 
and pull the latest unified codebase.

curl -sL https://raw.githubusercontent.com/lucivaantarez/thefool/main/setup.sh | bash

--------------------------------------------------

### [2] PUBLIC ACCESS (CLOUDFLARE TUNNEL)
Run this in a SEPARATE Termux tab while the Hub or Swarm is active.
Copy the ".trycloudflare.com" link generated to your Lua scripts.

# For Master Hub (Master Redfinger)
cloudflared tunnel --url http://127.0.0.1:8000

# For Swarm Worker (Sub-Redfinger)
cloudflared tunnel --url http://127.0.0.1:5000

--------------------------------------------------

### [3] COMMAND REFERENCE
| Action                  | Command                                           |
|-------------------------|---------------------------------------------------|
| Awakening the Court     | fool                                              |
| Engaging the Swarm      | swarm                                             |
| Force Refresh Code      | cd ~/thefool && git pull                          |
| Clean Re-Install        | rm -rf ~/thefool && fool                          |
| Install Cloudflared     | pkg install cloudflared                           |

--------------------------------------------------

### [4] LUA INTEGRATION
Paste your Cloudflare URL into the universal beacon script inside 
your Roblox executor.

local HUB_URL = "https://your-unique-link.trycloudflare.com"

--------------------------------------------------

### [5] OPERATIONAL WORKFLOW
1. DIRECTIVE: Launch 'fool' on your Master Hub. 
2. ARCHITECT: Set Window Layout (1x1/1x2) and search filter (com.lana).
3. AWAKEN: Press 'S' to deploy the swarm and start the Sentinel watcher.
4. BRIDGE: Start the Cloudflare tunnel in Tab 2 to link your Roblox accounts.
5. MONITOR: Watch 'LANA LIVE INTERCEPT' for real-time mission updates.

--------------------------------------------------
[ SYSTEM STATUS: READY ]
[ ARCHITECTURE: UNIFIED V3.5 ]
