#!/bin/bash
clear
echo -e "\033[95m+===================================================+\033[0m"
echo -e "\033[95m|          T H E  F O O L ' S  C O U R T            |\033[0m"
echo -e "\033[95m+===================================================+\033[0m"
echo -e "\033[97m|  [1] Install MAIN HUB (The Command Center)        |\033[0m"
echo -e "\033[97m|  [2] Install SUB-HUB (The Swarm Worker)           |\033[0m"
echo -e "\033[95m+===================================================+\033[0m"
read -p "Select device role (1 or 2): " role

echo -e "\033[96m[SYSTEM] Cleaning environment and fixing .bashrc...\033[0m"
# This part kills all old, broken 'fool' or 'swarm' lines to prevent syntax errors
sed -i '/THE FOOL/d' ~/.bashrc
sed -i '/fool()/d' ~/.bashrc
sed -i '/alias swarm/d' ~/.bashrc
sed -i '/{/,/}/d' ~/.bashrc # Cleans up any leftover function brackets

pkg update -y -q && pkg install git python curl wget -y -q
pip install fastapi uvicorn pydantic -q

cd ~
if [ ! -d "thefool" ]; then
  echo -e "\033[96m[SYSTEM] Cloning repository from The Void...\033[0m"
  git clone https://github.com/lucivaantarez/thefool.git -q
fi

if [ "$role" == "1" ]; then
    echo -e "\033[95m[SYSTEM] Injecting MAIN HUB architecture...\033[0m"
    echo -e "\033[96m[SYSTEM] Installing Cloudflare Engine...\033[0m"
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -O cloudflared -q
    chmod +x cloudflared
    mv cloudflared /data/data/com.termux/files/usr/bin/
    
    # Using a safer injection method
    echo "# --- THE FOOL ---" >> ~/.bashrc
    echo "fool() {" >> ~/.bashrc
    echo "    cd ~/thefool" >> ~/.bashrc
    echo "    git fetch origin -q && git reset --hard origin/main -q" >> ~/.bashrc
    echo "    python hub.py" >> ~/.bashrc
    echo "}" >> ~/.bashrc
    
    echo -e "\033[96m[SYSTEM] Main Hub secured. Restart Termux or type 'source ~/.bashrc'.\033[0m"
elif [ "$role" == "2" ]; then
    echo -e "\033[95m[SYSTEM] Injecting SUB-HUB architecture...\033[0m"
    echo "alias swarm='cd ~/thefool && git pull origin main -q && termux-wake-lock && python subhub.py'" >> ~/.bashrc
    echo -e "\033[96m[SYSTEM] Sub-Hub secured. Type 'swarm' to arm the workers.\033[0m"
else
    echo -e "\033[31m[ERROR] Invalid selection. Aborting installation.\033[0m"
    exit 1
fi
