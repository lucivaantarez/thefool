#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  THE FOOL -- Roblox Private Server Hopper
#  Version: 1.0.0  |  Author: Saturnity
# ════════════════════════════════════════════════════════════════════

set -uo pipefail

# -- CONSTANTS -------------------------------------------------------
readonly VERSION="1.0.0"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/lucivaantarez/thefool/main/the_fool.sh"
readonly API_ENDPOINT="https://universe-vault.vercel.app/api/links"
readonly API_AUTH_TOKEN="fool-secret-token-2025"
readonly SELF_PATH="$(realpath "$0")"
readonly STATE_DIR="${HOME}/.fool_state"
readonly MAX_LINE_WIDTH=60

# -- CONFIG ----------------------------------------------------------
CACHE_CLEAR_INTERVAL=30
REJOIN_INTERVAL=15
MAX_FAILS=3
LAUNCH_DELAY=30
HOP_INTERVAL=480
AUTO_KILL=1

# -- GLOBAL STATE ----------------------------------------------------
declare -a LINKS=()
declare -a GAME_IDS=()
declare -a LINK_CODES=()
declare -a NODES=()
declare -a NODE_PIDS=()
TOTAL_HOPS=0
TOTAL_FAILS=0
LAST_CACHE_CLEAR=$(date +%s)
DISTRIBUTION_MODE=1
SCREEN_W=2160
SCREEN_H=1440

# -- COLORS ----------------------------------------------------------
R=$'\033[0m'
BOLD=$'\033[1m'
VIOLET=$'\033[38;5;135m'
DUST=$'\033[38;5;183m'
GREEN=$'\033[38;5;114m'
RED=$'\033[38;5;203m'
YELLOW=$'\033[38;5;222m'
GRAY=$'\033[38;5;242m'
WHITE=$'\033[97m'

# ====================================================================
#  TUI ENGINE
# ====================================================================

tui_init() { stty sane 2>/dev/null || true; }
tui_restore() { stty sane 2>/dev/null || true; printf '\n'; }
tui_clear() { tput clear 2>/dev/null || printf '\033[2J\033[H'; }

# Move cursor to row,col and print (ASCII safe)
at() {
  local row=$1 col=$2; shift 2
  local text="${*:0:$MAX_LINE_WIDTH}"
  tput cup "$row" "$col" 2>/dev/null || true
  printf '%s' "$text"
}

hline() {
  local row=$1 len="${2:-58}"
  tput cup "$row" 0 2>/dev/null || true
  printf '%0.s-' $(seq 1 $len)
}

# ====================================================================
#  ASCII HEADER (pure ASCII, no box-drawing chars)
# ====================================================================

draw_header() {
  local r="${1:-0}"
  printf '%s%s' "$VIOLET" "$BOLD"
  at $((r+0)) 0 " _____ _   _ _____   _____ ___  ___  _     "
  at $((r+1)) 0 "|_   _| | | |  ___| |  ___/ _ \ / _ \| |    "
  at $((r+2)) 0 "  | | | |_| | |__   | |_ | | | | | | | |    "
  at $((r+3)) 0 "  | | |  _  |  __|  |  _|| | | | | | | |    "
  at $((r+4)) 0 "  | | | | | | |___  | |  \ \_/ / \_/ / |____"
  at $((r+5)) 0 "  \_/ \_| |_/\____/ \_|   \___/ \___/\_____/"
  printf '%s' "$R"
  at $((r+6)) 0 "${GRAY}  v${VERSION}  Saturnity  Private Server Hopper${R}"
}

# ====================================================================
#  SELF-UPDATE
# ====================================================================

