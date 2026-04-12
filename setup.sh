#!/bin/bash
clear
echo -e "\033[95m+===================================================+\033[0m"
echo -e "\033[95m|          T H E  F O O L ' S  C O U R T            |\033[0m"
echo -e "\033[95m+===================================================+\033[0m"
echo -e "\033[97m|  [1] Install MAIN HUB (The Command Center)        |\033[0m"
echo -e "\033[97m|  [2] Install SUB-HUB (The Swarm Worker)           |\033[0m"
echo -e "\033[95m+===================================================+\033[0m"
read -p "Select device role (1 or 2): " role

echo -e "\033[96m[SYSTEM] Installing core Android dependencies...\033[0m"
pkg update -y -q && pkg install git python curl wget -y -q
pip install fastapi uvicorn pydantic -q

cd ~
if [ ! -d "thefool" ]; then
  echo -e "\033[96m[SYSTEM] Cloning repository from The Void...\033[0m"
  git clone https://github.com/lucivaantarez/thefool.git -q
fi

sed -i '/THE FOOL/d' ~/.bashrc
sed -i '/fool()/d' ~/.bashrc
sed -i '/alias swarm/d' ~/.bashrc

if [ "$role" == "1" ]; then
    echo -e "\033[95m[SYSTEM] Injecting MAIN HUB architecture...\033[0m"
    echo -e "\033[96m[SYSTEM] Installing Cloudflare Engine...\033[0m"
    wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 -O cloudflared -q
    chmod +x cloudflared
    mv cloudflared /data/data/com.termux/files/usr/bin/
    
    cat << 'EOF' >> ~/.bashrc
# --- THE FOOL ---
fool() {
    cd ~/thefool
    echo -e "\033[95m[SYSTEM] Syncing with The Void...\033[0m"
    git fetch origin -q
    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse origin/main 2>/dev/null)
    if [ "$LOCAL" != "$REMOTE" ]; then
        echo -e "\033[96m[UPDATE] New Directive Detected. Rebuilding...\033[0m"
        cp config.json config_backup.json 2>/dev/null
        cp swarm.db swarm_backup.db 2>/dev/null
        git reset --hard origin/main -q
        mv config_backup.json config.json 2>/dev/null
        mv swarm_backup.db swarm.db 2>/dev/null
        echo -e "\033[96m[UPDATE] Architecture Secured.\033[0m"
        sleep 1
    fi
    python hub.py
}
EOF
    echo -e "\033[96m[SYSTEM] Main Hub secured. Type 'fool' to Awaken.\033[0m"
elif [ "$role" == "2" ]; then
    echo -e "\033[95m[SYSTEM] Injecting SUB-HUB architecture...\033[0m"
    cat << 'EOF' >> ~/.bashrc
# --- THE FOOL ---
alias swarm='cd ~/thefool && git pull origin main -q && termux-wake-lock && python subhub.py'
EOF
    echo -e "\033[96m[SYSTEM] Sub-Hub secured. Type 'swarm' to arm the workers.\033[0m"
else
    echo -e "\033[31m[ERROR] Invalid selection. Aborting installation.\033[0m"
    exit 1
fi
