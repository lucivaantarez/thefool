#!/usr/bin/env bash
# THE FOOL v1.0.0 | Saturnity

set -uo pipefail

readonly VERSION="1.0.0"
readonly GITHUB_RAW_URL="https://raw.githubusercontent.com/lucivaantarez/thefool/main/the_fool.sh"
readonly API_ENDPOINT="https://universe-vault.vercel.app/api/links"
readonly API_AUTH_TOKEN="fool-secret-token-2025"
readonly SELF_PATH="$(realpath "$0")"
readonly STATE_DIR="${HOME}/.fool_state"

CACHE_CLEAR_INTERVAL=30
REJOIN_INTERVAL=15
MAX_FAILS=3
LAUNCH_DELAY=30
HOP_INTERVAL=480
AUTO_KILL=1

declare -a LINKS=()
declare -a GAME_IDS=()
declare -a LINK_CODES=()
declare -a NODES=()
declare -a NODE_PIDS=()
LAST_CACHE_CLEAR=$(date +%s)
DISTRIBUTION_MODE=1
SCREEN_W=2160
SCREEN_H=1440

R=$'\033[0m'
BOLD=$'\033[1m'
VI=$'\033[38;5;135m'
DU=$'\033[38;5;183m'
GR=$'\033[38;5;114m'
RE=$'\033[38;5;203m'
YE=$'\033[38;5;222m'
GY=$'\033[38;5;242m'
WH=$'\033[97m'

# ── helpers ──────────────────────────────────────────
cls()  { printf '\033[2J\033[H'; }
hr()   { printf '%s\n' "----------------------------------------"; }
p()    { printf '%s\n' "$*"; }
inp()  { stty sane 2>/dev/null||true; printf '%s ' "$1"; read -r "$2"; }
inp1() { stty sane 2>/dev/null||true; printf '%s ' "$1"; read -r -n1 "$2"; printf '\n'; }

hdr() {
  cls
  printf '%s%s\n' "$VI" "$BOLD"
  printf '%s\n' " _____ _  _ ___    ___  ___  ___  _    "
  printf '%s\n' "|_   _| || | __|  | __|/ _ \/ _ \| |   "
  printf '%s\n' "  | | | __ | _|   | _|| (_) | (_) | |__ "
  printf '%s\n' "  |_| |_||_|___|  |_|  \___/ \___/|____|"
  printf '%s\n' "$R"
  printf '%s v%s Saturnity%s\n' "$GY" "$VERSION" "$R"
  hr
}

# ── self-update ───────────────────────────────────────
check_update() {
  hdr; p "${GY}Checking for updates...${R}"
  local tmp="${HOME}/.fool_tmp_$$.sh"
  if ! curl -sf --max-time 8 "$GITHUB_RAW_URL" -o "$tmp" 2>/dev/null; then
    p "${YE}Offline. Skipping update.${R}"; sleep 1; return
  fi
  local lh rh
  lh=$(sha256sum "$SELF_PATH" 2>/dev/null | awk '{print $1}')
  rh=$(sha256sum "$tmp"       2>/dev/null | awk '{print $1}')
  if [[ -n "$rh" && "$lh" != "$rh" ]]; then
    p "${DU}Update found. Installing...${R}"; sleep 1
    mv "$tmp" "$SELF_PATH"; chmod +x "$SELF_PATH"
    p "${GR}Done. Relaunching...${R}"; sleep 1
    exec "$SELF_PATH" "$@"
  else
    p "${GR}Up to date.${R}"; rm -f "$tmp"; sleep 0.5
  fi
}

