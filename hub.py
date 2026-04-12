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

# ANSI Bold Colors
G, C, W, R, Y, X = '\033[1;32m', '\033[1;36m', '\033[1;37m', '\033[1;31m', '\033[1;33m', '\033[0m'

config = {
    "target_timer": 300, 
    "base_timer": 1800, 
    "primary_base": "None", 
    "primary_pkg": "com.roblox.client"
}

if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, "r") as f: config.update(json.load(f))
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
        add_log(f"{G}HUNTING{X} -> Target detected in [{target[1][:8]}]")
        return {"action": "EXECUTE", "mission": "HUNT", "target_userid": target[0], "dwell_time": config["target_timer"]}
    add_log(f"{Y}IDLE{X} -> No targets. Sending to Homebase.")
    return {"action": "EXECUTE", "mission": "REST", "target_userid": "null", "dwell_time": config["base_timer"]}

def get_uptime():
    h, rem = divmod(int(time.time() - start_time), 3600)
    m, s = divmod(rem, 60)
    return f"{h}h {m}m {s}s"

def draw_header():
    os.system('clear')
    print(f"""{G}
 ████████╗██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗     
 ╚══██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║     
    ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║     
    ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║     
    ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗
    ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝{X}""")
    print(f" {W}[{X} {G}SYSTEM: THE FOOL'S COURT{X} {W}]{X}\n")

def draw_static_menu():
    draw_header()
    print(f" {W}[{X}{G} STATUS {X}{W}]{X} : {R}OFFLINE{X}")
    print(f" {W}--------------------------------------------------{X}")
    print(f" {W}[{X}{C} 1 {X}{W}]{X} The Fool's Hop     : {W}{config['target_timer']}s{X}")
    print(f" {W}[{X}{C} 2 {X}{W}]{X} Fool's Rest Time   : {W}{config['base_timer']}s{X}")
    print(f" {W}[{X}{C} 3 {X}{W}]{X} Primary Homebase   : {W}{config['primary_base'][:20]}...{X}")
    print(f" {W}[{X}{C} 4 {X}{W}]{X} Roblox Package     : {W}{config['primary_pkg']}{X}")
    print(f" {W}--------------------------------------------------{X}")
    print(f" {W}[{X}{G} S {X}{W}]{X} {G}AWAKEN THE FOOL{X}")
    print(f" {W}[{X}{R} Q {X}{W}]{X} {R}TERMINATE{X}\n")

def draw_live_dashboard():
    while True:
        time.sleep(1)
        draw_header()
        cursor.execute("SELECT COUNT(*) FROM targets")
        active = cursor.fetchone()[0]
        print(f" {W}[{X}{G} STATUS {X}{W}]{X} : {G}ACTIVE{X}")
        print(f" {W}[{X}{C} UPTIME {X}{W}]{X} : {W}{get_uptime()}{X}")
        print(f" {W}[{X}{C} TARGET {X}{W}]{X} : {G}{active} Active Servers{X}")
        print(f" {W}--------------------------------------------------{X}")
        print(f" {C}LIVE INTERCEPT SIGNALS:{X}")
        log_list = list(comm_log)
        for log in log_list:
            print(f" {W}>{X} {log}")
        print(f"\n {W}Press {X}{R}'s'{X}{W} + Enter to kill server.{X}")

def interactive_menu():
    while True:
        draw_static_menu()
        cmd = input(f" {G}Directive:{X} ").strip().upper()
        if cmd == 'S': break
        if cmd == 'Q': sys.exit()
        
        try:
            if cmd == '1':
                val = input(f" {C}New Hop Time (s):{X} ")
                if val: config['target_timer'] = int(val)
            elif cmd == '2':
                val = input(f" {C}New Rest Time (s):{X} ")
                if val: config['base_timer'] = int(val)
            elif cmd == '3':
                val = input(f" {C}New Homebase Link:{X} ").strip()
                if val: config['primary_base'] = val
            elif cmd == '4':
                val = input(f" {C}New Package Name:{X} ").strip()
                if val: config['primary_pkg'] = val
            save_config()
        except ValueError:
            print(f" {R}Error: Number required.{X}")
            time.sleep(1)

if __name__ == "__main__":
    interactive_menu()
    if config["primary_base"] != "None":
        os.system(f'am start -a android.intent.action.VIEW -d "{config["primary_base"]}" {config["primary_pkg"]} > /dev/null 2>&1')
    threading.Thread(target=draw_live_dashboard, daemon=True).start()
    uvicorn.run(app, host="0.0.0.0", port=8000)
