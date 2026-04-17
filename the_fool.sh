#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  THE FOOL — Roblox Private Server Hopper
#  Version: 1.0.0
#  Author: Saturnity
#  Self-updating via GitHub. Deploy: curl -s <RAW_URL> | bash
# ════════════════════════════════════════════════════════════════════

set -uo pipefail

# ── CONSTANTS ────────────────────────────────────────────────────────
readonly VERSION="1.0.0"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/lucivaantarez/thefool/refs/heads/main/the_fool.sh"
readonly API_ENDPOINT="https://universe-vault.vercel.app/api/links"
readonly API_AUTH_TOKEN="fool-secret-token-2025"
readonly SELF_PATH="$(realpath "$0")"
readonly STATE_DIR="${HOME}/.fool_state"
readonly MAX_LINE_WIDTH=72

# ── CONFIG (mutable via lobby) ────────────────────────────────────────
CACHE_CLEAR_INTERVAL=30     # minutes
REJOIN_INTERVAL=15          # seconds
MAX_FAILS=3                 # fails before skipping a link
LAUNCH_DELAY=30             # seconds between clone launches
HOP_INTERVAL=480            # seconds (8 min default)
AUTO_KILL=1                 # 1=ON, 0=OFF

# ── GLOBAL STATE ─────────────────────────────────────────────────────
declare -a LINKS=()
declare -a GAME_IDS=()
declare -a LINK_CODES=()
declare -a NODES=()
declare -a NODE_PIDS=()
declare -a NODE_PTRS=()
declare -a NODE_STATUS=()
declare -a NODE_FAILS=()
declare -a NODE_NEXT_HOP=()
TOTAL_HOPS=0
TOTAL_FAILS=0
LAST_CACHE_CLEAR=$(date +%s)
NEXT_CACHE_CLEAR_TS=0
DISTRIBUTION_MODE=1   # 1=Converge 2=Diverge
SCREEN_W=0
SCREEN_H=0

# ── COLORS ───────────────────────────────────────────────────────────
R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
VIOLET=$'\033[38;5;135m'
DUST=$'\033[38;5;183m'
ROSE=$'\033[38;5;211m'
GREEN=$'\033[38;5;114m'
RED=$'\033[38;5;203m'
YELLOW=$'\033[38;5;222m'
GRAY=$'\033[38;5;242m'
CYAN=$'\033[38;5;117m'
WHITE=$'\033[97m'

# ════════════════════════════════════════════════════════════════════
#  TUI ENGINE
# ════════════════════════════════════════════════════════════════════

tui_init() {
  tput civis 2>/dev/null || true
  stty -echo 2>/dev/null || true
}

tui_restore() {
  tput cvvis 2>/dev/null || true
  stty echo 2>/dev/null || true
  echo ""
}

tui_clear() { tput clear 2>/dev/null || printf '\033[2J\033[H'; }

# Print at row col with max width enforcement
at() {
  local row=$1 col=$2
  shift 2
  local text="$*"
  # Truncate to MAX_LINE_WIDTH
  text="${text:0:$MAX_LINE_WIDTH}"
  tput cup "$row" "$col"
  printf '%s' "$text"
}

# Print a horizontal line
hline() {
  local row=$1 char="${2:-─}" len="${3:-$MAX_LINE_WIDTH}"
  tput cup "$row" 0
  printf '%*s' "$len" '' | tr ' ' "$char"
}

# ════════════════════════════════════════════════════════════════════
#  ASCII ART HEADER
# ════════════════════════════════════════════════════════════════════

draw_header() {
  local row="${1:-0}"
  printf '%s%s' "$VIOLET" "$BOLD"
  at $((row+0)) 0 "  ████████╗██╗  ██╗███████╗    ███████╗ ██████╗  ██████╗ ██╗     "
  at $((row+1)) 0 "     ██╔══╝██║  ██║██╔════╝    ██╔════╝██╔═══██╗██╔═══██╗██║     "
  at $((row+2)) 0 "     ██║   ███████║█████╗      █████╗  ██║   ██║██║   ██║██║     "
  at $((row+3)) 0 "     ██║   ██╔══██║██╔══╝      ██╔══╝  ██║   ██║██║   ██║██║     "
  at $((row+4)) 0 "     ██║   ██║  ██║███████╗    ██║     ╚██████╔╝╚██████╔╝███████╗"
  at $((row+5)) 0 "     ╚═╝   ╚═╝  ╚═╝╚══════╝    ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝"
  printf '%s' "$R"
  at $((row+6)) 0 "$(printf '%s%s%s' "$GRAY" "  v${VERSION}  ·  Saturnity  ·  Private Server Hopper" "$R")"
}

