import os
import time
import json
import sqlite3
import threading
import requests
import subprocess
from fastapi import FastAPI, HTTPException, Header
import uvicorn
from pydantic import BaseModel

# ==========================================
# 1. THE CONFIG WIZARD & WEBHOOKS
# ==========================================
CONFIG_FILE = "config.json"

def load_or_create_config():
    if not os.path.exists(CONFIG_FILE):
        os.system("clear")
        print("======================================")
        print("      INITIALIZING THE FOOL'S COURT   ")
        print("======================================")
        webhook = input("> Enter Discord Webhook URL: ")
        discord_id = input("> Enter your Discord User ID: ")
        api_key = input("> Create a Secret API Key for Bots: ")
        
        # --- ROBLOX PACKAGE SCANNER ---
        print("\n> Scanning Android for Roblox packages...")
        packages = []
        try:
            output = subprocess.check_output("pm list packages | grep 'com.roblox.'", shell=True, text=True)
            packages = [line.split(':')[1].strip() for line in output.strip().split('\n') if line]
        except Exception:
            pass

        target_pkg = "com.roblox.client" 
        
        if packages:
            print("\n[!] Found the following Roblox versions:")
            for i, pkg in enumerate(packages):
                print(f"  {i+1}. {pkg}")
            
            choice = input(f"\n> Choose package for auto-launch (1-{len(packages)}): ")
            try:
                target_pkg = packages[int(choice)-1]
            except (ValueError, IndexError):
                print(f"[!] Invalid choice. Defaulting to {packages[0]}")
                target_pkg = packages[0]
        else:
            print("\n[!] No Roblox packages detected.")
            target_pkg = input("> Enter package name manually: ")

        print(f"\n[+] Selected Package: {target_pkg}")

        # Inject the 'hunt' command into Termux
        try:
            alias_cmd = f"alias hunt='am force-stop {target_pkg} && sleep 2 && monkey -p {target_pkg} -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1 && echo \"[+] Launched {target_pkg}\"'"
            os.system(f"echo \"{alias_cmd}\" >> ~/.bashrc")
            print("[+] 'hunt' command installed to Termux!")
        except Exception:
            print("[!] Could not auto-install 'hunt' alias.")

        config_data = {
            "webhook_url": webhook,
            "discord_id": discord_id,
            "api_key": api_key,
            "max_retries": 5,
            "roblox_package": target_pkg
        }
        with open(CONFIG_FILE, "w") as f:
            json.dump(config_data, f, indent=4)
        
        print("\n[+] Config saved! Starting Hub...\n")
        
        if webhook:
            try:
                requests.post(webhook, json={"content": "🃏 **The Fool's Court is online.** System linked."})
            except:
                pass
        time.sleep(2)
        return config_data
    
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)

config = load_or_create_config()

def send_discord_alert(message):
    if not config["webhook_url"]: return
    payload = {"content": f"<@{config['discord_id']}> {message}"}
    try:
        requests.post(config["webhook_url"], json=payload, timeout=3)
    except: pass

