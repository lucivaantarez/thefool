# 🃏 The Fool's Court: C2 Architecture

An elite Command & Control (C2) architecture designed to manage a limitless swarm of automated Roblox clients. Powered by Python, FastAPI, and SQLite, with a secure bridge via Ngrok.

## ⚙️ Core Architecture
* **The Master Hub (`hub.py`):** The central brain. Tracks server JobIds, manages cooldowns, enforces a 3-minute healing Grace Period, and actively garbage-collects dead endpoints.
* **The Monitor (`monitor.py`):** A lightweight, read-only terminal dashboard for remote viewing.
* **The Hunter (`hunter.lua`):** The primary execution bot that receives the target `JobId` and executes trades.
* **The Swarm (`beacon.lua`):** Zero-UI, lightweight background scripts that securely report live `JobId` data to the Master Hub every 60 seconds.

## 🚀 Ignition Sequence

### 1. The Brain (Redfinger Cloud Phone)
Run this block in Termux to install the Hub and create the `fool` command. 
*Note: Type `fool` to launch the Hub. It will automatically update from GitHub, lock the wakestate, and launch the Ngrok tunnel silently.*

```bash
pkg update && pkg install git ngrok -y
git clone [https://github.com/lucivaantarez/thefool.git](https://github.com/lucivaantarez/thefool.git) ~/thefool
echo "alias fool='cd ~/thefool && git pull origin main && termux-wake-lock && nohup ngrok http --domain=intersectant-unaffrightedly-somer.ngrok-free.dev 8000 > /dev/null 2>&1 & python hub.py'" >> ~/.bashrc
source ~/.bashrc