# ════════════════════════════════════════════════════════════════════
#  SELF-UPDATE
# ════════════════════════════════════════════════════════════════════

check_update() {
  tui_clear
  draw_header 0
  at 9 0 "${GRAY}  Checking for updates...${R}"

  local tmp="/tmp/fool_update_$$.sh"
  if ! curl -sf --max-time 8 "$GITHUB_RAW_URL" -o "$tmp" 2>/dev/null; then
    at 10 0 "${YELLOW}  ⚠  Could not reach update server. Continuing offline.${R}"
    sleep 1
    return
  fi

  local remote_ver
  remote_ver=$(grep -m1 'readonly VERSION=' "$tmp" 2>/dev/null | cut -d'"' -f2 || echo "")
  local local_hash remote_hash
  local_hash=$(sha256sum "$SELF_PATH" 2>/dev/null | awk '{print $1}' || echo "")
  remote_hash=$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}' || echo "")

  if [[ -n "$remote_ver" && "$local_hash" != "$remote_hash" ]]; then
    at 10 0 "${DUST}  ↑  Update available: ${remote_ver}. Installing...${R}"
    sleep 1
    mv "$tmp" "$SELF_PATH"
    chmod +x "$SELF_PATH"
    at 11 0 "${GREEN}  ✓  Updated. Relaunching...${R}"
    sleep 1
    exec "$SELF_PATH" "$@"
  else
    at 10 0 "${GREEN}  ✓  Up to date (v${VERSION})${R}"
    rm -f "$tmp"
    sleep 0.5
  fi
}

# ════════════════════════════════════════════════════════════════════
#  DATA LAYER — FETCH LINKS
# ════════════════════════════════════════════════════════════════════

fetch_links() {
  local silent="${1:-0}"
  if [[ "$silent" == "0" ]]; then
    at 10 0 "${GRAY}  Synchronizing with Universe Vault...${R}"
  fi

  local response
  response=$(curl -sf --max-time 10 \
    -H "x-fool-auth: ${API_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    "$API_ENDPOINT" 2>/dev/null) || {
    if [[ "$silent" == "0" ]]; then
      at 10 0 "${RED}  ✗  Failed to reach Universe Vault. Check connection.${R}"
    fi
    return 1
  }

  # Parse with jq: extract fullUrl, gameId, linkCode arrays
  LINKS=()
  GAME_IDS=()
  LINK_CODES=()

  local count
  count=$(echo "$response" | jq -r '. | length' 2>/dev/null || echo 0)

  if [[ "$count" -eq 0 ]]; then
    if [[ "$silent" == "0" ]]; then
      at 10 0 "${YELLOW}  ⚠  Vault returned 0 links. Add links via the dashboard.${R}"
    fi
    return 0
  fi

  while IFS=$'\t' read -r url gid code; do
    LINKS+=("$url")
    GAME_IDS+=("$gid")
    LINK_CODES+=("$code")
  done < <(echo "$response" | jq -r '.[] | [.fullUrl, .gameId, .linkCode] | @tsv' 2>/dev/null)

  if [[ "$silent" == "0" ]]; then
    at 10 0 "${GREEN}  ✓  Synchronized. Retrieved ${#LINKS[@]} private server links from the Universe.${R}"
  fi
  return 0
}

# ════════════════════════════════════════════════════════════════════
#  SCREEN 1 — BOOT & SYNC
# ════════════════════════════════════════════════════════════════════

