# The Fool's Court: Swarm Architecture

A highly optimized, multi-node Command & Control architecture designed for Roblox automation across Redfinger cloud environments (Android 10/Termux). It utilizes a centralized API hub to route worker nodes (Hoppers) to designated targets in real-time, completely bypassing traditional executor limitations.

## Core Features
* **Zero-Touch Updates:** Workers pull their routing logic directly from this repository dynamically.
* **Hardware Watchdog:** Sub-Hubs monitor local Android memory limits and forcefully reboot frozen Roblox packages.
* **Intelligent Routing:** Eliminates API rate limits via the SQLite SQLite target/rest queue.
* **Cloudflare Integrated:** Natively uses Cloudflare Quick Tunnels for external API exposure.

---

## 1. Installation

This system requires zero manual configuration. Run the single-line injector on your target Redfinger devices inside Termux.

```bash
curl -sSL https://raw.githubusercontent.com/lucivaantarez/thefool/main/setup.sh > setup.sh && bash setup.sh && source ~/.bashrc && rm setup.sh