check_update() {
  tui_clear; draw_header 0; hline 8
  at 9 0 "${GRAY}  Checking for updates...${R}"
  local tmp="${HOME}/.fool_update_$$.sh"
  if ! curl -sf --max-time 8 "$GITHUB_RAW_URL" -o "$tmp" 2>/dev/null; then
    at 10 0 "${YELLOW}  Could not reach update server. Continuing offline.${R}"
    sleep 1; return
  fi
  local lh rh
  lh=$(sha256sum "$SELF_PATH" 2>/dev/null | awk '{print $1}' || echo "")
  rh=$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}' || echo "")
  if [[ -n "$rh" && "$lh" != "$rh" ]]; then
    at 10 0 "${DUST}  Update found. Installing...${R}"
    sleep 1; mv "$tmp" "$SELF_PATH"; chmod +x "$SELF_PATH"
    at 11 0 "${GREEN}  Updated. Relaunching...${R}"; sleep 1
    exec "$SELF_PATH" "$@"
  else
    at 10 0 "${GREEN}  Up to date (v${VERSION})${R}"
    rm -f "$tmp"; sleep 0.5
  fi
}

# ====================================================================
#  DATA LAYER
# ====================================================================

fetch_links() {
  local silent="${1:-0}"
  [[ "$silent" == "0" ]] && at 10 0 "${GRAY}  Connecting to Universe Vault...${R}"
  local response
  response=$(curl -sf --max-time 10 \
    -H "x-fool-auth: ${API_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_ENDPOINT}" 2>/dev/null) || {
    [[ "$silent" == "0" ]] && at 10 0 "${RED}  Failed to reach Universe Vault.${R}"
    return 1
  }
  LINKS=(); GAME_IDS=(); LINK_CODES=()
  local count
  count=$(printf '%s' "$response" | jq -r '. | length' 2>/dev/null || echo 0)
  if [[ "$count" -eq 0 ]]; then
    [[ "$silent" == "0" ]] && at 10 0 "${YELLOW}  Vault returned 0 links.${R}"
    return 0
  fi
  while IFS=$'\t' read -r url gid code; do
    LINKS+=("$url"); GAME_IDS+=("$gid"); LINK_CODES+=("$code")
  done < <(printf '%s' "$response" | jq -r '.[] | [.fullUrl, .gameId, .linkCode] | @tsv' 2>/dev/null)
  [[ "$silent" == "0" ]] && at 10 0 "${GREEN}  Retrieved ${#LINKS[@]} links from the Universe.${R}"
  return 0
}

# ====================================================================
#  SCREEN 1 -- BOOT
# ====================================================================

screen_boot() {
  tui_clear; draw_header 0; hline 8
  at 9 0 "${DUST}  Initializing...${R}"
  mkdir -p "$STATE_DIR"
  check_update
  tui_clear; draw_header 0; hline 8
  at 9 0 "${DUST}  Connecting to Universe Vault...${R}"
  if ! fetch_links 0; then
    at 12 0 "${YELLOW}  Press any key to retry, [q] to exit.${R}"
    local k; read -r -n1 k
    [[ "$k" == "q" ]] && cleanup
    screen_boot; return
  fi
  at 12 0 "${GRAY}  Press any key to continue...${R}"
  read -r -n1
}

# ====================================================================
#  SCREEN 2 -- CHOOSE THE ARMY
# ====================================================================

