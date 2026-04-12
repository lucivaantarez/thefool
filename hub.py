import os, sys, json, time, sqlite3, threading
from collections import deque
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
import logging

logging.getLogger("uvicorn").setLevel(logging.CRITICAL)
logging.getLogger("uvicorn.access").setLevel(logging.CRITICAL)

app = FastAPI()
CONFIG_FILE = "config.json"
DB_FILE = "swarm.db"

config = {
    "target_timer": 300, 
    "base_timer": 1800, 
    "army_per_device": 2, 
    "primary_base": "https://www.roblox.com/share?code=...", 
    "secondary_base": "None"
}

if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, "r") as f: config.update(json.load(f))
else:
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

def save_config():
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

conn = sqlite3.connect(DB_FILE, check_same_thread=False)
cursor = conn.cursor()
cursor.executescript("""
    CREATE TABLE IF NOT EXISTS targets (userid TEXT PRIMARY KEY, jobid TEXT, last_seen REAL);
    CREATE TABLE IF NOT EXISTS anchors (role TEXT PRIMARY KEY, jobid TEXT, players INTEGER);
    CREATE TABLE IF NOT EXISTS hoppers (userid TEXT PRIMARY KEY, assigned_jobid TEXT, mission TEXT);
""")
conn.commit()

comm_log = deque(maxlen=10)
def add_log(msg): comm_log.append(msg)

start_time = time.time()
PURPLE, WHITE, CYAN, RED, RESET = '\033[95m', '\033[97m', '\033[96m', '\033[91m', '\033[0m'

class PingData(BaseModel):
    userid: str
    jobid: str
    role: str
    players: int = 0

@app.post("/api/ping")
def handle_ping(data: PingData):
    now = time.time()
    if data.role in ["PRIMARY", "SECONDARY"]:
        cursor.execute("REPLACE INTO anchors (role, jobid, players) VALUES (?, ?, ?)", (data.role, data.jobid, data.players))
    elif data.role == "TARGET":
        cursor.execute("REPLACE INTO targets (userid, jobid, last_seen) VALUES (?, ?, ?)", (data.userid, data.jobid, now))
    conn.commit()
    return {"status": "Logged"}

@app.get("/api/mission")
def get_mission(userid: str, current_jobid: str):
    cursor.execute("SELECT userid, jobid FROM targets ORDER BY last_seen ASC LIMIT 1")
    target = cursor.fetchone()
    short_user = userid[:6]
    if target:
        add_log(f"> Hopper_{short_user} : Hunting in Server [{target[1][:8]}]")
        return {"action": "EXECUTE", "mission": "HUNT", "target_userid": target[0], "dwell_time": config["target_timer"]}
    else:
        add_log(f"> Hopper_{short_user} : Resting at Homebase.")
        return {"action": "EXECUTE", "mission": "REST", "target_userid": "null", "dwell_time": config["base_timer"]}

def clear_screen(): os.system('clear')

def draw_static_menu():
    clear_screen()
    print(PURPLE + "+===================================================+\n|                                                   |\n|          T H E  F O O L ' S  C O U R T            |\n|                                                   |\n+===================================================+" + RESET)
    print(WHITE + f"|  SYSTEM STATUS          :  {CYAN}[ OFFLINE ]{WHITE}            |\n+---------------------------------------------------+")
    print(f"|  [1] The Fool's Hop     :  {config['target_timer']} seconds")
    print(f"|  [2] Fool's Rest Time   :  {config['base_timer']} seconds")
    print(f"|  [3] Army/Device        :  {config['army_per_device']}")
    print(f"|  [4] Primary Homebase   :  {config['primary_base'][:20]}...")
    print(f"|  [5] Secondary Homebase :  {config['secondary_base'][:20]}...")
    print(PURPLE + "+===================================================+" + RESET)
    print(WHITE + "|  [E] Configuration                                |\n|  [S] Awaken The Fool                              |\n|  [Q] Kill The Fool                                |\n" + PURPLE + "+---------------------------------------------------+" + RESET)

def interactive_menu():
    while True:
        draw_static_menu()
        choice = input(WHITE + "Select an action: " + RESET).strip().upper()
        if choice == 'Q': sys.exit(0)
        elif choice == 'S': break 
        elif choice == 'E':
            opt = input(CYAN + "Which setting to edit (1-5)? " + RESET)
            if opt == '1': config['target_timer'] = int(input("New Hop Time (seconds): "))
            if opt == '2': config['base_timer'] = int(input("New Rest Time (seconds): "))
            if opt == '3': config['army_per_device'] = int(input("New Army/Device: "))
            if opt == '4': config['primary_base'] = input("New Primary Base Link: ").strip()
            if opt == '5': config['secondary_base'] = input("New Secondary Base Link: ").strip()
            save_config()

def get_uptime():
    h, rem = divmod(int(time.time() - start_time), 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}h {m:02d}m {s:02d}s"

def draw_live_dashboard():
    while True:
        time.sleep(1)
        clear_screen()
        cursor.execute("SELECT COUNT(*) FROM targets")
        active_universe = cursor.fetchone()[0]
        print(PURPLE + "+===================================================+\n|                                                   |\n|          T H E  F O O L ' S  C O U R T            |\n|                                                   |\n+===================================================+" + RESET)
        print(WHITE + f"|  SYSTEM STATUS          :  {CYAN}[ AWAKENED ]{WHITE}           |\n|  NETWORK UPTIME         :  {CYAN}{get_uptime():<21}{WHITE}|\n|  ACTIVE UNIVERSE        :  {CYAN}{active_universe:<4} TARGETS{WHITE}          |\n" + PURPLE + "+---------------------------------------------------+" + RESET)
        print(WHITE + "|  [ LIVE COMM LINK ] (Last 10 Events)              |")
        log_list = list(comm_log)
        for i in range(10): print(f"| {log_list[i][:45]:<49} |" if i < len(log_list) else f"| {' ':<49} |")
        print(PURPLE + "+===================================================+" + RESET)
        print(WHITE + "Type " + CYAN + "'s'" + WHITE + " and press [ENTER] to Kill The Fool." + RESET)

def listen_for_kill():
    while True:
        if input().strip().lower() == 's':
            print(RED + "\n[SYSTEM] Assassinating the Hub. Saving Data..." + RESET)
            os._exit(0)

if __name__ == "__main__":
    interactive_menu()
    clear_screen()
    print(PURPLE + "[SYSTEM] Opening the Void... Awaken The Fool." + RESET)
    
    if config.get("primary_base") and config["primary_base"] != "None":
        os.system(f'am start -a android.intent.action.VIEW -d "{config["primary_base"]}" com.roblox.client > /dev/null 2>&1')
        time.sleep(3) 
        
    if config.get("secondary_base") and config["secondary_base"] != "None":
        os.system(f'am start -a android.intent.action.VIEW -d "{config["secondary_base"]}" com.dualspace.roblox > /dev/null 2>&1')

    threading.Thread(target=draw_live_dashboard, daemon=True).start()
    threading.Thread(target=listen_for_kill, daemon=True).start()
    uvicorn.run(app, host="0.0.0.0", port=8000)
