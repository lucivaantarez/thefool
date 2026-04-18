#!/usr/bin/env bash
# ================================================================
#  THE FOOL -- Roblox Private Server Hopper v1.0.0 | Saturnity
# ================================================================

set -uo pipefail

# -- CONSTANTS ---------------------------------------------------
readonly VERSION="1.0.0"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/lucivaantarez/thefool/main/the_fool.sh"
readonly API_ENDPOINT="https://universe-vault.vercel.app/api/links"
readonly API_AUTH_TOKEN="fool-secret-token-2025"
readonly SELF_PATH="$(realpath "$0")"
readonly STATE_DIR="${HOME}/.fool_state"

# -- CONFIG ------------------------------------------------------
CACHE_CLEAR_INTERVAL=30
REJOIN_INTERVAL=15
MAX_FAILS=3
LAUNCH_DELAY=30
HOP_INTERVAL=480
AUTO_KILL=1

# -- STATE -------------------------------------------------------
declare -a LINKS=()
declare -a GAME_IDS=()
declare -a LINK_CODES=()
declare -a NODES=()
declare -a NODE_PIDS=()
LAST_CACHE_CLEAR=$(date +%s)
DISTRIBUTION_MODE=1
SCREEN_W=2160
SCREEN_H=1440

# -- COLORS ------------------------------------------------------
R=$'\033[0m'
BOLD=$'\033[1m'
VIOLET=$'\033[38;5;135m'
DUST=$'\033[38;5;183m'
GREEN=$'\033[38;5;114m'
RED=$'\033[38;5;203m'
YELLOW=$'\033[38;5;222m'
GRAY=$'\033[38;5;242m'
WHITE=$'\033[97m'

# ================================================================
#  PRINT HELPERS -- plain echo, no tput positioning
# ================================================================

cls() { printf '\033[2J\033[H'; }

line() { printf '%s\n' "----------------------------------------------------------------"; }

header() {
  cls
  printf '%s%s\n' "$VIOLET" "$BOLD"
  printf '%s\n' "  _____ _   _ _____   _____ ___   ___  _     "
  printf '%s\n' " |_   _| | | |  ___| |  ___/ _ \ / _ \| |   "
  printf '%s\n' "   | | | |_| | |__   | |_ | | | | | | | |   "
  printf '%s\n' "   | | |  _  |  __|  |  _|| | | | | | | |   "
  printf '%s\n' "   | | | | | | |___  | |  \ \_/ / \_/ / |___"
  printf '%s\n' "   \_/ \_| |_/\____/ \_|   \___/ \___/\_____/"
  printf '%s\n' "$R"
  printf '%s  v%s  Saturnity  Private Server Hopper%s\n' "$GRAY" "$VERSION" "$R"
  line
}

p()  { printf '%s\n' "$*"; }
pp() { printf '  %s\n' "$*"; }

inp() {
  # inp "label" varname
  stty sane 2>/dev/null || true
  printf '  %s: ' "$1"
  read -r "$2"
}

inp1() {
  # inp1 "label" varname  -- single char
  stty sane 2>/dev/null || true
  printf '  %s: ' "$1"
  read -r -n1 "$2"
  printf '\n'
}

# ================================================================
#  SELF-UPDATE
# ================================================================

check_update() {
  header
  pp "${GRAY}Checking for updates...${R}"
  local tmp="${HOME}/.fool_update_$$.sh"
  if ! curl -sf --max-time 8 "$GITHUB_RAW_URL" -o "$tmp" 2>/dev/null; then
    pp "${YELLOW}Could not reach update server. Continuing offline.${R}"
    sleep 1; return
  fi
  local lh rh
  lh=$(sha256sum "$SELF_PATH" 2>/dev/null | awk '{print $1}')
  rh=$(sha256sum "$tmp"       2>/dev/null | awk '{print $1}')
  if [[ -n "$rh" && "$lh" != "$rh" ]]; then
    pp "${DUST}Update found. Installing...${R}"
    sleep 1; mv "$tmp" "$SELF_PATH"; chmod +x "$SELF_PATH"
    pp "${GREEN}Updated. Relaunching...${R}"; sleep 1
    exec "$SELF_PATH" "$@"
  else
    pp "${GREEN}Up to date (v${VERSION})${R}"
    rm -f "$tmp"; sleep 0.5
  fi
}