screen_army() {
  NODES=()
  local packages=()
  while true; do
    tui_clear; draw_header 0; hline 8
    at 9  0 "${DUST}${BOLD}  CHOOSE THE ARMY -- Node Configuration${R}"
    at 11 0 "${WHITE}  Package name (e.g. com.roblox, com.delta):${R}"
    at 12 0 "  > "
    tput cup 12 4 2>/dev/null || true
    stty sane 2>/dev/null || true
    local input=""
    read -r input
    [[ -z "$input" ]] && continue
    at 14 0 "${GRAY}  Scanning...${R}"
    mapfile -t packages < <(pm list packages 2>/dev/null | grep "$input" | sed 's/^package://' | sort)
    if [[ ${#packages[@]} -eq 0 ]]; then
      at 15 0 "${RED}  No packages matched. Try again.${R}"
      sleep 1.5; continue
    fi
    tput cup 14 0 2>/dev/null || true
    printf '%s' "${GRAY}  Found ${#packages[@]} package(s):${R}"
    local i
    for i in "${!packages[@]}"; do
      at $((15+i)) 2 "${VIOLET}[$((i+1))]${R} ${packages[$i]}"
    done
    local sel_row=$((15 + ${#packages[@]} + 1))
    at "$sel_row" 0 "${WHITE}  Select nodes [1 2 3 / all]:${R}"
    at $((sel_row+1)) 0 "  > "
    tput cup $((sel_row+1)) 4 2>/dev/null || true
    stty sane 2>/dev/null || true
    local selection=""
    read -r selection
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
      at $((sel_row+2)) 0 "${RED}  No valid selection. Try again.${R}"
      sleep 1.2; continue
    fi
    at $((sel_row+2)) 0 "${GREEN}  ${#NODES[@]} node(s) selected.${R}"
    sleep 0.8; break
  done
}

# ====================================================================
#  SCREEN 3 -- CHOOSE THE UNIVERSE
# ====================================================================

get_screen_dims() {
  # Use wm size via su for Redfinger actual screen
  local size
  size=$(su -c "wm size" 2>/dev/null | grep -o '[0-9]*x[0-9]*' | tail -1)
  if [[ -z "$size" ]]; then
    size=$(wm size 2>/dev/null | grep -o '[0-9]*x[0-9]*' | tail -1)
  fi
  SCREEN_W=$(printf '%s' "$size" | cut -dx -f1)
  SCREEN_H=$(printf '%s' "$size" | cut -dx -f2)
  [[ -z "$SCREEN_W" || "$SCREEN_W" -eq 0 ]] && SCREEN_W=2160
  [[ -z "$SCREEN_H" || "$SCREEN_H" -eq 0 ]] && SCREEN_H=1440
}

calculate_bounds() {
  local idx=$1
  local hw=$((SCREEN_W/2)) hh=$((SCREEN_H/2))
  case $idx in
    0) echo "0 0 $hw $hh" ;;
    1) echo "$hw 0 $SCREEN_W $hh" ;;
    2) echo "0 $hh $hw $SCREEN_H" ;;
    3) echo "$hw $hh $SCREEN_W $SCREEN_H" ;;
    *) echo "0 0 $hw $hh" ;;
  esac
}

launch_node_window() {
  local idx=$1 pkg=$2
  local bounds; bounds=$(calculate_bounds "$idx")
  read -r L T R_b B <<< "$bounds"
  su -c "settings put global enable_freeform_support 1" 2>/dev/null || true
  su -c "am start --windowingMode 5 --bounds [${L},${T},${R_b},${B}] -n ${pkg}/com.roblox.client.startup.ActivityNativeMain" 2>/dev/null || \
  su -c "am start --windowingMode 5 --bounds [${L},${T},${R_b},${B}] ${pkg}" 2>/dev/null || true
}

screen_universe() {
  get_screen_dims
  while true; do
    tui_clear; draw_header 0; hline 8
    at 9  0 "${DUST}${BOLD}  CHOOSE THE UNIVERSE -- Strategy & Layout${R}"
    at 11 0 "  Screen: ${SCREEN_W}x${SCREEN_H}  Nodes: ${#NODES[@]}  Links: ${#LINKS[@]}"
    at 13 0 "${VIOLET}  Distribution Mode:${R}"
    at 14 2 "[1] Converge - all nodes use full link list"
    at 15 2 "[2] Diverge  - split list per node"
    at 17 0 "${VIOLET}  Actions:${R}"
    at 18 2 "[f] Re-fetch links from API"
    at 19 2 "[t] Test Grid (launch all nodes, 15s delay)"
    at 20 2 "[enter] Continue to Command Center"
    at 22 0 "${GREEN}  Mode: $([ $DISTRIBUTION_MODE -eq 1 ] && echo CONVERGE || echo DIVERGE)${R}"
    at 24 0 "${WHITE}  Choice:${R}"
    at 25 0 "  > "
    tput cup 25 4 2>/dev/null || true
    stty sane 2>/dev/null || true
    local key=""
    read -r -n1 key
    key="${key,,}"
    case "$key" in
      1) DISTRIBUTION_MODE=1 ;;
      2) DISTRIBUTION_MODE=2 ;;
      f)
        at 24 0 "${GRAY}  Re-fetching...                    ${R}"
        fetch_links 1
        at 24 0 "${GREEN}  ${#LINKS[@]} links loaded.           ${R}"
        sleep 1 ;;
      t)
        at 24 0 "${DUST}  Launching test grid...            ${R}"
        local ni
        for ni in "${!NODES[@]}"; do
          [[ $ni -ge 4 ]] && break
          launch_node_window "$ni" "${NODES[$ni]}"
          sleep 15
        done
        at 24 0 "${GREEN}  Test grid launched.               ${R}"
        sleep 1 ;;
      "") break ;;
    esac
  done
}

