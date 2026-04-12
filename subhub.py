import os, sys, json, time, threading
from collections import deque
from fastapi import FastAPI
import uvicorn
import logging

logging.getLogger("uvicorn").setLevel(logging.CRITICAL)
logging.getLogger("uvicorn.access").setLevel(logging.CRITICAL)

app = FastAPI(); CONFIG_FILE = "sub_config.json"
G, C, W, R, Y, X = '\033[1;32m', '\033[1;36m', '\033[1;37m', '\033[1;31m', '\033[1;33m', '\033[0m'

config = {"target_packages": ["com.roblox.client"], "crash_timeout": 300, "search_filter": "com.roblox"}

if os.path.exists(CONFIG_FILE):
    try:
        with open(CONFIG_FILE, "r") as f: config.update(json.load(f))
    except: pass
else:
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

def save_config():
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

SYSTEM_STATE = "STANDBY"
active_hoppers, watchdog_log = {}, deque(maxlen=7)

def add_log(msg): watchdog_log.append(msg)

def draw_header(status="OFFLINE"):
    os.system('clear')
    print(f"{G}  ████████╗██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗\n  ╚══██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║\n     ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║\n     ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║\n     ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗\n     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝{X}")
    print(f" {W}[{X} {C}SYSTEM: SWARM_WORKER_V3.6{X} {W}]{X} : {G if status=='ARMED' else R}{status}{X}\n")

def scan_packages():
    draw_header("CONFIG")
    raw = os.popen(f"pm list packages | grep {config['search_filter']}").read()
    packages = [line.replace("package:", "").strip() for line in raw.split("\n") if line]
    if not packages: return config["target_packages"]
    for i, p in enumerate(packages): print(f" [{i+1}] {p}")
    choice = input(f"\n {G}Selection (e.g. 1,2):{X} ").strip()
    try: return [packages[int(c.strip())-1] for c in choice.split(",") if c.strip()]
    except: return config["target_packages"]

def launch_app(pkg): os.system(f"am start -n {pkg}/com.roblox.client.ActivityMain > /dev/null 2>&1")

def anomaly_checker():
    global SYSTEM_STATE
    while True:
        time.sleep(10)
        if SYSTEM_STATE != "ARMED": continue
        now = time.time()
        for h_id, last_p in list(active_hoppers.items()):
            if now - last_p > config["crash_timeout"]:
                add_log(f"{R}CRASH{X} -> Rebooting node...")
                for p in config["target_packages"]: os.system(f"am force-stop {p} > /dev/null 2>&1")
                time.sleep(3)
                for p in config["target_packages"]: launch_app(p); time.sleep(2)
                active_hoppers[h_id] = time.time() + 60; break 

@app.get("/local_ping")
def local_ping(hopper_id: str):
    global SYSTEM_STATE
    if hopper_id not in active_hoppers: add_log(f"{C}SIGNAL{X} -> Hopper [{hopper_id[:6]}] online.")
    active_hoppers[hopper_id] = time.time()
    if SYSTEM_STATE == "BOOTING" and len(active_hoppers) >= len(config["target_packages"]):
        SYSTEM_STATE = "ARMED"; add_log(f"{G}READY{X} -> Swarm ARMED.")
    return {"status": "ok"}

def draw_live():
    while True:
        time.sleep(1); draw_header(SYSTEM_STATE)
        print(f" {W}[{X}{C} TIMEOUT {X}{W}]{X} : {config['crash_timeout']}s | {W}[{X}{C} APPS {X}{W}]{X} : {len(config['target_packages'])}\n {W}--------------------------------------------------{X}\n {W}[{X} {C}LOCAL WATCHDOG LOG{X} {W}]{X}")
        for log in list(watchdog_log): print(f" {W}>{X} {log}")
        print(f"\n {W}Type {X}{R}'q'{X}{W} and press Enter to kill.{X}")

if __name__ == "__main__":
    draw_header("STANDBY")
    print(f" [1] Target Apps: {len(config['target_packages'])}\n [2] Timeout: {config['crash_timeout']}s\n [S] ARM WATCHDOG\n")
    if input("> ").upper() == 'S':
        SYSTEM_STATE = "BOOTING"
        for p in config["target_packages"]: launch_app(p); time.sleep(2)
        threading.Thread(target=draw_live, daemon=True).start()
        threading.Thread(target=anomaly_checker, daemon=True).start()
        threading.Thread(target=lambda: (input(), os._exit(0)), daemon=True).start()
        uvicorn.run(app, host="127.0.0.1", port=5000)