screen_boot() {
  tui_clear
  draw_header 0
  hline 8 "─" 70
  at 9 0 "${DUST}  ◈  Initializing systems...${R}"

  mkdir -p "$STATE_DIR"

  check_update

  tui_clear
  draw_header 0
  hline 8 "─" 70
  at 9 0 "${DUST}  ◈  Connecting to Universe Vault...${R}"

  if ! fetch_links 0; then
    at 12 0 "${YELLOW}  Press any key to retry, or [q] to exit.${R}"
    read -r -n1 key
    if [[ "$key" == "q" ]]; then cleanup; fi
    screen_boot
    return
  fi

  at 12 0 "${GRAY}  Press any key to continue...${R}"
  read -r -n1
}

# ════════════════════════════════════════════════════════════════════
#  SCREEN 2 — CHOOSE THE ARMY
# ════════════════════════════════════════════════════════════════════

screen_army() {
  NODES=()
  local packages=()

  while true; do
    tui_clear
    draw_header 0
    hline 8 "─" 70
    at 9  0 "${DUST}${BOLD}  ◈  CHOOSE THE ARMY — Node Configuration${R}"
    at 11 0 "${WHITE}  Enter base package name ${GRAY}(e.g. com.roblox, com.delta)${R}${WHITE}:${R} "
    tput cup 11 50
    tput cnorm
    local input=""
    read -r input
    tput civis

    if [[ -z "$input" ]]; then continue; fi

    at 13 0 "${GRAY}  Scanning packages...${R}"
    mapfile -t packages < <(pm list packages 2>/dev/null | grep "$input" | sed 's/^package://' | sort)

    if [[ ${#packages[@]} -eq 0 ]]; then
      at 14 0 "${RED}  ✗  No packages matched '${input}'. Try again.${R}"
      sleep 1.5
      continue
    fi

    tput cup 13 0
    printf '%s' "${GRAY}  Found ${#packages[@]} package(s):${R}"
    local i
    for i in "${!packages[@]}"; do
      at $((14+i)) 2 "${VIOLET}[$((i+1))]${R} ${packages[$i]}"
    done

    local sel_row=$((14 + ${#packages[@]} + 1))
    at "$sel_row" 0 "${WHITE}  Select clones to bind ${GRAY}[1 2 3 4 / all]${R}${WHITE}:${R} "
    tput cup "$sel_row" 45
    tput cnorm
    local selection=""
    read -r selection
    tput civis

    NODES=()
    if [[ "$selection" == "all" ]]; then
      NODES=("${packages[@]}")
    else
      for tok in $selection; do
        local idx=$((tok - 1))
        if [[ "$idx" -ge 0 && "$idx" -lt "${#packages[@]}" ]]; then
          NODES+=("${packages[$idx]}")
        fi
      done
    fi

    if [[ ${#NODES[@]} -eq 0 ]]; then
      at $((sel_row+1)) 0 "${RED}  ✗  No valid selection. Try again.${R}"
      sleep 1.2
      continue
    fi

    at $((sel_row+2)) 0 "${GREEN}  ✓  ${#NODES[@]} node(s) selected.${R}"
    sleep 0.8
    break
  done
}

# ════════════════════════════════════════════════════════════════════
#  SCREEN 3 — CHOOSE THE UNIVERSE
# ════════════════════════════════════════════════════════════════════

get_screen_dims() {
  local size
  size=$(wm size 2>/dev/null | grep -oP '\d+x\d+' | tail -1)
  SCREEN_W=$(echo "$size" | cut -dx -f1)
  SCREEN_H=$(echo "$size" | cut -dx -f2)
  # Fallback
  [[ -z "$SCREEN_W" || "$SCREEN_W" -eq 0 ]] && SCREEN_W=2160
  [[ -z "$SCREEN_H" || "$SCREEN_H" -eq 0 ]] && SCREEN_H=1440
}

calculate_bounds() {
  # Args: node_index (0-3)
  # Returns: L T R B as space-separated string
  local idx=$1
  local half_w=$((SCREEN_W / 2))
  local half_h=$((SCREEN_H / 2))
  case $idx in
    0) echo "0 0 $half_w $half_h" ;;
    1) echo "$half_w 0 $SCREEN_W $half_h" ;;
    2) echo "0 $half_h $half_w $SCREEN_H" ;;
    3) echo "$half_w $half_h $SCREEN_W $SCREEN_H" ;;
    *) echo "0 0 $half_w $half_h" ;;
  esac
}

launch_node_window() {
  # Launch a node into freeform grid cell
  local idx=$1 pkg=$2
  local bounds
  bounds=$(calculate_bounds "$idx")
  read -r L T R_b B <<< "$bounds"
  su -c "settings put global enable_freeform_support 1" 2>/dev/null || true
  su -c "am start --windowingMode 5 --bounds [${L},${T},${R_b},${B}] -n ${pkg}/com.roblox.client.startup.ActivityNativeMain" 2>/dev/null || \
  su -c "am start --windowingMode 5 --bounds [${L},${T},${R_b},${B}] ${pkg}" 2>/dev/null || true
}

screen_universe() {
  get_screen_dims

  while true; do
    tui_clear
    draw_header 0
    hline 8 "─" 70
    at 9  0 "${DUST}${BOLD}  ◈  CHOOSE THE UNIVERSE — Strategy & Layout${R}"
    at 11 0 "${WHITE}  Screen: ${SCREEN_W}×${SCREEN_H}  ·  Nodes: ${#NODES[@]}  ·  Links: ${#LINKS[@]}${R}"
    at 13 0 "${VIOLET}  Distribution Mode:${R}"
    at 14 2 "${GRAY}[1]${R} ${WHITE}Converge${R} ${GRAY}— all nodes iterate the same full link array${R}"
    at 15 2 "${GRAY}[2]${R} ${WHITE}Diverge${R}  ${GRAY}— split links into equal chunks per node${R}"
    at 17 0 "${VIOLET}  Actions:${R}"
    at 18 2 "${GRAY}[F]${R} Re-fetch links from API"
    at 19 2 "${GRAY}[T]${R} Test Grid — launch all nodes to Roblox home (staggered 15s)"
    at 20 2 "${GRAY}[↵]${R} ${WHITE}Continue to Command Center${R}"
    at 22 0 "${GREEN}  Current mode: $([ $DISTRIBUTION_MODE -eq 1 ] && echo 'CONVERGE' || echo 'DIVERGE')${R}"

    at 24 0 "${WHITE}  Choice:${R} "
    tput cup 24 11
    tput cnorm
    local key=""
    read -r -n1 key
    tput civis
    key="${key,,}"

    case "$key" in
      1) DISTRIBUTION_MODE=1 ;;
      2) DISTRIBUTION_MODE=2 ;;
      f|F)
        at 24 0 "${GRAY}  Re-fetching...                    ${R}"
        fetch_links 1
        at 24 0 "${GREEN}  ✓  ${#LINKS[@]} links loaded.           ${R}"
        sleep 1 ;;
      t|T)
        at 24 0 "${DUST}  Launching test grid...            ${R}"
        local ni
        for ni in "${!NODES[@]}"; do
          [[ $ni -ge 4 ]] && break
          launch_node_window "$ni" "${NODES[$ni]}"
          sleep 15
        done
        at 24 0 "${GREEN}  ✓  Test grid launched.             ${R}"
        sleep 1 ;;
      "" | " ") break ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════════════