# ================================================================
#  DATA LAYER
# ================================================================

fetch_links() {
  local silent="${1:-0}"
  [[ "$silent" == "0" ]] && pp "${GRAY}Connecting to Universe Vault...${R}"
  local response
  response=$(curl -sf --max-time 10 \
    -H "x-fool-auth: ${API_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_ENDPOINT}" 2>/dev/null) || {
    [[ "$silent" == "0" ]] && pp "${RED}Failed to reach Universe Vault. Check connection.${R}"
    return 1
  }
  LINKS=(); GAME_IDS=(); LINK_CODES=()
  local count
  count=$(printf '%s' "$response" | jq -r 'length' 2>/dev/null || echo 0)
  if [[ "$count" -eq 0 ]]; then
    [[ "$silent" == "0" ]] && pp "${YELLOW}Vault returned 0 links.${R}"
    return 0
  fi
  while IFS=$'\t' read -r url gid code; do
    LINKS+=("$url"); GAME_IDS+=("$gid"); LINK_CODES+=("$code")
  done < <(printf '%s' "$response" | jq -r '.[] | [.fullUrl, .gameId, .linkCode] | @tsv' 2>/dev/null)
  [[ "$silent" == "0" ]] && pp "${GREEN}Retrieved ${#LINKS[@]} links from the Universe.${R}"
  return 0
}

# ================================================================
#  SCREEN 1 -- BOOT
# ================================================================

screen_boot() {
  header
  pp "${DUST}Initializing...${R}"
  mkdir -p "$STATE_DIR"
  check_update
  header
  pp "${DUST}Connecting to Universe Vault...${R}"
  p ""
  if ! fetch_links 0; then
    p ""
    inp1 "Press any key to retry, [q] to exit" _key
    [[ "${_key:-}" == "q" ]] && cleanup
    screen_boot; return
  fi
  p ""
  inp1 "Press any key to continue" _k
}

# ================================================================
#  SCREEN 2 -- CHOOSE THE ARMY
# ================================================================

