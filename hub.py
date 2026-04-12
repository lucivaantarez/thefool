import os, sys, json, time, sqlite3, threading
from collections import deque
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
import logging

# Silence logs
logging.getLogger("uvicorn").setLevel(logging.CRITICAL)
logging.getLogger("uvicorn.access").setLevel(logging.CRITICAL)

app = FastAPI()
CONFIG_FILE = "config.json"
DB_FILE = "swarm.db"

# High-Contrast Palette
G, C, W, R, Y, X = '\033[1;32m', '\033[1;36m', '\033[1;37m', '\033[1;31m', '\033[1;33m', '\033[0m'

config = {
    "target_timer": 300, 
    "base_timer": 1800, 
    "primary_base": "None", 
    "search_filter": "com.lana", # Changed from com.imam/com.roblox
    "active_pkgs": ["com.roblox.client"]
}

if os.path.exists(CONFIG_FILE):
    try:
        with open(CONFIG_FILE, "r") as f: config.update(json.load(f))
    except: pass
else:
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

def save_config():
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

conn = sqlite3.connect(DB_FILE, check_same_thread=False)
cursor = conn.cursor()
cursor.executescript("CREATE TABLE IF NOT EXISTS targets (userid TEXT PRIMARY KEY, jobid TEXT, last_seen REAL);")
conn.commit()

comm_log = deque(maxlen=8)
def add_log(msg): comm_log.append(msg)
start_time = time.time()

class PingData(BaseModel):
    userid: str
    jobid: str
    role: str

@app.post("/api/ping")
def handle_ping(data: PingData):
    if data.role == "TARGET":
        cursor.execute("REPLACE INTO targets (userid, jobid, last_seen) VALUES (?, ?, ?)", (data.userid, data.jobid, time.time()))
        conn.commit()
    return {"status": "ok"}

@app.get("/api/mission")
def get_mission(userid: str):
    cursor.execute("SELECT userid, jobid FROM targets ORDER BY last_seen ASC LIMIT 1")
    target = cursor.fetchone()
    if target:
        add_log(f"{G}HUNTING{X} -> Target Intercepted in [{target[1][:8]}]")
        return {"action": "EXECUTE", "mission": "HUNT", "target_userid": target[0], "dwell_time": config["target_timer"]}
    add_log(f"{Y}IDLE{X} -> No Signal. Resting the Fool.")
    return {"action": "EXECUTE", "mission": "REST", "target_userid": "null", "dwell_time": config["base_timer"]}

def scan_for_packages():
    print(f"\n {C}Scanning environment for prefix: {W}{config['search_filter']}{X}")
    raw = os.popen(f"pm list packages | grep {config['search_filter']}").read()
    packages = [line.replace("package:", "").strip() for line in raw.split("\n") if line]
    if not packages:
        print(f" {R}No packages found matching {config['search_filter']}.{X}")
        time.sleep(1)
        return config["active_pkgs"]
    for i, pkg in enumerate(packages): print(f" {W}[{X}{C} {i+1} {X}{W}]{X} {pkg}")
    choice = input(f"\n {G}Selection (1,2 / 1-3 / all):{X} ").strip().lower()
    try:
        if choice == 'all': return packages
        if '-' in choice:
            s, e = map(int, choice.split('-'))
            return packages[s-1:e]
        if ',' in choice:
            return [packages[int(i)-1] for i in choice.split(',')]
        return [packages[int(choice)-1]]
    except: return config["active_pkgs"]

def draw_header():
    os.system('clear')
    print(f"{G}")
    print(r"  ██████╗ ██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗")
    print(r"  ╚══██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║")
    print(r"     ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║")
    print(r"     ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║")
    print(r"     ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗")
    print(r"     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝")
    print(f"{X} {W}[{X} {G}SYSTEM: THE FOOL'S COURT{X} {W}]{X}\n")

def draw_live():
    while True:
        time.sleep(1)
        draw_header()
        cursor.execute("SELECT COUNT(*) FROM targets")
        active = cursor.fetchone()[0]
        print(f" {W}[{X}{G} STATUS {X}{W}]{X} : {G}ACTIVE{X}\n {W}[{X}{C} TARGET {X}{W}]{X} : {G}{active} Signals Found{X}\n {W}[{X}{C} ANCHORS{X}{W}]{X} : {G}{len(config['active_pkgs'])} Connected Instances{X}\n {W}--------------------------------------------------{X}\n {C}LIVE INTERCEPT SIGNALS:{X}")
        for log in list(comm_log): print(f" {W}>{X} {log}")
        print(f"\n {W}Press {X}{R}'s'{X}{W} + Enter to terminate session.{X}")

def interactive_menu():
    while True:
        draw_header()
        print(f" {W}[{X}{G} STATUS {X}{W}]{X} : {R}OFFLINE{X}\n {W}--------------------------------------------------{X}\n {W}[{X}{C} 1 {X}{W}]{X} The Fool's Hop     : {W}{config['target_timer']}s{X}\n {W}[{X}{C} 2 {X}{W}]{X} Fool's Rest Time   : {W}{config['base_timer']}s{X}\n {W}[{X}{C} 3 {X}{W}]{X} Search Filter      : {W}{config['search_filter']}{X}\n {W}[{X}{C} 4 {X}{W}]{X} Active Anchors     : {W}{len(config['active_pkgs'])}{X}\n {W}[{X}{C} 5 {X}{W}]{X} Primary Homebase   : {W}{config['primary_base'][:15]}...{X}\n {W}--------------------------------------------------{X}\n {W}[{X}{G} S {X}{W}]{X} {G}AWAKEN THE FOOL{X}\n {W}[{X}{R} Q {X}{W}]{X} {R}TERMINATE{X}\n")
        cmd = input(f" {G}Directive:{X} ").strip().upper()
        if cmd == 'S': break
        if cmd == 'Q': sys.exit()
        try:
            if cmd == '1': config['target_timer'] = int(input("Seconds: "))
            elif cmd == '2': config['base_timer'] = int(input("Seconds: "))
            elif cmd == '3': config['search_filter'] = input("Filter (e.g. com.lana): ").strip()
            elif cmd == '4': config['active_pkgs'] = scan_for_packages()
            elif cmd == '5': config['primary_base'] = input("Link: ").strip()
            save_config()
        except: pass

if __name__ == "__main__":
    interactive_menu()
    if config["primary_base"] != "None":
        for pkg in config["active_pkgs"]:
            os.system(f'am start -a android.intent.action.VIEW -d "{config["primary_base"]}" {pkg} > /dev/null 2>&1')
            time.sleep(2)
    threading.Thread(target=draw_live, daemon=True).start()
    uvicorn.run(app, host="0.0.0.0", port=8000)