# ====================================================================
#  SCREEN 4 -- COMMAND CENTER
# ====================================================================

screen_lobby() {
  while true; do
    tui_clear; draw_header 0; hline 8
    at 9  0 "${DUST}${BOLD}  COMMAND CENTER${R}  Nodes:${#NODES[@]}  Links:${#LINKS[@]}  Mode:$([ $DISTRIBUTION_MODE -eq 1 ] && echo C || echo D)"
    hline 10
    at 11 0 "${VIOLET}  CONFIG${R}"
    at 12 2 "[a] Cache clear interval  ${DUST}${CACHE_CLEAR_INTERVAL}min${R}"
    at 13 2 "[b] Rejoin interval       ${DUST}${REJOIN_INTERVAL}s${R}"
    at 14 2 "[c] Max fails per link    ${DUST}${MAX_FAILS}${R}"
    at 15 2 "[d] Launch delay          ${DUST}${LAUNCH_DELAY}s${R}"
    at 16 2 "[e] Hop interval          ${DUST}${HOP_INTERVAL}s${R}"
    at 17 2 "[f] Auto-Kill             $([ $AUTO_KILL -eq 1 ] && printf '%s' "${GREEN}ON${R}" || printf '%s' "${RED}OFF${R}")"
    hline 18
    at 19 0 "${VIOLET}  ACTIONS${R}"
    at 20 2 "[1] RELEASE THE FOOL  -- start hopping"
    at 21 2 "[2] Expand Universe   -- back to strategy"
    at 22 2 "[3] Rally Army        -- back to node select"
    at 23 2 "[0] EXIT"
    hline 24
    at 25 0 "${WHITE}  Command:${R}"
    at 26 0 "  > "
    tput cup 26 4 2>/dev/null || true
    stty sane 2>/dev/null || true
    local key=""
    read -r -n1 key
    case "$key" in
      a) at 26 0 "  Cache clear (5-60 min): "; stty sane 2>/dev/null; local v; read -r v
         [[ "$v" =~ ^[0-9]+$ ]] && (( v>=5 && v<=60 )) && CACHE_CLEAR_INTERVAL=$v ;;
      b) at 26 0 "  Rejoin interval (sec):  "; stty sane 2>/dev/null; local v; read -r v
         [[ "$v" =~ ^[0-9]+$ ]] && REJOIN_INTERVAL=$v ;;
      c) at 26 0 "  Max fails:              "; stty sane 2>/dev/null; local v; read -r v
         [[ "$v" =~ ^[0-9]+$ ]] && MAX_FAILS=$v ;;
      d) at 26 0 "  Launch delay (15-120s): "; stty sane 2>/dev/null; local v; read -r v
         [[ "$v" =~ ^[0-9]+$ ]] && (( v>=15 && v<=120 )) && LAUNCH_DELAY=$v ;;
      e) at 26 0 "  Hop interval (180-900s):"; stty sane 2>/dev/null; local v; read -r v
         [[ "$v" =~ ^[0-9]+$ ]] && (( v>=180 && v<=900 )) && HOP_INTERVAL=$v ;;
      f) AUTO_KILL=$(( 1 - AUTO_KILL )) ;;
      1) screen_journey ;;
      2) screen_universe ;;
      3) screen_army; screen_universe ;;
      0) cleanup ;;
    esac
  done
}

# ====================================================================
#  NODE LOOP
# ====================================================================