#  SCREEN 4 — MAIN LOBBY / COMMAND CENTER
# ════════════════════════════════════════════════════════════════════

fmt_toggle() { [[ $1 -eq 1 ]] && echo "${GREEN}ON${R}" || echo "${RED}OFF${R}"; }
fmt_min() { echo "${1}min"; }
fmt_sec() { echo "${1}s"; }

screen_lobby() {
  while true; do
    tui_clear
    draw_header 0
    hline 8 "─" 70
    at 9  0 "${DUST}${BOLD}  ◈  COMMAND CENTER${R}                  ${GRAY}Nodes: ${#NODES[@]}  Links: ${#LINKS[@]}  Mode: $([ $DISTRIBUTION_MODE -eq 1 ] && echo CONVERGE || echo DIVERGE)${R}"
    hline 10 "─" 70

    at 11 0 "${VIOLET}  CONFIG${R}"
    at 12 2 "${GRAY}[a]${R} Cache clear interval    ${DUST}$(fmt_min $CACHE_CLEAR_INTERVAL)${R}"
    at 13 2 "${GRAY}[b]${R} Rejoin interval         ${DUST}$(fmt_sec $REJOIN_INTERVAL)${R}"
    at 14 2 "${GRAY}[c]${R} Max fails per link      ${DUST}${MAX_FAILS}${R}"
    at 15 2 "${GRAY}[d]${R} Launch delay per clone  ${DUST}$(fmt_sec $LAUNCH_DELAY)${R}"
    at 16 2 "${GRAY}[e]${R} Hop interval            ${DUST}$(fmt_sec $HOP_INTERVAL)${R}"
    at 17 2 "${GRAY}[f]${R} Auto-Kill               $(fmt_toggle $AUTO_KILL)"

    hline 18 "─" 70
    at 19 0 "${VIOLET}  ACTIONS${R}"
    at 20 2 "${GRAY}[1]${R} ${WHITE}${BOLD}Release The Fool${R}     — start hopping"
    at 21 2 "${GRAY}[2]${R} Expand The Universe  — back to strategy"
    at 22 2 "${GRAY}[3]${R} Rally The Army       — back to node select"
    at 23 2 "${GRAY}[0]${R} ${RED}Kill The Fool${R}        — exit"
    hline 24 "─" 70
    at 25 0 "${WHITE}  Command:${R} "
    tput cup 25 12
    tput cnorm
    local key=""
    read -r -n1 key
    tput civis

    case "$key" in
      a)
        tput cup 25 0; printf '  Cache clear (5-60 min): '; tput cnorm
        read -r val; tput civis
        if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= 5 && val <= 60 )); then
          CACHE_CLEAR_INTERVAL=$val; fi ;;
      b)
        tput cup 25 0; printf '  Rejoin interval (sec): '; tput cnorm
        read -r val; tput civis
        if [[ "$val" =~ ^[0-9]+$ ]]; then REJOIN_INTERVAL=$val; fi ;;
      c)
        tput cup 25 0; printf '  Max fails: '; tput cnorm
        read -r val; tput civis
        if [[ "$val" =~ ^[0-9]+$ ]]; then MAX_FAILS=$val; fi ;;
      d)
        tput cup 25 0; printf '  Launch delay (15-120s): '; tput cnorm
        read -r val; tput civis
        if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= 15 && val <= 120 )); then
          LAUNCH_DELAY=$val; fi ;;
      e)
        tput cup 25 0; printf '  Hop interval (180-900s): '; tput cnorm
        read -r val; tput civis
        if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= 180 && val <= 900 )); then
          HOP_INTERVAL=$val; fi ;;
      f) AUTO_KILL=$(( 1 - AUTO_KILL )) ;;
      1) screen_journey; ;;
      2) screen_universe ;;
      3) screen_army; screen_universe ;;
      0) cleanup ;;
    esac
  done
}

