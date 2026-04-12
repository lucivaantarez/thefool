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
G, C, W, R, Y, X = '\033[1;32m', '\033[1;36m', '\033[1;37m', '\033[1;31m', '\033[1;33m', '\033[0m'

config = {
    "target_timer": 300, "base_timer": 1800, "primary_base": "None",
    "search_filter": "com.roblox", "active_pkgs": ["com.roblox.client"],
    "window_mode": "1x1", "relaunch_enabled": True
}

anchor_health, anchor_map, comm_log = {}, {}, deque(maxlen=8)

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

def add_log(msg): comm_log.append(msg)

class PingData(BaseModel):
    userid: str; jobid: str; role: str; pkg: str = ""

@app.post("/api/ping")
def handle_ping(data: PingData):
    now = time.time()
    if data.role == "TARGET":
        cursor.execute("REPLACE INTO targets (userid, jobid, last_seen) VALUES (?, ?, ?)", (data.userid, data.jobid, now))
        conn.commit()
    elif data.role == "ANCHOR":
        if data.jobid not in anchor_map:
            for pkg in config["active_pkgs"]:
                if pkg not in anchor_health or (now - anchor_health[pkg] > 120):
                    anchor_map[data.jobid] = pkg
                    add_log(f"{G}LINKED{X} -> {pkg[:12]} identified.")
                    break
        target_pkg = anchor_map.get(data.jobid, config["active_pkgs"][0])
        anchor_health[target_pkg] = now
    return {"status": "ok"}

@app.get("/api/mission")
def get_mission(userid: str):
    cursor.execute("SELECT userid, jobid FROM targets ORDER BY last_seen ASC LIMIT 1")
    target = cursor.fetchone()
    if target:
        add_log(f"{G}LANA_SIGNAL{X} -> Target found in [{target[1][:8]}]")
        return {"action": "EXECUTE", "mission": "HUNT", "target_userid": target[0], "dwell_time": config["target_timer"]}
    return {"action": "EXECUTE", "mission": "REST", "target_userid": "null", "dwell_time": config["base_timer"]}

def get_bounds(index):
    if config["window_mode"] == "1x1": return "0,0,360,360" if index == 0 else "360,0,720,360"
    if config["window_mode"] == "1x2": return "0,0,360,720" if index == 0 else "360,0,720,720"
    return None

def launch_instance(pkg, index):
    bounds = get_bounds(index)
    link = config.get("primary_base", "None")
    
    # If no link, just open the app. If link exists, force it into the Roblox Activity.
    if link == "None" or link == "":
        cmd = f'am start -n {pkg}/com.roblox.client.ActivityMain'
    else:
        cmd = f'am start -n {pkg}/com.roblox.client.ActivityMain -a android.intent.action.VIEW -d "{link}"'
        
    if bounds and config["window_mode"] != "Full":
        cmd = cmd.replace('am start', f'am start --bounds "{bounds}"')
        
    os.system(f'{cmd} > /dev/null 2>&1')
    anchor_health[pkg] = time.time()

def sentinel_watcher():
    while True:
        time.sleep(30)
        if not config["relaunch_enabled"]: continue
        now = time.time()
        for i, pkg in enumerate(config["active_pkgs"]):
            if now - anchor_health.get(pkg, now) > 95:
                add_log(f"{R}SENTINEL{X} -> {pkg[:10]} lost. Relaunching...")
                launch_instance(pkg, i)

def scan_for_packages():
    draw_header()
    print(f" {C}Scanning for prefix: {W}{config['search_filter']}{X}")
    raw = os.popen(f"pm list packages | grep {config['search_filter']}").read()
    packages = [line.replace("package:", "").strip() for line in raw.split("\n") if line]
    if not packages: return config["active_pkgs"]
    for i, p in enumerate(packages): print(f" {W}[{X}{C} {i+1} {X}{W}]{X} {p}")
    choice = input(f"\n {G}Selection (1,2 / 1-3 / all):{X} ").strip().lower()
    try:
        if choice == 'all': return packages
        if '-' in choice:
            s, e = map(int, choice.split('-'))
            return packages[s-1:e]
        return [packages[int(i)-1] for i in choice.split(',')] if ',' in choice else [packages[int(choice)-1]]
    except: return config["active_pkgs"]

def draw_header(status="OFFLINE"):
    os.system('clear')
    print(f"{G}  ████████╗██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗\n  ╚══██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║\n     ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║\n     ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║\n     ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗\n     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝{X}")
    print(f" {W}[{X} {G}SYSTEM: THE FOOL'S COURT{X} {W}]{X} : {G if status=='ACTIVE' else R}{status}{X}\n")

def draw_live():
    while True:
        time.sleep(1)
        draw_header("ACTIVE")
        cursor.execute("SELECT COUNT(*) FROM targets")
        print(f" {W}[{X}{C} TARGETS {X}{W}]{X} : {G}{cursor.fetchone()[0]} Signals{X}\n {W}[{X}{C} ANCHORS {X}{W}]{X} : {G}{len(config['active_pkgs'])} Protected{X}\n {W}--------------------------------------------------{X}\n {C}LANA LIVE INTERCEPT:{X}")
        for log in list(comm_log): print(f" {W}>{X} {log}")
        print(f"\n {W}Press {X}{R}'s'{X}{W} + Enter to Terminate.{X}")

def interactive_menu():
    while True:
        draw_header()
        print(f" {W}--------------------------------------------------{X}\n {W}[{X}{C} 1 {X}{W}]{X} The Fool's Hop   : {W}{config['target_timer']}s{X}\n {W}[{X}{C} 2 {X}{W}]{X} Fool's Rest Time : {W}{config['base_timer']}s{X}\n {W}[{X}{C} 3 {X}{W}]{X} Search Filter    : {W}{config['search_filter']}{X}\n {W}[{X}{C} 4 {X}{W}]{X} Active Anchors   : {W}{len(config['active_pkgs'])}{X}\n {W}[{X}{C} 5 {X}{W}]{X} Window Layout    : {W}{config['window_mode']}{X}\n {W}[{X}{C} 6 {X}{W}]{X} Homebase Link    : {W}{config.get('primary_base', 'None')[:20]}...{X}\n {W}--------------------------------------------------{X}\n {W}[{X}{G} S {X}{W}]{X} {G}AWAKEN THE FOOL{X}\n {W}[{X}{R} Q {X}{W}]{X} {R}TERMINATE{X}\n")
        cmd = input(f" {G}Directive:{X} ").strip().upper()
        if cmd == 'S': break
        if cmd == 'Q': sys.exit()
        try:
            if cmd == '1': config['target_timer'] = int(input("Seconds: "))
            elif cmd == '2': config['base_timer'] = int(input("Seconds: "))
            elif cmd == '3': config['search_filter'] = input("Filter: ").strip()
            elif cmd == '4': config['active_pkgs'] = scan_for_packages()
            elif cmd == '5':
                print(f"\n {C}1: Full | 2: 1x1 | 3: 1x2{X}"); m = input("Choice: ")
                config['window_mode'] = "Full" if m=='1' else "1x1" if m=='2' else "1x2"
            elif cmd == '6': config['primary_base'] = input("Link: ").strip()
            save_config()
        except: pass

if __name__ == "__main__":
    interactive_menu()
    for i, pkg in enumerate(config["active_pkgs"]): launch_instance(pkg, i)
    threading.Thread(target=sentinel_watcher, daemon=True).start()
    threading.Thread(target=draw_live, daemon=True).start()
    threading.Thread(target=lambda: (input(), os._exit(0)), daemon=True).start()
    uvicorn.run(app, host="0.0.0.0", port=8000)
