#!/bin/bash
# THE FOOL'S COURT - UNIFIED INSTALLER V3.6 (STABLE BINARY)
G='\033[1;32m'; C='\033[1;36m'; W='\033[1;37m'; R='\033[1;31m'; X='\033[0m'

clear
echo -e "${G}  ████████╗██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗"
echo -e "  ╚══██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║"
echo -e "     ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║"
echo -e "     ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║"
echo -e "     ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗"
echo -e "     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝${X}"
echo -e " ${W}[{X} {G}SYSTEM: COURT_INITIALIZER_V3.6${X} {W}]${X}\n"

echo -e " ${C}[1]${X} ${W}MAIN HUB (Command Center)${X}"
echo -e " ${C}[2]${X} ${W}SWARM WORKER (Swarm Node)${X}"
read -p " Select architecture: " role

echo -e "\n${G}[SYSTEM]${X} ${W}Arming environment...${X}"
pkg update -y -q
pkg install git python curl wget -y -q
pip install fastapi uvicorn pydantic requests -q

# --- THE CRITICAL FIX: Direct Cloudflare Binary Injection ---
echo -e "${G}[SYSTEM]${X} ${W}Injecting stable Cloudflare binary...${X}"
rm -f $PREFIX/bin/cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
chmod +x cloudflared-linux-arm64
mv cloudflared-linux-arm64 $PREFIX/bin/cloudflared

cd ~
rm -rf thefool
git clone https://github.com/lucivaantarez/thefool.git -q

if [ "$role" == "1" ]; then
    # Create alias for Master Hub
    echo "alias fool='cd ~/thefool && git pull origin main -q && python hub.py'" >> ~/.bashrc
    echo -e "${G}[SUCCESS]${X} ${W}Main Hub secured. Type 'fool' to awaken.${X}"
else
    # Create alias for Swarm Worker
    echo "alias swarm='cd ~/thefool && git pull origin main -q && python subhub.py'" >> ~/.bashrc
    echo -e "${G}[SUCCESS]${X} ${W}Swarm Node secured. Type 'swarm' to engage.${X}"
fi

# Refresh environment
source ~/.bashrc
cloudflared --version
