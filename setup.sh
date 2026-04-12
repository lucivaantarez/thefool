#!/bin/bash
# THE FOOL'S COURT - UNIFIED INSTALLER V4.0
G='\033[1;32m'; C='\033[1;36m'; W='\033[1;37m'; R='\033[1;31m'; X='\033[0m'

clear
echo -e "${G}  ████████╗██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗"
echo -e "  ╚══██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║"
echo -e "     ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║"
echo -e "     ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║"
echo -e "     ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗"
echo -e "     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝${X}"
echo -e " ${W}[${X} ${G}SYSTEM: COURT_INITIALIZER_V4.0${X} ${W}]${X}\n"

echo -e " ${C}[1]${X} ${W}MAIN HUB (Master Redfinger)${X}"
echo -e " ${C}[2]${X} ${W}SWARM WORKER (Sub-Redfinger)${X}"
read -p " Select architecture: " role

echo -e "\n${G}[SYSTEM]${X} ${W}Arming environment...${X}"
pkg update -y -q
pkg install git python curl tur-repo -y -q
pkg install cloudflared -y -q

echo -e "${G}[SYSTEM]${X} ${W}Installing lightweight dependencies (Bypassing Rust)...${X}"
pip install "pydantic<2" "fastapi<0.100" uvicorn requests -q

echo -e "${G}[SYSTEM]${X} ${W}Synchronizing with The Fool's Court...${X}"
cd ~
rm -rf thefool
git clone https://github.com/lucivaantarez/thefool.git -q

# Clean up old aliases to prevent duplicates
sed -i '/alias fool=/d' ~/.bashrc
sed -i '/alias swarm=/d' ~/.bashrc

if [ "$role" == "1" ]; then
    echo "alias fool='cd ~/thefool && git pull origin main -q && python hub.py'" >> ~/.bashrc
    echo -e "${G}[SUCCESS]${X} ${W}Main Hub secured. Type 'source ~/.bashrc' then 'fool' to awaken.${X}"
else
    echo "alias swarm='cd ~/thefool && git pull origin main -q && python subhub.py'" >> ~/.bashrc
    echo -e "${G}[SUCCESS]${X} ${W}Swarm Node secured. Type 'source ~/.bashrc' then 'swarm' to engage.${X}"
fi

cloudflared --version
