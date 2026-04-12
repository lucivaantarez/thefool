import os, sys, json, time, threading
from collections import deque
from fastapi import FastAPI
import uvicorn
import logging

logging.getLogger("uvicorn").setLevel(logging.CRITICAL)
logging.getLogger("uvicorn.access").setLevel(logging.CRITICAL)

app = FastAPI()
CONFIG_FILE = "sub_config.json"
config = {"target_packages": ["com.roblox.client"], "crash_timeout": 300}

if os.path.exists(CONFIG_FILE):
    with open(CONFIG_FILE, "r") as f: config.update(json.load(f))
else:
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

def save_config():
    with open(CONFIG_FILE, "w") as f: json.dump(config, f, indent=4)

SYSTEM_STATE = "STANDBY"
active_hoppers = {}
watchdog_log = deque(maxlen=8)

PURPLE, WHITE, CYAN, RED, RESET = '\033[95m', '\033[97m', '\033[96m', '\033[91m', '\033[0m'

def add_log(msg): watchdog_log.append(msg)
def clear_screen(): os.system('clear')

def scan_packages():
    print(CYAN + "\n[SYSTEM] Scanning Redfinger for Roblox instances..." + RESET)
    raw = os.popen("pm list packages | grep roblox").read()
    packages = [line.replace("package:", "").strip() for line in raw.split("\n") if line]
    if not packages: return config["target_packages"]
    for i, pkg in enumerate(packages): print(f"  [{i+1}] {pkg}")
    print(WHITE + "\nType the numbers you want to target, separated by a comma." + RESET)
    choice = input(CYAN + "Selection (e.g., 1,2): " + RESET)
    selected = [packages[int(c.strip())-1] for c in choice.split(",") if 0 <= int(c.strip())-1 < len(packages)]
    return selected if selected else config["target_packages"]

def launch_app(pkg_name): os.system(f"monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1")

def anomaly_checker():
    global SYSTEM_STATE
    while True:
        time.sleep(10)
        if SYSTEM_STATE != "ARMED": continue
        current_time = time.time()
        for hopper_id, last_ping in list(active_hoppers.items()):
            if current_time - last_ping > config["crash_timeout"]:
                add_log(f"> WARNING: Hopper silent. Wiping active packages...")
                for pkg in config["target_packages"]: os.system(f"am force-stop {pkg} > /dev/null 2>&1")
                time.sleep(3)
                for pkg in config["target_packages"]: launch_app(pkg); time.sleep(2)
                active_hoppers[hopper_id] = time.time() + 60 
                add_log(f"> Node: Swarm rebooted. Awaiting pings.")
                break 

@app.get("/local_ping")
def local_ping(hopper_id: str):
    global SYSTEM_STATE
    if hopper_id not in active_hoppers: add_log(f"> Node: Hopper [{hopper_id[:6]}] ping received.")
    active_hoppers[hopper_id] = time.time()
    if SYSTEM_STATE == "BOOTING" and len(active_hoppers) >= len(config["target_packages"]):
        SYSTEM_STATE = "ARMED"
        add_log("> Node: All local forces online. System ARMED.")
    return {"status": "received"}

def draw_static_menu():
    clear_screen()
    print(PURPLE + "+===================================================+\n|                                                   |\n|          T H E  F O O L ' S  S W A R M            |\n|                                                   |\n+===================================================+" + RESET)
    print(WHITE + f"|  NODE STATUS            :  {CYAN}[ STANDBY ]{WHITE}            |\n+---------------------------------------------------+")
    print(f"|  [1] Target Packages    :  {len(config['target_packages'])} Apps Selected")
    print(f"|  [2] Crash Timeout      :  {config['crash_timeout']} seconds\n" + PURPLE + "+===================================================+" + RESET)
    print(WHITE + "|  [E] Configuration                                |\n|  [S] Arm the Watchdog (Auto-Launch)               |\n|  [Q] Disconnect Node                              |\n" + PURPLE + "+---------------------------------------------------+" + RESET)

def interactive_menu():
    while True:
        draw_static_menu()
        choice = input(WHITE + "Select an action: " + RESET).strip().upper()
        if choice == 'Q': sys.exit(0)
        elif choice == 'S': break 
        elif choice == 'E':
            opt = input(CYAN + "Which setting to edit (1-2)? " + RESET)
            if opt == '1': config['target_packages'] = scan_packages()
            elif opt == '2': config['crash_timeout'] = int(input("New Timeout (seconds): "))
            save_config()

def draw_live_dashboard():
    while True:
        time.sleep(1)
        clear_screen()
        print(PURPLE + "+===================================================+\n|                                                   |\n|          T H E  F O O L ' S  S W A R M            |\n|                                                   |\n+===================================================+" + RESET)
        print(WHITE + f"|  NODE STATUS            :  {CYAN}[ {SYSTEM_STATE} ]{WHITE}" + " " * (13 - len(SYSTEM_STATE)) + "|\n|  CRASH TIMEOUT          :  {CYAN}{config['crash_timeout']} SECONDS{WHITE}          |\n|  TARGETED APPS          :  {CYAN}{len(config['target_packages'])} PACKAGES{WHITE}         |\n" + PURPLE + "+---------------------------------------------------+" + RESET)
        print(WHITE + "|  [ LOCAL WATCHDOG LOG ]                           |")
        log_list = list(watchdog_log)
        for i in range(7): print(f"| {log_list[i][:45]:<49} |" if i < len(log_list) else f"| {' ':<49} |")
        print(PURPLE + "+===================================================+" + RESET)
        print(WHITE + "Type " + CYAN + "'q'" + WHITE + " and press [ENTER] to kill the Watchdog." + RESET)

def listen_for_kill():
    while True:
        if input().strip().lower() == 'q':
            for pkg in config["target_packages"]: os.system(f"am force-stop {pkg} > /dev/null 2>&1")
            os._exit(0)

if __name__ == "__main__":
    interactive_menu()
    SYSTEM_STATE = "BOOTING"
    add_log(f"> Node: Booting {len(config['target_packages'])} application(s)...")
    for pkg in config["target_packages"]: launch_app(pkg); time.sleep(2)
    threading.Thread(target=draw_live_dashboard, daemon=True).start()
    threading.Thread(target=anomaly_checker, daemon=True).start()
    threading.Thread(target=listen_for_kill, daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=5000)