screen_army() {
  NODES=()
  local packages=()
  while true; do
    header
    pp "${DUST}${BOLD}CHOOSE THE ARMY -- Node Configuration${R}"
    p ""
    inp "Package name (e.g. com.roblox, com.delta)" _input
    [[ -z "${_input:-}" ]] && continue
    p ""
    pp "${GRAY}Scanning packages...${R}"
    mapfile -t packages < <(pm list packages 2>/dev/null | grep "$_input" | sed 's/^package://' | sort)
    if [[ ${#packages[@]} -eq 0 ]]; then
      pp "${RED}No packages matched '${_input}'. Try again.${R}"
      sleep 1.5; continue
    fi
    p ""
    pp "${GRAY}Found ${#packages[@]} package(s):${R}"
    local i
    for i in "${!packages[@]}"; do
      pp "  ${VIOLET}[$((i+1))]${R} ${packages[$i]}"
    done
    p ""
    inp "Select nodes [1 2 3 / all]" _sel
    NODES=()
    if [[ "${_sel:-}" == "all" ]]; then
      NODES=("${packages[@]}")
    else
      for tok in ${_sel:-}; do
        local idx=$((tok - 1))
        if [[ "$idx" -ge 0 && "$idx" -lt "${#packages[@]}" ]]; then
          NODES+=("${packages[$idx]}")
        fi
      done
    fi
    if [[ ${#NODES[@]} -eq 0 ]]; then
      pp "${RED}No valid selection. Try again.${R}"
      sleep 1.2; continue
    fi
    p ""
    pp "${GREEN}${#NODES[@]} node(s) selected.${R}"
    sleep 0.8; break
  done
}

# ================================================================
#  SCREEN 3 -- CHOOSE THE UNIVERSE
# ================================================================

get_screen_dims() {
  local size
  size=$(su -c "wm size" 2>/dev/null | grep -o '[0-9]*x[0-9]*' | tail -1)
  [[ -z "$size" ]] && size=$(wm size 2>/dev/null | grep -o '[0-9]*x[0-9]*' | tail -1)
  SCREEN_W=$(printf '%s' "$size" | cut -dx -f1)
  SCREEN_H=$(printf '%s' "$size" | cut -dx -f2)
  [[ -z "$SCREEN_W" || "$SCREEN_W" -eq 0 ]] && SCREEN_W=2160
  [[ -z "$SCREEN_H" || "$SCREEN_H" -eq 0 ]] && SCREEN_H=1440
}

calculate_bounds() {
  local idx=$1 hw=$((SCREEN_W/2)) hh=$((SCREEN_H/2))
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
    header
    pp "${DUST}${BOLD}CHOOSE THE UNIVERSE -- Strategy & Layout${R}"
    p ""
    pp "Screen: ${SCREEN_W}x${SCREEN_H}  Nodes: ${#NODES[@]}  Links: ${#LINKS[@]}"
    p ""
    pp "${VIOLET}Distribution Mode:${R}"
    pp "  [1] Converge - all nodes use full link list"
    pp "  [2] Diverge  - split list equally per node"
    p ""
    pp "${VIOLET}Actions:${R}"
    pp "  [f] Re-fetch links from API"
    pp "  [t] Test Grid (launch all, 15s stagger)"
    pp "  [enter] Continue to Command Center"
    p ""
    pp "${GREEN}Current: $([ $DISTRIBUTION_MODE -eq 1 ] && echo CONVERGE || echo DIVERGE)${R}"
    p ""
    inp1 "Choice" _key
    case "${_key:-}" in
      1) DISTRIBUTION_MODE=1; pp "${GREEN}Mode set to CONVERGE${R}"; sleep 0.5 ;;
      2) DISTRIBUTION_MODE=2; pp "${GREEN}Mode set to DIVERGE${R}"; sleep 0.5 ;;
      f|F)
        pp "${GRAY}Re-fetching...${R}"
        fetch_links 1
        pp "${GREEN}${#LINKS[@]} links loaded.${R}"; sleep 1 ;;
      t|T)
        pp "${DUST}Launching test grid...${R}"
        local ni
        for ni in "${!NODES[@]}"; do
          [[ $ni -ge 4 ]] && break
          launch_node_window "$ni" "${NODES[$ni]}"
          sleep 15
        done
        pp "${GREEN}Test grid launched.${R}"; sleep 1 ;;
      "") break ;;
    esac
  done
}

# ================================================================
#  SCREEN 4 -- COMMAND CENTER
# ================================================================

screen_lobby() {
  while true; do
    header
    pp "${DUST}${BOLD}COMMAND CENTER${R}"
    pp "Nodes: ${#NODES[@]}  Links: ${#LINKS[@]}  Mode: $([ $DISTRIBUTION_MODE -eq 1 ] && echo CONVERGE || echo DIVERGE)"
    p ""
    pp "${VIOLET}CONFIG${R}"
    pp "  [a] Cache clear interval  ${DUST}${CACHE_CLEAR_INTERVAL}min${R}"
    pp "  [b] Rejoin interval       ${DUST}${REJOIN_INTERVAL}s${R}"
    pp "  [c] Max fails per link    ${DUST}${MAX_FAILS}${R}"
    pp "  [d] Launch delay          ${DUST}${LAUNCH_DELAY}s${R}"
    pp "  [e] Hop interval          ${DUST}${HOP_INTERVAL}s${R}"
    pp "  [f] Auto-Kill             $([ $AUTO_KILL -eq 1 ] && printf '%sON%s' "$GREEN" "$R" || printf '%sOFF%s' "$RED" "$R")"
    p ""
    line
    pp "${VIOLET}ACTIONS${R}"
    pp "  [1] RELEASE THE FOOL -- start hopping"
    pp "  [2] Expand Universe  -- back to strategy"
    pp "  [3] Rally Army       -- back to node select"
    pp "  [0] EXIT"
    p ""
    inp1 "Command" _key
    case "${_key:-}" in
      a) inp "Cache clear interval (5-60 min)" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && (( _v>=5 && _v<=60 )) && CACHE_CLEAR_INTERVAL=$_v ;;
      b) inp "Rejoin interval (seconds)" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && REJOIN_INTERVAL=$_v ;;
      c) inp "Max fails per link" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && MAX_FAILS=$_v ;;
      d) inp "Launch delay (15-120s)" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && (( _v>=15 && _v<=120 )) && LAUNCH_DELAY=$_v ;;
      e) inp "Hop interval (180-900s)" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && (( _v>=180 && _v<=900 )) && HOP_INTERVAL=$_v ;;
      f) AUTO_KILL=$(( 1 - AUTO_KILL ))
         pp "Auto-Kill: $([ $AUTO_KILL -eq 1 ] && echo ON || echo OFF)"; sleep 0.5 ;;
      1) screen_journey ;;
      2) screen_universe ;;
      3) screen_army; screen_universe ;;
      0) cleanup ;;
    esac
  done
}