# ── fetch links ───────────────────────────────────────
fetch_links() {
  local s="${1:-0}"
  [[ "$s" == "0" ]] && p "${GY}Connecting to Vault...${R}"
  local res
  res=$(curl -sf --max-time 10 \
    -H "x-fool-auth: ${API_AUTH_TOKEN}" \
    -H "Content-Type: application/json" \
    "${API_ENDPOINT}" 2>/dev/null) || {
    [[ "$s" == "0" ]] && p "${RE}Cannot reach Vault.${R}"
    return 1
  }
  LINKS=(); GAME_IDS=(); LINK_CODES=()
  local n
  n=$(printf '%s' "$res" | jq -r 'length' 2>/dev/null || echo 0)
  if [[ "$n" -eq 0 ]]; then
    [[ "$s" == "0" ]] && p "${YE}Vault has 0 links.${R}"; return 0
  fi
  while IFS=$'\t' read -r url gid code; do
    LINKS+=("$url"); GAME_IDS+=("$gid"); LINK_CODES+=("$code")
  done < <(printf '%s' "$res" | jq -r '.[] | [.fullUrl,.gameId,.linkCode] | @tsv' 2>/dev/null)
  [[ "$s" == "0" ]] && p "${GR}Got ${#LINKS[@]} links.${R}"
  return 0
}

# ── screen 1: boot ───────────────────────────────────
screen_boot() {
  hdr; p "${DU}Booting...${R}"
  mkdir -p "$STATE_DIR"
  check_update
  hdr; p "${DU}Connecting...${R}"; p ""
  if ! fetch_links 0; then
    p ""; inp1 "Retry? [any=yes q=quit]" _k
    [[ "${_k:-}" == "q" ]] && cleanup
    screen_boot; return
  fi
  p ""; inp1 "[any key] Continue" _k
}

# ── screen 2: army ───────────────────────────────────
screen_army() {
  NODES=()
  local pkgs=()
  while true; do
    hdr
    p "${DU}${BOLD}CHOOSE THE ARMY${R}"
    p ""
    inp "Package (e.g. com.roblox):" _in
    [[ -z "${_in:-}" ]] && continue
    p ""
    mapfile -t pkgs < <(pm list packages 2>/dev/null | grep "$_in" | sed 's/^package://' | sort)
    if [[ ${#pkgs[@]} -eq 0 ]]; then
      p "${RE}No match for '$_in'. Try again.${R}"; sleep 1.5; continue
    fi
    p "${GY}Found ${#pkgs[@]}:${R}"
    local i
    for i in "${!pkgs[@]}"; do
      p " [${VI}$((i+1))${R}] ${pkgs[$i]}"
    done
    p ""
    inp "Select [1 2 3... or all]:" _sel
    NODES=()
    if [[ "${_sel:-}" == "all" ]]; then
      NODES=("${pkgs[@]}")
    else
      for t in ${_sel:-}; do
        local x=$((t-1))
        [[ $x -ge 0 && $x -lt ${#pkgs[@]} ]] && NODES+=("${pkgs[$x]}")
      done
    fi
    if [[ ${#NODES[@]} -eq 0 ]]; then
      p "${RE}Invalid. Try again.${R}"; sleep 1.2; continue
    fi
    p ""; p "${GR}${#NODES[@]} node(s) selected.${R}"; sleep 0.8; break
  done
}

# ── screen 3: universe ───────────────────────────────
get_screen_dims() {
  local sz
  sz=$(su -c "wm size" 2>/dev/null | grep -o '[0-9]*x[0-9]*' | tail -1)
  [[ -z "$sz" ]] && sz=$(wm size 2>/dev/null | grep -o '[0-9]*x[0-9]*' | tail -1)
  SCREEN_W=$(printf '%s' "$sz" | cut -dx -f1)
  SCREEN_H=$(printf '%s' "$sz" | cut -dx -f2)
  [[ -z "$SCREEN_W" || "$SCREEN_W" -eq 0 ]] && SCREEN_W=2160
  [[ -z "$SCREEN_H" || "$SCREEN_H" -eq 0 ]] && SCREEN_H=1440
}

calc_bounds() {
  local i=$1 hw=$((SCREEN_W/2)) hh=$((SCREEN_H/2))
  case $i in
    0) echo "0 0 $hw $hh" ;;
    1) echo "$hw 0 $SCREEN_W $hh" ;;
    2) echo "0 $hh $hw $SCREEN_H" ;;
    3) echo "$hw $hh $SCREEN_W $SCREEN_H" ;;
    *) echo "0 0 $hw $hh" ;;
  esac
}

launch_win() {
  local i=$1 pkg=$2
  read -r L T Rb B <<< "$(calc_bounds $i)"
  su -c "settings put global enable_freeform_support 1" 2>/dev/null||true
  su -c "am start --windowingMode 5 --bounds [${L},${T},${Rb},${B}] -n ${pkg}/com.roblox.client.startup.ActivityNativeMain" 2>/dev/null || \
  su -c "am start --windowingMode 5 --bounds [${L},${T},${Rb},${B}] ${pkg}" 2>/dev/null||true
}

screen_universe() {
  get_screen_dims
  while true; do
    hdr
    p "${DU}${BOLD}CHOOSE THE UNIVERSE${R}"
    p "Screen:${SCREEN_W}x${SCREEN_H} Nodes:${#NODES[@]} Links:${#LINKS[@]}"
    p ""
    p "${VI}Mode:${R}"
    p " [1] Converge - all nodes, full list"
    p " [2] Diverge  - split list per node"
    p ""
    p "${VI}Actions:${R}"
    p " [f] Re-fetch links"
    p " [t] Test grid (15s delay)"
    p " [enter] Go to Command Center"
    p ""
    p "${GR}Now: $([ $DISTRIBUTION_MODE -eq 1 ] && echo CONVERGE || echo DIVERGE)${R}"
    p ""
    inp1 ">" _k
    case "${_k:-}" in
      1) DISTRIBUTION_MODE=1; p "${GR}CONVERGE set.${R}"; sleep 0.4 ;;
      2) DISTRIBUTION_MODE=2; p "${GR}DIVERGE set.${R}"; sleep 0.4 ;;
      f|F)
        p "${GY}Fetching...${R}"; fetch_links 1
        p "${GR}${#LINKS[@]} links.${R}"; sleep 1 ;;
      t|T)
        p "${DU}Launching...${R}"
        for ni in "${!NODES[@]}"; do
          [[ $ni -ge 4 ]] && break
          launch_win "$ni" "${NODES[$ni]}"; sleep 15
        done
        p "${GR}Done.${R}"; sleep 1 ;;
      "") break ;;
    esac
  done
}

