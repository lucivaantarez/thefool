import os
import time
import requests

HUB_URL = "https://intersectant-unaffrightedly-somer.ngrok-free.dev/api/dashboard_data"

def clear_screen():
    os.system('clear')

def run_monitor():
    while True:
        try:
            response = requests.get(HUB_URL, timeout=3)
            data = response.json()
            
            status = data.get("status", "UNKNOWN")
            target = data.get("target", "None")
            active = data.get("active_beacons", 0)
            total = data.get("total_beacons", 0)
            success = data.get("trades", 0)
            fails = data.get("fails", 0)
            
            clear_screen()
            print("======================================")
            print("          THE FOOL'S COURT            ")
            print("======================================")
            print(" [ SYSTEM ]")
            print(f" Mode       : {status}")
            print(f" Override   : None\n")
            print(" [ THE HUNTER ]")
            print(f" Status     : {status}")
            print(f" Target ID  : {target[:12]}..." if target != "None" else " Target ID  : None\n")
            print(" [ THE NETWORK ]")
            print(f" Beacons    : {active} / {total} Online")
            print(f" Success    : {success}")
            print(f" Fail       : {fails}\n")
            print(" [ LOGS ]")
            print(" > System synced.")
            print("======================================")
            
        except requests.exceptions.RequestException:
            clear_screen()
            print("======================================")
            print("          THE FOOL'S COURT            ")
            print("======================================")
            print("\n [ ! ] CONNECTION LOST TO REDFINGER")
            print(" Waiting for Hub to come online...\n")
            print("======================================")

        time.sleep(1.5)

if __name__ == "__main__":
    run_monitor()