# ================================================================
#  NODE LOOP
# ================================================================

node_loop() {
  local node_idx=$1 pkg=$2
  local -a my_links=() my_gids=() my_codes=()
  local ptr=0 total_hops=0 consecutive_fails=0

  if [[ $DISTRIBUTION_MODE -eq 1 ]]; then
    my_links=("${LINKS[@]}"); my_gids=("${GAME_IDS[@]}"); my_codes=("${LINK_CODES[@]}")
  else
    local total=${#LINKS[@]} nc=${#NODES[@]}
    local chunk=$(( (total + nc - 1) / nc ))
    local start=$(( node_idx * chunk )) end=$(( node_idx * chunk + chunk ))
    [[ $end -gt $total ]] && end=$total
    for (( i=start; i<end; i++ )); do
      my_links+=("${LINKS[$i]}"); my_gids+=("${GAME_IDS[$i]}"); my_codes+=("${LINK_CODES[$i]}")
    done
  fi

  local total_my=${#my_links[@]}
  [[ $total_my -eq 0 ]] && { echo "IDLE" > "${STATE_DIR}/node_${node_idx}.status"; return; }
  [[ -f "${STATE_DIR}/node_${node_idx}.ptr" ]] && ptr=$(( $(cat "${STATE_DIR}/node_${node_idx}.ptr") % total_my ))
  local last_cache=$( date +%s)

  while true; do
    ptr=$(( ptr % total_my ))
    local gid="${my_gids[$ptr]}" code="${my_codes[$ptr]}"
    local next_hop=$(( $(date +%s) + HOP_INTERVAL ))
    echo "LAUNCHING"            > "${STATE_DIR}/node_${node_idx}.status"
    echo "$pkg"                 > "${STATE_DIR}/node_${node_idx}.pkg"
    echo "${ptr}/${total_my}"   > "${STATE_DIR}/node_${node_idx}.progress"
    echo "$next_hop"            > "${STATE_DIR}/node_${node_idx}.nexthop"
    echo "$total_hops"          > "${STATE_DIR}/node_${node_idx}.hops"
    echo "$consecutive_fails"   > "${STATE_DIR}/node_${node_idx}.fails"
    echo "$ptr"                 > "${STATE_DIR}/node_${node_idx}.ptr"

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
    if (( (now - last_cache) / 60 >= CACHE_CLEAR_INTERVAL )); then
      su -c "pm clear ${pkg}" 2>/dev/null || true
      last_cache=$now
      echo "CACHE CLR" > "${STATE_DIR}/node_${node_idx}.status"
      sleep 3
    fi
    ptr=$(( ptr + 1 ))
  done
}

# ================================================================
#  SCREEN 5 -- THE JOURNEY
# ================================================================

init_nodes() {
  NODE_PIDS=()
  local i
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    rm -f "${STATE_DIR}/node_${i}.skip"
    echo "INIT" > "${STATE_DIR}/node_${i}.status"
    echo "0"    > "${STATE_DIR}/node_${i}.ptr"
    echo "0"    > "${STATE_DIR}/node_${i}.hops"
    echo "0"    > "${STATE_DIR}/node_${i}.fails"
    echo "0"    > "${STATE_DIR}/node_${i}.nexthop"
    echo "0/0"  > "${STATE_DIR}/node_${i}.progress"
    echo "${NODES[$i]}" > "${STATE_DIR}/node_${i}.pkg"
    launch_node_window "$i" "${NODES[$i]}"
    sleep "$LAUNCH_DELAY"
    node_loop "$i" "${NODES[$i]}" &
    NODE_PIDS+=($!)
  done
}

fmt_cd() {
  local t=$1 n=$(date +%s) r=$(( $1 - $(date +%s) ))
  [[ $r -lt 0 ]] && r=0
  printf '%02d:%02d' $(( r/60 )) $(( r%60 ))
}

render_journey() {
  cls
  printf '%s%s  THE JOURNEY%s  %s%s%s\n' "$VIOLET" "$BOLD" "$R" "$GRAY" "$(date '+%H:%M:%S')" "$R"
  line
  local hops=0 fails=0 i
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local h=0 f=0
    [[ -f "${STATE_DIR}/node_${i}.hops" ]]  && h=$(cat "${STATE_DIR}/node_${i}.hops")
    [[ -f "${STATE_DIR}/node_${i}.fails" ]] && f=$(cat "${STATE_DIR}/node_${i}.fails")
    hops=$(( hops+h )); fails=$(( fails+f ))
  done
  pp "Total Hops: ${GREEN}${hops}${R}  Total Fails: ${RED}${fails}${R}"
  line
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local status="?" pkg="?" progress="0/0" next_hop=0
    [[ -f "${STATE_DIR}/node_${i}.status" ]]   && status=$(cat "${STATE_DIR}/node_${i}.status")
    [[ -f "${STATE_DIR}/node_${i}.pkg" ]]      && pkg=$(cat "${STATE_DIR}/node_${i}.pkg")
    [[ -f "${STATE_DIR}/node_${i}.progress" ]] && progress=$(cat "${STATE_DIR}/node_${i}.progress")
    [[ -f "${STATE_DIR}/node_${i}.nexthop" ]]  && next_hop=$(cat "${STATE_DIR}/node_${i}.nexthop")
    local short="${pkg##*.}"; short="${short:0:14}"
    pp "N$((i+1)) [${short}]  ${progress}  ${status}  next: $(fmt_cd $next_hop)"
  done
  line
  pp "${GRAY}[q] Return to lobby   [s1-s4] Skip node${R}"
}

screen_journey() {
  cls
  pp "${DUST}Initializing nodes...${R}"
  init_nodes
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
        NODE_PIDS=(); screen_lobby; return
      elif [[ "$key" =~ ^s([0-9])$ ]]; then
        touch "${STATE_DIR}/node_${BASH_REMATCH[1]}.skip"
      fi
    fi
  done
}

# ================================================================
#  LIFECYCLE
# ================================================================

cleanup() {
  [[ ${#NODE_PIDS[@]} -gt 0 ]] && for pid in "${NODE_PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  jobs -p 2>/dev/null | xargs -r kill 2>/dev/null || true
  rm -rf "$STATE_DIR" 2>/dev/null || true
  stty sane 2>/dev/null || true
  printf '\n%s  The Fool has returned from the journey.%s\n\n' "$VIOLET" "$R"
  exit 0
}

trap 'cleanup' SIGINT SIGTERM EXIT

# ================================================================
#  MAIN
# ================================================================
main() {
  local missing=()
  for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'Missing deps: %s\nRun: pkg install %s\n' "${missing[*]}" "${missing[*]}"
    exit 1
  fi
  stty sane 2>/dev/null || true
  screen_boot
  screen_army
  screen_universe
  screen_lobby
}

main "$@"