# ==========================================
# 2. DATABASE & STARTUP WIPE
# ==========================================
def init_db():
    conn = sqlite3.connect("farm_hub.db")
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS beacons (userid TEXT PRIMARY KEY, jobid TEXT, last_ping REAL)''')
    c.execute('''CREATE TABLE IF NOT EXISTS stats (id INTEGER PRIMARY KEY, status TEXT, trades_done INTEGER, fails INTEGER, current_jobid TEXT)''')
    c.execute("INSERT OR IGNORE INTO stats (id, status, trades_done, fails, current_jobid) VALUES (1, 'IDLE', 0, 0, 'None')")
    c.execute("UPDATE stats SET status = 'IDLE', current_jobid = 'None' WHERE id = 1")
    conn.commit()
    conn.close()

init_db()
START_TIME = time.time()

# ==========================================
# 3. FASTAPI C2 SERVER
# ==========================================
app = FastAPI()

def verify_token(authorization: str = Header(None)):
    if not authorization or authorization != f"Bearer {config['api_key']}":
        raise HTTPException(status_code=401, detail="Unauthorized")

class PingData(BaseModel):
    userid: str
    jobid: str

@app.post("/api/ping")
def farm_ping(data: PingData, authorization: str = Header(None)):
    verify_token(authorization)
    conn = sqlite3.connect("farm_hub.db")
    c = conn.cursor()
    c.execute("REPLACE INTO beacons (userid, jobid, last_ping) VALUES (?, ?, ?)", (data.userid, data.jobid, time.time()))
    conn.commit()
    conn.close()
    return {"status": "ok"}

@app.get("/api/get_target")
def get_target(authorization: str = Header(None)):
    verify_token(authorization)
    conn = sqlite3.connect("farm_hub.db")
    c = conn.cursor()
    
    if time.time() - START_TIME < 180:
        return {"jobid": "WAITING_FOR_BEACONS"}

    cutoff = time.time() - 120 
    c.execute("SELECT jobid FROM beacons WHERE last_ping > ? ORDER BY last_ping ASC LIMIT 1", (cutoff,))
    row = c.fetchone()
    
    if row:
        target = row[0]
        c.execute("UPDATE stats SET status = 'HOPPING', current_jobid = ? WHERE id = 1", (target,))
        conn.commit()
        conn.close()
        return {"jobid": target}
    
    conn.close()
    return {"jobid": "None"}

@app.post("/api/trade_success")
def trade_success(authorization: str = Header(None)):
    verify_token(authorization)
    conn = sqlite3.connect("farm_hub.db")
    c = conn.cursor()
    c.execute("UPDATE stats SET trades_done = trades_done + 1, status = 'IDLE', current_jobid = 'None' WHERE id = 1")
    conn.commit()
    conn.close()
    return {"status": "ok"}

@app.post("/api/trade_fail")
def trade_fail(jobid: str, authorization: str = Header(None)):
    verify_token(authorization)
    conn = sqlite3.connect("farm_hub.db")
    c = conn.cursor()
    c.execute("UPDATE stats SET fails = fails + 1, status = 'IDLE', current_jobid = 'None' WHERE id = 1")
    conn.commit()
    conn.close()
    send_discord_alert(f"[FAILED HOP] Skipped JobID: `{jobid[:12]}...`")
    return {"status": "ok"}

@app.get("/api/dashboard_data")
def dashboard_data():
    conn = sqlite3.connect("farm_hub.db")
    c = conn.cursor()
    c.execute("SELECT status, trades_done, fails, current_jobid FROM stats WHERE id = 1")
    stats = c.fetchone()
    
    cutoff = time.time() - 120
    c.execute("SELECT count(*) FROM beacons WHERE last_ping > ?", (cutoff,))
    active = c.fetchone()[0]
    
    c.execute("SELECT count(*) FROM beacons")
    total = c.fetchone()[0]
    conn.close()
    
    return {
        "status": stats[0], "target": stats[3], "active_beacons": active, 
        "total_beacons": total, "trades": stats[1], "fails": stats[2]
    }

# ==========================================
# 4. BACKGROUND TASKS
# ==========================================
def garbage_collector():
    while True:
        time.sleep(300)
        if time.time() - START_TIME < 180: continue 
        conn = sqlite3.connect("farm_hub.db")
        c = conn.cursor()
        dead_cutoff = time.time() - 86400 
        c.execute("DELETE FROM beacons WHERE last_ping < ?", (dead_cutoff,))
        conn.commit()
        conn.close()

threading.Thread(target=garbage_collector, daemon=True).start()

def draw_dashboard():
    while True:
        try:
            conn = sqlite3.connect("farm_hub.db")
            c = conn.cursor()
            c.execute("SELECT status, trades_done, fails, current_jobid FROM stats WHERE id = 1")
            stats = c.fetchone()
            cutoff = time.time() - 120
            c.execute("SELECT count(*) FROM beacons WHERE last_ping > ?", (cutoff,))
            active = c.fetchone()[0]
            c.execute("SELECT count(*) FROM beacons")
            total = c.fetchone()[0]
            conn.close()

            uptime_seconds = int(time.time() - START_TIME)
            hours, remainder = divmod(uptime_seconds, 3600)
            minutes, seconds = divmod(remainder, 60)
            uptime_str = f"{hours:02d}h {minutes:02d}m {seconds:02d}s"

            os.system('clear')
            print("======================================")
            print("        🃏 THE FOOL'S COURT           ")
            print("======================================")
            print(" [ SYSTEM ]")
            if time.time() - START_TIME < 180:
                print(f" Mode       : GRACE PERIOD (Healing)")
            else:
                print(f" Mode       : ACTIVE")
            print(f" Uptime     : {uptime_str}")
            print(f" Override   : None\n")
            print(" [ THE HUNTER ]")
            print(f" Status     : {stats[0]}")
            tgt = stats[3]
            print(f" Target ID  : {tgt[:12]}..." if tgt != "None" else " Target ID  : None")
            print("\n [ THE NETWORK ]")
            print(f" Beacons    : {active} / {total} Online")
            print(f" Success    : {stats[1]}")
            print(f" Fail       : {stats[2]}\n")
            print(" [ LOGS ]")
            print(" > System synced.")
            print("======================================")
        except Exception: pass
        time.sleep(1)

threading.Thread(target=draw_dashboard, daemon=True).start()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="critical")
