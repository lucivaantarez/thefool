# THE FOOL'S COURT | SYSTEM ARCHITECTURE V3.5
--------------------------------------------------
High-end automated infrastructure for multi-instance management.
Featuring Sentinel auto-relaunch, window bounds, and identity mapping.

### [1] SYSTEM INITIALIZATION
Run this command in Termux to install dependencies and pull the latest code.

curl -sL https://raw.githubusercontent.com/lucivaantarez/thefool/main/setup.sh | bash

--------------------------------------------------

### [2] EXTERNAL GATEWAY (CLOUDFLARE)
Run this in a SEPARATE Termux tab on your Master Redfinger. 
This provides the link for your Lua script.

cloudflared tunnel --url http://127.0.0.1:8000

--------------------------------------------------

### [3] OPERATIONAL DIRECTIVES
| Action                  | Command                                           |
|-------------------------|---------------------------------------------------|
| Awakening the Court     | fool                                              |
| Engaging the Swarm      | swarm                                             |
| Force Refresh Code      | cd ~/thefool && git pull                          |
| Clear All Environment   | rm -rf ~/thefool && fool                          |

--------------------------------------------------

### [4] WORKFLOW STRATEGY
1. MASTER: Launch 'fool' on the primary device.
2. ARCHITECT: Configure window layout (1x1/1x2) and search filter (com.lana).
3. AWAKEN: Press 'S' to deploy anchors and start the Sentinel watcher.
4. BRIDGE: Open the Cloudflare tunnel and copy the URL to 'homebase.lua'.
5. WORKERS: On sub-devices, launch 'swarm' to manage local instance health.

--------------------------------------------------
[ STATUS: READY ]
[ ARCHITECTURE: UNIFIED V3.5 ]