# ── screen 4: lobby ──────────────────────────────────
screen_lobby() {
  while true; do
    hdr
    p "${DU}${BOLD}COMMAND CENTER${R}"
    p "Nodes:${#NODES[@]} Links:${#LINKS[@]} $([ $DISTRIBUTION_MODE -eq 1 ] && echo CONV || echo DIV)"
    hr
    p "${VI}CONFIG${R}"
    p " [a] Cache clear  ${DU}${CACHE_CLEAR_INTERVAL}min${R}"
    p " [b] Rejoin delay ${DU}${REJOIN_INTERVAL}s${R}"
    p " [c] Max fails    ${DU}${MAX_FAILS}${R}"
    p " [d] Launch delay ${DU}${LAUNCH_DELAY}s${R}"
    p " [e] Hop interval ${DU}${HOP_INTERVAL}s${R}"
    p " [f] Auto-Kill    $([ $AUTO_KILL -eq 1 ] && printf '%sON%s' "$GR" "$R" || printf '%sOFF%s' "$RE" "$R")"
    hr
    p "${VI}ACTIONS${R}"
    p " [1] RELEASE THE FOOL"
    p " [2] Back to Universe"
    p " [3] Back to Army"
    p " [0] Exit"
    p ""
    inp1 ">" _k
    case "${_k:-}" in
      a) inp "Cache (5-60min):" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && ((_v>=5&&_v<=60)) && CACHE_CLEAR_INTERVAL=$_v ;;
      b) inp "Rejoin (sec):" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && REJOIN_INTERVAL=$_v ;;
      c) inp "Max fails:" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && MAX_FAILS=$_v ;;
      d) inp "Launch delay (15-120s):" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && ((_v>=15&&_v<=120)) && LAUNCH_DELAY=$_v ;;
      e) inp "Hop interval (180-900s):" _v
         [[ "$_v" =~ ^[0-9]+$ ]] && ((_v>=180&&_v<=900)) && HOP_INTERVAL=$_v ;;
      f) AUTO_KILL=$((1-AUTO_KILL))
         p "Auto-Kill: $([ $AUTO_KILL -eq 1 ] && echo ON || echo OFF)"; sleep 0.4 ;;
      1) screen_journey ;;
      2) screen_universe ;;
      3) screen_army; screen_universe ;;
      0) cleanup ;;
    esac
  done
}