node_loop() {
  local node_idx=$1 pkg=$2
  local -a my_links=() my_gids=() my_codes=()
  local ptr=0 total_hops=0 consecutive_fails=0

  if [[ $DISTRIBUTION_MODE -eq 1 ]]; then
    my_links=("${LINKS[@]}"); my_gids=("${GAME_IDS[@]}"); my_codes=("${LINK_CODES[@]}")
  else
    local total=${#LINKS[@]} node_count=${#NODES[@]}
    local chunk=$(( (total + node_count - 1) / node_count ))
    local start=$(( node_idx * chunk )) end=$(( node_idx * chunk + chunk ))
    [[ $end -gt $total ]] && end=$total
    local i; for (( i=start; i<end; i++ )); do
      my_links+=("${LINKS[$i]}"); my_gids+=("${GAME_IDS[$i]}"); my_codes+=("${LINK_CODES[$i]}")
    done
  fi

  local total_my=${#my_links[@]}
  [[ $total_my -eq 0 ]] && { echo "IDLE" > "${STATE_DIR}/node_${node_idx}.status"; return; }
  [[ -f "${STATE_DIR}/node_${node_idx}.ptr" ]] && { ptr=$(cat "${STATE_DIR}/node_${node_idx}.ptr"); ptr=$(( ptr % total_my )); }

  local last_cache_clear=$(date +%s)

  while true; do
    ptr=$(( ptr % total_my ))
    local gid="${my_gids[$ptr]}" code="${my_codes[$ptr]}"
    local next_hop=$(( $(date +%s) + HOP_INTERVAL ))

    echo "LAUNCHING"        > "${STATE_DIR}/node_${node_idx}.status"
    echo "$pkg"             > "${STATE_DIR}/node_${node_idx}.pkg"
    echo "${ptr}/${total_my}" > "${STATE_DIR}/node_${node_idx}.progress"
    echo "$next_hop"        > "${STATE_DIR}/node_${node_idx}.nexthop"
    echo "$total_hops"      > "${STATE_DIR}/node_${node_idx}.hops"
    echo "$consecutive_fails" > "${STATE_DIR}/node_${node_idx}.fails"
    echo "$ptr"             > "${STATE_DIR}/node_${node_idx}.ptr"

    su -c "am start -a android.intent.action.VIEW -d 'roblox://placeId=${gid}&linkCode=${code}' --package ${pkg}" 2>/dev/null || \
    su -c "am start -a android.intent.action.VIEW -d 'roblox://placeId=${gid}&linkCode=${code}'" 2>/dev/null || {
      consecutive_fails=$(( consecutive_fails + 1 ))
      echo "$consecutive_fails" > "${STATE_DIR}/node_${node_idx}.fails"
      if [[ $consecutive_fails -ge $MAX_FAILS ]]; then
        echo "SKIP" > "${STATE_DIR}/node_${node_idx}.status"
        ptr=$(( ptr + 1 )); consecutive_fails=0; continue
      fi
      sleep "$REJOIN_INTERVAL"; continue
    }

    consecutive_fails=0; total_hops=$(( total_hops + 1 ))
    echo "CONNECTED" > "${STATE_DIR}/node_${node_idx}.status"

    while [[ $(date +%s) -lt $next_hop ]]; do
      echo "$next_hop" > "${STATE_DIR}/node_${node_idx}.nexthop"
      sleep 5
      [[ -f "${STATE_DIR}/node_${node_idx}.skip" ]] && { rm -f "${STATE_DIR}/node_${node_idx}.skip"; break; }
    done

    echo "HOPPING" > "${STATE_DIR}/node_${node_idx}.status"
    [[ $AUTO_KILL -eq 1 ]] && { su -c "am force-stop ${pkg}" 2>/dev/null || true; sleep 2; }

    local now=$(date +%s)
    if (( (now - last_cache_clear) / 60 >= CACHE_CLEAR_INTERVAL )); then
      su -c "pm clear ${pkg}" 2>/dev/null || true
      last_cache_clear=$now
      echo "CACHE CLR" > "${STATE_DIR}/node_${node_idx}.status"
      sleep 3
    fi
    ptr=$(( ptr + 1 ))
  done
}

# ====================================================================
#  SCREEN 5 -- THE JOURNEY
# ====================================================================

init_nodes() {
  NODE_PIDS=()
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
    launch_node_window "$i" "$pkg"
    sleep "$LAUNCH_DELAY"
    node_loop "$i" "$pkg" &
    NODE_PIDS+=($!)
  done
}

fmt_countdown() {
  local target=$1 now=$(date +%s)
  local r=$(( target - now )); [[ $r -lt 0 ]] && r=0
  printf '%02d:%02d' $(( r/60 )) $(( r%60 ))
}

render_journey() {
  tput cup 0 0 2>/dev/null || true
  local hops=0 fails=0 i
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local h=0 f=0
    [[ -f "${STATE_DIR}/node_${i}.hops" ]]  && h=$(cat "${STATE_DIR}/node_${i}.hops")
    [[ -f "${STATE_DIR}/node_${i}.fails" ]] && f=$(cat "${STATE_DIR}/node_${i}.fails")
    hops=$(( hops + h )); fails=$(( fails + f ))
  done

  at 0 0 "${VIOLET}${BOLD}  THE JOURNEY${R}  ${GRAY}$(date '+%H:%M:%S')${R}"
  hline 1
  at 2 0 "  Hops: ${GREEN}${hops}${R}  Fails: ${RED}${fails}${R}  Cache clears in: ${YELLOW}$(fmt_countdown $(( LAST_CACHE_CLEAR + CACHE_CLEAR_INTERVAL*60 )))${R}"
  hline 3

  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local status="?" pkg="?" progress="0/0" next_hop=0
    [[ -f "${STATE_DIR}/node_${i}.status" ]]   && status=$(cat "${STATE_DIR}/node_${i}.status")
    [[ -f "${STATE_DIR}/node_${i}.pkg" ]]      && pkg=$(cat "${STATE_DIR}/node_${i}.pkg")
    [[ -f "${STATE_DIR}/node_${i}.progress" ]] && progress=$(cat "${STATE_DIR}/node_${i}.progress")
    [[ -f "${STATE_DIR}/node_${i}.nexthop" ]]  && next_hop=$(cat "${STATE_DIR}/node_${i}.nexthop")
    local short="${pkg##*.}"; short="${short:0:12}"
    local cd; cd=$(fmt_countdown "$next_hop")
    at $((4+i)) 0 "  [N$((i+1)) ${short}]  ${progress}  ${status}  ${cd}"
  done

  hline $((4 + ${#NODES[@]} + 1))
  at $((4 + ${#NODES[@]} + 2)) 0 "${GRAY}  [q] Return to lobby   [s1-s4] Skip node${R}"
}

screen_journey() {
  tui_clear
  at 5 0 "${DUST}  Initializing nodes...${R}"
  init_nodes
  tui_clear
  local NEXT_REDRAW=$(( $(date +%s) + 30 ))
  while true; do
    local now=$(date +%s)
    if [[ $now -ge $NEXT_REDRAW ]]; then
      render_journey
      NEXT_REDRAW=$(( now + 30 ))
    fi
    local key=""
    if read -r -t 1 -n 2 key 2>/dev/null; then
      key="${key,,}"
      if [[ "$key" == "q" ]]; then
        for pid in "${NODE_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
        NODE_PIDS=()
        screen_lobby; return
      elif [[ "$key" =~ ^s([0-9])$ ]]; then
        local ni=$(( ${BASH_REMATCH[1]} - 1 ))
        touch "${STATE_DIR}/node_${ni}.skip"
      fi
    fi
  done
}

# ====================================================================
#  LIFECYCLE
# ====================================================================

cleanup() {
  [[ ${#NODE_PIDS[@]} -gt 0 ]] && for pid in "${NODE_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
  rm -rf "$STATE_DIR" 2>/dev/null || true
  tui_restore
  printf '\n%s  The Fool has returned from the journey.%s\n\n' "$VIOLET" "$R"
  exit 0
}

trap 'cleanup' SIGINT SIGTERM EXIT

# ====================================================================
#  MAIN
# ====================================================================

main() {
  local missing=()
  for cmd in curl jq tput; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf '%sMissing: %s%s\n' "$RED" "${missing[*]}" "$R"
    printf 'Run: pkg install %s\n' "${missing[*]}"
    exit 1
  fi
  tui_init
  screen_boot
  screen_army
  screen_universe
  screen_lobby
}

main "$@"