# ════════════════════════════════════════════════════════════════════
#  NODE LOOP — runs as background job per node
# ════════════════════════════════════════════════════════════════════

node_loop() {
  local node_idx=$1
  local pkg=$2
  local -a my_links=()
  local -a my_gids=()
  local -a my_codes=()
  local ptr=0
  local total_hops=0
  local consecutive_fails=0

  # Build this node's link subset
  if [[ $DISTRIBUTION_MODE -eq 1 ]]; then
    my_links=("${LINKS[@]}")
    my_gids=("${GAME_IDS[@]}")
    my_codes=("${LINK_CODES[@]}")
  else
    # Diverge: split array into chunks
    local total=${#LINKS[@]}
    local node_count=${#NODES[@]}
    local chunk=$(( (total + node_count - 1) / node_count ))
    local start=$(( node_idx * chunk ))
    local end=$(( start + chunk ))
    [[ $end -gt $total ]] && end=$total
    local i
    for (( i=start; i<end; i++ )); do
      my_links+=("${LINKS[$i]}")
      my_gids+=("${GAME_IDS[$i]}")
      my_codes+=("${LINK_CODES[$i]}")
    done
  fi

  local total_my=${#my_links[@]}
  if [[ $total_my -eq 0 ]]; then
    echo "IDLE" > "${STATE_DIR}/node_${node_idx}.status"
    return
  fi

  # Restore pointer if state exists
  if [[ -f "${STATE_DIR}/node_${node_idx}.ptr" ]]; then
    ptr=$(cat "${STATE_DIR}/node_${node_idx}.ptr")
    ptr=$(( ptr % total_my ))
  fi

  local last_cache_clear=$(date +%s)

  while true; do
    # Wrap pointer
    ptr=$(( ptr % total_my ))
    local url="${my_links[$ptr]}"
    local gid="${my_gids[$ptr]}"
    local code="${my_codes[$ptr]}"
    local next_hop=$(( $(date +%s) + HOP_INTERVAL ))

    # Write state for dashboard
    echo "LAUNCHING" > "${STATE_DIR}/node_${node_idx}.status"
    echo "$pkg" > "${STATE_DIR}/node_${node_idx}.pkg"
    echo "${ptr}/${total_my}" > "${STATE_DIR}/node_${node_idx}.progress"
    echo "$next_hop" > "${STATE_DIR}/node_${node_idx}.nexthop"
    echo "$total_hops" > "${STATE_DIR}/node_${node_idx}.hops"
    echo "$consecutive_fails" > "${STATE_DIR}/node_${node_idx}.fails"
    echo "$ptr" > "${STATE_DIR}/node_${node_idx}.ptr"

    # Launch deep link
    su -c "am start -a android.intent.action.VIEW -d 'roblox://placeId=${gid}&linkCode=${code}' --package ${pkg}" 2>/dev/null || \
    su -c "am start -a android.intent.action.VIEW -d 'roblox://placeId=${gid}&linkCode=${code}'" 2>/dev/null || {
      consecutive_fails=$(( consecutive_fails + 1 ))
      echo "$consecutive_fails" > "${STATE_DIR}/node_${node_idx}.fails"
      if [[ $consecutive_fails -ge $MAX_FAILS ]]; then
        echo "SKIP" > "${STATE_DIR}/node_${node_idx}.status"
        ptr=$(( ptr + 1 ))
        consecutive_fails=0
        continue
      fi
      sleep "$REJOIN_INTERVAL"
      continue
    }

    consecutive_fails=0
    total_hops=$(( total_hops + 1 ))
    echo "CONNECTED" > "${STATE_DIR}/node_${node_idx}.status"

    # Wait for hop interval, updating next_hop countdown
    while [[ $(date +%s) -lt $next_hop ]]; do
      echo "$next_hop" > "${STATE_DIR}/node_${node_idx}.nexthop"
      sleep 5
      # Check for skip signal
      if [[ -f "${STATE_DIR}/node_${node_idx}.skip" ]]; then
        rm -f "${STATE_DIR}/node_${node_idx}.skip"
        break
      fi
    done

    echo "HOPPING" > "${STATE_DIR}/node_${node_idx}.status"

    # Auto-kill before hop
    if [[ $AUTO_KILL -eq 1 ]]; then
      su -c "am force-stop ${pkg}" 2>/dev/null || true
      sleep 2
    fi

    # Cache clear check
    local now=$(date +%s)
    local cache_elapsed=$(( (now - last_cache_clear) / 60 ))
    if [[ $cache_elapsed -ge $CACHE_CLEAR_INTERVAL ]]; then
      su -c "pm clear ${pkg}" 2>/dev/null || true
      last_cache_clear=$now
      echo "CACHE CLEAR" > "${STATE_DIR}/node_${node_idx}.status"
      sleep 3
    fi

    # Advance pointer
    ptr=$(( ptr + 1 ))
  done
}

# ════════════════════════════════════════════════════════════════════
#  SCREEN 5 — THE JOURNEY (LIVE DASHBOARD)
# ════════════════════════════════════════════════════════════════════

init_nodes() {
  NODE_PIDS=()
  NODE_STATUS=()
  NODE_PTRS=()
  NODE_FAILS=()
  NODE_NEXT_HOP=()

  # Initialize per-node state files
  local i
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local pkg="${NODES[$i]}"
    rm -f "${STATE_DIR}/node_${i}.skip"
    echo "INIT" > "${STATE_DIR}/node_${i}.status"
    echo "0" > "${STATE_DIR}/node_${i}.ptr"
    echo "0" > "${STATE_DIR}/node_${i}.hops"
    echo "0" > "${STATE_DIR}/node_${i}.fails"
    echo "0" > "${STATE_DIR}/node_${i}.nexthop"
    echo "0/0" > "${STATE_DIR}/node_${i}.progress"
    echo "$pkg" > "${STATE_DIR}/node_${i}.pkg"

    # Launch into freeform grid
    launch_node_window "$i" "$pkg"
    sleep "$LAUNCH_DELAY"

    # Start background loop
    node_loop "$i" "$pkg" &
    NODE_PIDS+=($!)
  done
}

read_node_state() {
  local i=$1
  local status="?" pkg="?" progress="0/0" next_hop="0" hops="0" fails="0"
  [[ -f "${STATE_DIR}/node_${i}.status" ]]   && status=$(cat "${STATE_DIR}/node_${i}.status")
  [[ -f "${STATE_DIR}/node_${i}.pkg" ]]      && pkg=$(cat "${STATE_DIR}/node_${i}.pkg")
  [[ -f "${STATE_DIR}/node_${i}.progress" ]] && progress=$(cat "${STATE_DIR}/node_${i}.progress")
  [[ -f "${STATE_DIR}/node_${i}.nexthop" ]]  && next_hop=$(cat "${STATE_DIR}/node_${i}.nexthop")
  [[ -f "${STATE_DIR}/node_${i}.hops" ]]     && hops=$(cat "${STATE_DIR}/node_${i}.hops")
  [[ -f "${STATE_DIR}/node_${i}.fails" ]]    && fails=$(cat "${STATE_DIR}/node_${i}.fails")
  echo "$status|$pkg|$progress|$next_hop|$hops|$fails"
}

fmt_countdown() {
  local target=$1 now=$(date +%s)
  local remaining=$(( target - now ))
  [[ $remaining -lt 0 ]] && remaining=0
  printf '%02d:%02d' $(( remaining / 60 )) $(( remaining % 60 ))
}

fmt_status_color() {
  case "$1" in
    CONNECTED)   echo "${GREEN}" ;;
    HOPPING)     echo "${YELLOW}" ;;
    CACHE*)      echo "${CYAN}" ;;
    SKIP)        echo "${RED}" ;;
    LAUNCHING)   echo "${DUST}" ;;
    *)           echo "${GRAY}" ;;
  esac
}