# ── node loop ─────────────────────────────────────────
node_loop() {
  local ni=$1 pkg=$2
  local -a ml=() mg=() mc=()
  local ptr=0 hops=0 cfails=0

  if [[ $DISTRIBUTION_MODE -eq 1 ]]; then
    ml=("${LINKS[@]}"); mg=("${GAME_IDS[@]}"); mc=("${LINK_CODES[@]}")
  else
    local tot=${#LINKS[@]} nc=${#NODES[@]}
    local chunk=$(((tot+nc-1)/nc))
    local s=$((ni*chunk)) e=$((ni*chunk+chunk))
    [[ $e -gt $tot ]] && e=$tot
    for ((j=s;j<e;j++)); do ml+=("${LINKS[$j]}"); mg+=("${GAME_IDS[$j]}"); mc+=("${LINK_CODES[$j]}"); done
  fi

  local tm=${#ml[@]}
  [[ $tm -eq 0 ]] && { echo "IDLE">"${STATE_DIR}/node_${ni}.status"; return; }
  [[ -f "${STATE_DIR}/node_${ni}.ptr" ]] && ptr=$(($(cat "${STATE_DIR}/node_${ni}.ptr")%tm))
  local lc=$(date +%s)

  while true; do
    ptr=$((ptr%tm))
    local gid="${mg[$ptr]}" code="${mc[$ptr]}"
    local nh=$(( $(date +%s)+HOP_INTERVAL ))
    echo "LAUNCHING"     >"${STATE_DIR}/node_${ni}.status"
    echo "$pkg"          >"${STATE_DIR}/node_${ni}.pkg"
    echo "${ptr}/${tm}"  >"${STATE_DIR}/node_${ni}.progress"
    echo "$nh"           >"${STATE_DIR}/node_${ni}.nexthop"
    echo "$hops"         >"${STATE_DIR}/node_${ni}.hops"
    echo "$cfails"       >"${STATE_DIR}/node_${ni}.fails"
    echo "$ptr"          >"${STATE_DIR}/node_${ni}.ptr"

    su -c "am start -a android.intent.action.VIEW -d 'roblox://placeId=${gid}&linkCode=${code}' --package ${pkg}" 2>/dev/null || \
    su -c "am start -a android.intent.action.VIEW -d 'roblox://placeId=${gid}&linkCode=${code}'" 2>/dev/null || {
      cfails=$((cfails+1)); echo "$cfails">"${STATE_DIR}/node_${ni}.fails"
      if [[ $cfails -ge $MAX_FAILS ]]; then
        echo "SKIP">"${STATE_DIR}/node_${ni}.status"; ptr=$((ptr+1)); cfails=0; continue
      fi
      sleep "$REJOIN_INTERVAL"; continue
    }

    cfails=0; hops=$((hops+1))
    echo "CONNECTED">"${STATE_DIR}/node_${ni}.status"

    while [[ $(date +%s) -lt $nh ]]; do
      echo "$nh">"${STATE_DIR}/node_${ni}.nexthop"; sleep 5
      [[ -f "${STATE_DIR}/node_${ni}.skip" ]] && { rm -f "${STATE_DIR}/node_${ni}.skip"; break; }
    done

    echo "HOPPING">"${STATE_DIR}/node_${ni}.status"
    [[ $AUTO_KILL -eq 1 ]] && { su -c "am force-stop ${pkg}" 2>/dev/null||true; sleep 2; }

    local now=$(date +%s)
    if (( (now-lc)/60 >= CACHE_CLEAR_INTERVAL )); then
      su -c "pm clear ${pkg}" 2>/dev/null||true; lc=$now
      echo "CACHE CLR">"${STATE_DIR}/node_${ni}.status"; sleep 3
    fi
    ptr=$((ptr+1))
  done
}

# ── screen 5: journey ────────────────────────────────
init_nodes() {
  NODE_PIDS=()
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    rm -f "${STATE_DIR}/node_${i}.skip"
    echo "INIT" >"${STATE_DIR}/node_${i}.status"
    echo "0"    >"${STATE_DIR}/node_${i}.ptr"
    echo "0"    >"${STATE_DIR}/node_${i}.hops"
    echo "0"    >"${STATE_DIR}/node_${i}.fails"
    echo "0"    >"${STATE_DIR}/node_${i}.nexthop"
    echo "0/0"  >"${STATE_DIR}/node_${i}.progress"
    echo "${NODES[$i]}">"${STATE_DIR}/node_${i}.pkg"
    launch_win "$i" "${NODES[$i]}"
    sleep "$LAUNCH_DELAY"
    node_loop "$i" "${NODES[$i]}" &
    NODE_PIDS+=($!)
  done
}

fcd() {
  local r=$(( $1 - $(date +%s) )); [[ $r -lt 0 ]] && r=0
  printf '%02d:%02d' $((r/60)) $((r%60))
}

render_journey() {
  cls
  printf '%s%sTHE JOURNEY%s %s%s%s\n' "$VI" "$BOLD" "$R" "$GY" "$(date '+%H:%M:%S')" "$R"
  hr
  local h=0 f=0
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local hh=0 ff=0
    [[ -f "${STATE_DIR}/node_${i}.hops" ]]  && hh=$(cat "${STATE_DIR}/node_${i}.hops")
    [[ -f "${STATE_DIR}/node_${i}.fails" ]] && ff=$(cat "${STATE_DIR}/node_${i}.fails")
    h=$((h+hh)); f=$((f+ff))
  done
  p "Hops:${GR}${h}${R} Fails:${RE}${f}${R}"
  hr
  for i in "${!NODES[@]}"; do
    [[ $i -ge 4 ]] && break
    local st="?" pk="?" pr="0/0" nh=0
    [[ -f "${STATE_DIR}/node_${i}.status" ]]   && st=$(cat "${STATE_DIR}/node_${i}.status")
    [[ -f "${STATE_DIR}/node_${i}.pkg" ]]      && pk=$(cat "${STATE_DIR}/node_${i}.pkg")
    [[ -f "${STATE_DIR}/node_${i}.progress" ]] && pr=$(cat "${STATE_DIR}/node_${i}.progress")
    [[ -f "${STATE_DIR}/node_${i}.nexthop" ]]  && nh=$(cat "${STATE_DIR}/node_${i}.nexthop")
    local sh="${pk##*.}"; sh="${sh:0:10}"
    p "N$((i+1))[${sh}] ${pr} ${st} $(fcd $nh)"
  done
  hr
  p "${GY}[q]lobby [s1-s4]skip node${R}"
}

screen_journey() {
  cls; p "${DU}Starting nodes...${R}"
  init_nodes
  local NR=$(( $(date +%s)+30 ))
  while true; do
    [[ $(date +%s) -ge $NR ]] && { render_journey; NR=$(( $(date +%s)+30 )); }
    local k=""
    if read -r -t 1 -n 2 k 2>/dev/null; then
      k="${k,,}"
      if [[ "$k" == "q" ]]; then
        for pid in "${NODE_PIDS[@]}"; do kill "$pid" 2>/dev/null||true; done
        NODE_PIDS=(); screen_lobby; return
      elif [[ "$k" =~ ^s([0-9])$ ]]; then
        touch "${STATE_DIR}/node_$((${BASH_REMATCH[1]}-1)).skip"
      fi
    fi
  done
}

# ── lifecycle ─────────────────────────────────────────
cleanup() {
  [[ ${#NODE_PIDS[@]} -gt 0 ]] && for pid in "${NODE_PIDS[@]}"; do kill "$pid" 2>/dev/null||true; done
  jobs -p 2>/dev/null | xargs -r kill 2>/dev/null||true
  rm -rf "$STATE_DIR" 2>/dev/null||true
  stty sane 2>/dev/null||true
  printf '\n%sThe Fool has returned.%s\n\n' "$VI" "$R"
  exit 0
}

trap 'cleanup' SIGINT SIGTERM EXIT

main() {
  for cmd in curl jq; do
    command -v "$cmd" &>/dev/null || { printf 'Missing: %s\nRun: pkg install %s\n' "$cmd" "$cmd"; exit 1; }
  done
  stty sane 2>/dev/null||true
  screen_boot; screen_army; screen_universe; screen_lobby
}

main "$@"