cache_clear_countdown() {
  local now=$(date +%s)
  local elapsed=$(( now - LAST_CACHE_CLEAR ))
  local remaining=$(( (CACHE_CLEAR_INTERVAL * 60) - elapsed ))
  [[ $remaining -lt 0 ]] && remaining=0
  printf '%02d:%02d' $(( remaining / 60 )) $(( remaining % 60 ))
}

render_journey() {
  local row=0
  tput cup 0 0

  # Header
  at $((row)) 0 "${VIOLET}${BOLD}  ◈  THE JOURNEY  ${R}${GRAY}v${VERSION}  ·  $(date '+%H:%M:%S')${R}"
  hline $((row+1)) "─" 70

  # Global stats
  local total_hops_all=0 total_fails_all=0
  local i
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local h=0 f=0
    [[ -f "${STATE_DIR}/node_${i}.hops" ]]  && h=$(cat "${STATE_DIR}/node_${i}.hops")
    [[ -f "${STATE_DIR}/node_${i}.fails" ]] && f=$(cat "${STATE_DIR}/node_${i}.fails")
    total_hops_all=$(( total_hops_all + h ))
    total_fails_all=$(( total_fails_all + f ))
  done

  local cc_str
  cc_str=$(cache_clear_countdown)
  printf '%s' "$(tput cup $((row+2)) 0)"
  printf '  %s%-12s%s  Hops: %s%-6s%s  Fails: %s%-6s%s  Cache clear in: %s%s%s' \
    "$DUST" "GLOBAL" "$R" \
    "$GREEN" "$total_hops_all" "$R" \
    "$RED" "$total_fails_all" "$R" \
    "$YELLOW" "$cc_str" "$R"

  hline $((row+3)) "─" 70

  # Per-node rows
  local node_row=$((row+4))
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    IFS='|' read -r status pkg progress next_hop hops fails <<< "$(read_node_state $i)"

    # Short package name
    local short_pkg="${pkg##*.}"
    short_pkg="${short_pkg:0:10}"
    local full_label="N$((i+1)) — ${short_pkg}"
    local countdown
    countdown=$(fmt_countdown "$next_hop")
    local sc
    sc=$(fmt_status_color "$status")

    printf '%s' "$(tput cup $((node_row + i)) 0)"
    printf '  %s[ %-14s]%s  %s%-8s%s  %s%-12s%s  ──  %s%s until next hop%s' \
      "$VIOLET" "$full_label" "$R" \
      "$GRAY" "$progress" "$R" \
      "$sc" "$status" "$R" \
      "$GRAY" "$countdown" "$R" \
      "" "" ""
  done

  hline $((node_row + ${#NODES[@]} + 1)) "─" 70
  local ctrl_row=$(( node_row + ${#NODES[@]} + 2 ))
  at "$ctrl_row" 0 "${GRAY}  [q] Return to lobby   [s#] Skip node (e.g. s2)${R}"

  # Ensure max 25 lines visible
  local last_line=$(( ctrl_row + 1 ))
  if [[ $last_line -lt 25 ]]; then
    tput cup $((last_line+1)) 0
  fi
}

manual_skip() {
  local node_idx=$1
  if [[ $node_idx -ge 0 && $node_idx -lt ${#NODES[@]} ]]; then
    touch "${STATE_DIR}/node_${node_idx}.skip"
  fi
}

screen_journey() {
  tui_clear
  at 5 0 "${DUST}  ◈  Initializing The Fool — deploying nodes...${R}"

  init_nodes

  tui_clear

  local NEXT_REDRAW=$(( $(date +%s) + 30 ))

  while true; do
    local now=$(date +%s)

    # Redraw on interval
    if [[ $now -ge $NEXT_REDRAW ]]; then
      render_journey
      NEXT_REDRAW=$(( now + 30 ))
    fi

    # Non-blocking input (1s timeout, 2 chars)
    local key=""
    if read -r -t 1 -n 2 key 2>/dev/null; then
      key="${key,,}"
      if [[ "$key" == "q" ]]; then
        # Kill all node background PIDs
        for pid in "${NODE_PIDS[@]}"; do
          kill "$pid" 2>/dev/null || true
        done
        NODE_PIDS=()
        # Return to lobby
        screen_lobby
        return
      elif [[ "$key" =~ ^s([0-9])$ ]]; then
        local node_idx=$(( ${BASH_REMATCH[1]} - 1 ))
        manual_skip "$node_idx"
      fi
    fi
  done
}

# ════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ════════════════════════════════════════════════════════════════════

cleanup() {
  # Kill all background node loops
  if [[ ${#NODE_PIDS[@]} -gt 0 ]]; then
    for pid in "${NODE_PIDS[@]}"; do
      kill "$pid" 2>/dev/null || true
    done
  fi
  # Kill any stray background jobs
  jobs -p | xargs -r kill 2>/dev/null || true
  # Clean state dir
  rm -rf "$STATE_DIR" 2>/dev/null || true
  tui_restore
  printf '\n%s%s◈  The Fool has returned from the journey.%s\n\n' "$VIOLET" "$BOLD" "$R"
  exit 0
}

trap 'cleanup' SIGINT SIGTERM EXIT

# ════════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════════

main() {
  # Dependency check
  local missing=()
  for cmd in curl jq tput su; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%s[THE FOOL] Missing dependencies: %s%s\n' "$RED" "${missing[*]}" "$R"
    printf 'Install via: pkg install %s\n' "${missing[*]}"
    exit 1
  fi

  tui_init
  screen_boot
  screen_army
  screen_universe
  screen_lobby
}

main "$@"
