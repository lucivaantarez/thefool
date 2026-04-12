<!--
╔══════════════════════════════════════════════════════════════════════════════════╗
║                         SATURNITY VAULT — MASTER DOCUMENTATION                    ║
║                    AI-READABLE ARCHITECTURE & BEHAVIORAL SPEC                  ║
╚══════════════════════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 1. IDENTITY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  File Name   : saturnity-vault-v5-5.html
  Language    : HTML5 + CSS3 + Vanilla JavaScript (ES2020+)
  Framework   : None — zero dependencies (Google Fonts CDN only, display only)
  Version     : v1.0
  Status      : Active / Production
  Entry Point : Self-contained. Open directly in any modern browser. No build step.
  Storage     : localStorage + optional GitHub Gist (remote). No mandatory server.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 2. PURPOSE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  IS RESPONSIBLE FOR:
  - Storing, organizing, and retrieving Roblox authentication cookie strings
    in localStorage, grouped by user-defined names and server names.
  - Parsing raw cookie lines in format:
      username:password:_|WARNING:-DO-NOT-SHARE-THIS.<cookie>
      username:_|WARNING:-DO-NOT-SHARE-THIS.<cookie>
      _|WARNING:-DO-NOT-SHARE-THIS.<cookie>
  - All CRUD operations on groups, cookies within groups, and cookie alternatives.
  - Exporting vault data as .json (full vault) or .txt (per-group cookie lines).
  - Importing and smart-merging vault data from .json or .txt files.
  - Rendering the complete UI: PIN lock screen, sidebar, card grid, slide-out
    detail panel, modals, toast notifications, quick-copy popup, filter bar,
    ban checker terminal, GitHub sync dot.
  - Tracking a daily-open streak and backup reminder.
  - PIN lock with decoy PIN support and lockout on repeated failures.
  - Optionally syncing vault to a GitHub Gist (PAT + Gist ID, user-provided).
  - Ban checking cookies via user-provided Cloudflare Worker URLs.
  - Calculating and displaying a vault health score.

  IS NOT RESPONSIBLE FOR:
  - Authentication against any external service.
  - Fetching or refreshing cookies from the network.
  - Encrypting data at rest (localStorage is plaintext; GitHub Gist is also
    plaintext — use a secret Gist and rotate PATs responsibly).
  - Operating the Cloudflare Worker — user must deploy their own Worker that
    accepts POST {cookie, username} and returns {status, duration?}.
  - Filtering banned groups from exports (ban is visual/annotation only).
  - Exporting alternative cookie sets via expTxt() (only main cookies exported).
  - Making alternatives reachable via Quick Copy (detail panel only).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 3. ARCHITECTURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Pattern     : Monolithic single-file SPA. Imperative DOM manipulation.
                Loosely resembles MVC: vault array = Model, render()/mkCard()
                = View, event listeners in the script block = Controller.
                No reactivity layer — all UI updates are manual DOM operations.

  Layer       : Primarily client-side. Optional async fetch() calls to GitHub
                Gist API (sync) and user-provided CF Worker URLs (ban check).

  Data Flow   :
    1. On load  → PIN screen shown → user unlocks → loadVault() → vault[].
    2. User action → mutates vault[] in memory.
    3. saveVault() → if decoyMode: no-op → else: localStorage + scheduleGhSync().
    4. scheduleGhSync() → 3s debounce → doGhSync() → PATCH GitHub Gist API.
    5. render() → wipes #vault → rebuilds DOM → updateHealthScore() → applyFilter().
    6. applyFilter() → dims/shows cards based on activeFilter + search query.
    7. Ban checker → reads getWorkerUrls() → round-robin POST to CF Workers →
       streams results to terminal log div in real time.

  CSS Architecture:
    - All styles in a single style block using CSS custom properties (--vars).
    - Colors defined in :root. Dark theme only. No light mode.
    - Card colors derived from server name via deterministic hash → PALETTE array.
    - Responsive only for ≤600px (hides sidebar, hides stat chips).
    - Three card sizes (sm/md/lg) controlled by body[data-csize] attribute.
    - Column count (1–4) controlled by CSS variable --cols on .card-grid.

  State Variables (module-level):
    vault[]           — Array of Group objects. Source of truth.
    pending[]         — Staged cookies for add-group modal.
    panelId           — ID of currently open detail panel group.
    bulkGroups[]      — Groups staged for bulk export modal.
    bulkLabel         — Label for bulk export modal.
    lastDeleted       — {group, index} for undo.
    undoTimer         — setTimeout handle for 5s undo window.
    cols              — Column count (1–4), persisted.
    sort              — Sort key: 'az'|'za'|'newest'|'most', persisted.
    settings          — Settings object, persisted separately.
    qcGroupId         — Group ID for open quick-copy popup.
    activeSrv         — Active sidebar server filter key.
    staggerTimers[]   — Handles for card entrance animation.
    confirmResolve    — Promise resolver for custom confirm modal.
    updateCandidates[] — Staged groups for sync-vault modal.
    ccache{}          — Color cache: server name → PALETTE entry.
    pinBuffer         — String of digits typed so far on PIN screen.
    pinFails          — Count of failed PIN attempts this session.
    pinLocked         — Boolean: is PIN input locked out?
    pinLockUntil      — Timestamp when lockout expires.
    decoyMode         — Boolean: decoy PIN entered; vault appears empty.
    ghPendingSync     — Boolean: a sync is queued (offline or failed).
    ghDebounceTimer   — setTimeout handle for 3s GitHub sync debounce.
    banCheckRunning   — Boolean: ban check in progress.
    banCheckAbort     — Boolean: abort signal for running check.
    banWorkerIdx      — Round-robin index for worker URL selection.
    banFailedCookies[] — Cookies flagged during ban check for export.
    activeFilter      — Current filter pill: 'all'|'pinned'|'banned'|'alts'|'empty'.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 4. DATA MODELS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Group {
    id          : string   — base36(Date.now()) + random 3-char suffix.
    name        : string   — Max 40 chars.
    serverName  : string|null — Max 60 chars.
    createdAt   : number   — Unix ms.
    pinned      : boolean
    banned      : boolean  — Visual flag only; does NOT affect exports.
    alternatives: Alt[]
    cookies     : Cookie[]
    changelog   : Entry[]  — Capped at 30.
    pc          : number   — [OPTIONAL] Panel column preference (1–3).
    lastChecked : number   — [OPTIONAL] Unix ms of last ban check run on this group.
  }

  Cookie {
    username    : string|null
    password    : string|null
    cookie      : string   — MUST start with COOKIE_PFX.
    banStatus   : string   — [OPTIONAL] set by ban checker: 'banned'|'expired'|'facelock'
  }

  Alt {
    id          : string   — base36(Date.now()) + random 3-char suffix.
    label       : string   — Max 40 chars.
    cookies     : Cookie[]
  }

  ChangeEntry {
    t   : number
    msg : string — Trusted HTML string. Never raw user input.
  }

  Settings {
    vaultName       : string
    firstCreated    : number   — Unix ms; correctly preserved by spread merge.
    lastOpen        : string|null — toDateString()
    lastBackup      : number|null
    cardSize        : 'sm'|'md'|'lg'
    streak          : number
    lastGithubSync  : number|null — Unix ms of last successful Gist sync.
  }

  localStorage Keys:
    'saturnity_vault_v1'    → JSON(Group[])
    'cv_cols'            → string(1–4)
    'cv_sort'            → 'az'|'za'|'newest'|'most'
    'cv_settings'        → JSON(Settings)
    'cv_pin_fails'       → string(number)  — PIN failure counter
    'cv_pin_lock_until'  → string(timestamp) — PIN lockout expiry
    'cv_decoy_pin'       → string — Decoy PIN digits (plain, user-set)
    'cv_gh_pat'          → string — GitHub PAT (stored separately, not in settings JSON)
    'cv_gh_gist'         → string — Gist ID
    'cv_gh_enabled'      → '1'|'0'
    'cv_worker_urls'     → JSON(string[]) — CF Worker URLs array (up to 3)

  JSON Export Wrapper:
    { version: 1, exported: <unix ms>, vault: Group[] }
    Import handlers check d.vault is Array. Do not change wrapper shape.

  CF Worker Expected API:
    POST <worker_url>
    Body: { cookie: string, username: string }
    Response: { status: 'active'|'banned'|'expired'|'facelock', duration?: string, error?: string }
    Timeout: 10 seconds (AbortSignal.timeout(10000))

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 5. DESIGN DECISIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  WHY single file:
    Portability — copy one file, open in browser, done. No npm, no server.

  WHY REAL_PIN is hardcoded (not stored):
    If the PIN were stored in localStorage (even hashed), an attacker with
    filesystem access could clear it to bypass the lock. Hardcoding in the file
    means the lock cannot be removed without editing the file itself.

  WHY decoy PIN shows empty vault instead of fake data:
    Generating convincing fake data is complex and fragile. An empty vault is
    plausible ("I don't use this tool much") and trivially safe to implement.
    Decoy mode sets decoyMode=true which makes saveVault() a no-op, so the
    real vault is never touched during a decoy session.

  WHY PIN lockout uses localStorage (cv_pin_lock_until):
    The lockout must survive page refreshes. An in-memory variable would reset
    on reload, trivially defeating the lockout. localStorage persists across reloads.

  WHY GitHub sync uses Gist (not repo file):
    Gist API does not require specifying a repo structure — just a Gist ID.
    PATCH /gists/{id} atomically replaces file content. Simple, reversible, and
    the Gist can be secret (not searchable). No branch management needed.

  WHY GitHub sync is debounced 3 seconds:
    saveVault() is called on every tiny mutation (cookie edit, pin toggle, etc.).
    Debouncing avoids hitting the GitHub API hundreds of times per session.
    3s is long enough to batch rapid changes, short enough to feel responsive.

  WHY offline queue is a simple boolean (ghPendingSync):
    Only the LATEST vault state needs syncing — intermediate states are irrelevant.
    When back online, doGhSync() runs once with the current vault[]. A queue of
    past states would waste bandwidth and complexity.

  WHY ban checker uses round-robin (not random):
    Round-robin ensures all workers are used equally and predictably. If Worker 1
    is rate-limited, the next request goes to Worker 2 automatically. On worker
    error, banWorkerIdx is also incremented to rotate past the failed worker.

  WHY filter uses data attributes on cards (not re-render):
    Re-rendering on every filter click would be expensive and lose scroll position.
    Data attributes set at render time (data-pinned, data-banned, data-alts,
    data-empty) allow applyFilter() to toggle 'dim' class in O(n) without
    touching vault[]. Same approach as the search dim mechanism.

  WHY health score includes GitHub sync freshness:
    Encouraging both local backup AND remote sync gives a fuller picture of data
    safety. A user who never syncs remotely loses points even if local backup
    is current, nudging them to enable GitHub sync.

  WHY COOKIE_PFX is the detection sentinel:
    Roblox auth cookies always begin with '_|WARNING:-DO-NOT-SHARE-THIS.'.
    This string is unique enough to serve as an unambiguous cookie boundary
    in any pasted text format. Never change it.

  WHY color is derived from serverName not stored:
    Deterministic hash means colors survive page reloads without storage.
    All groups under one server share a color for visual cohesion.

  WHY render() rebuilds the full vault DOM on most mutations:
    Simplicity and correctness at the current vault scale. Partial patching is
    used only for high-frequency single-field updates (pin, ban, cookie count).

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 6. RULES  [hard constraints — never violate]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [RULE-01] COOKIE_PFX ('_|WARNING:-DO-NOT-SHARE-THIS.') is the sole cookie
            detection sentinel. Do not change it, shorten it, or make it
            configurable. parseLine() returns null for any line without it.

  [RULE-02] vault[] is the single source of truth. Mutate it, then call
            saveVault() immediately. Never render from any other source.

  [RULE-03] Group IDs are never reused. Sync-vault merge uses ID equality.
            Changing ID generation breaks all existing saved vaults.

  [RULE-04] All user strings rendered into innerHTML MUST go through esc().
            Includes: group.name, serverName, alt.label, username, cookie in
            display. esc() does NOT escape single quotes — use double-quote
            HTML attribute delimiters when interpolating.

  [RULE-05] changelog entries cap at 30 per group (logChange()). Never remove
            this cap — unbounded growth causes localStorage quota errors.

  [RULE-06] saveVault() MUST stay at the top: if(decoyMode)return.
            In decoy mode the real vault must NEVER be written to localStorage.
            Do not move or bypass this guard.

  [RULE-07] saveVault() surfaces QuotaExceededError as an 'err' toast.
            Do not re-silence this error. Do not retry inside saveVault().

  [RULE-08] customConfirm() is async and MUST be awaited. Never replace with
            window.confirm() — removed in v3.1.

  [RULE-09] pending[] must be populated by openAddModal() before confirmAdd()
            or mergeIntoGroup() is called.

  [RULE-10] Per-server group limit is 18. Enforced only in confirmAdd().

  [RULE-11] All modals use openMod(id)/closeMod(id) only. Never set display
            directly on .m-ov elements.

  [RULE-12] JSON export wrapper shape is contractual:
            { version:1, exported:<ms>, vault:Group[] }
            All import handlers check d.vault as Array. Never rename 'vault'.

  [RULE-13] import-f (.json) and update-f (sync) are DISTINCT operations:
            import-f prepends new groups (no review).
            update-f opens review modal (or updates by username for .txt).

  [RULE-14] vault[] is only fully reassigned during purge, delete, and
            json-import. Every reassignment must immediately call saveVault().
            All other mutations use in-place array methods.

  [RULE-15] mkCkItem edit save MUST route to correct cookie array:
            opts.isAlt + valid altIdx → g.alternatives[altIdx].cookies[i]
            otherwise → g.cookies[i]. Never bypass this branch.

  [RULE-16] Copy button in mkCkItem MUST use getCopyFmt() on every click.
            Never pre-compute a static copyFmt — it becomes stale after edits.

  [RULE-17] REAL_PIN ('180801') must never be stored anywhere — not in
            localStorage, not in settings, not in a comment near where it is
            used. It exists only as the constant at the top of the script.
            Decoy PINs are stored as plain text in cv_decoy_pin; this is
            intentional (they protect nothing sensitive, the real PIN is not
            derivable from them).

  [RULE-18] decoyMode must propagate to every vault mutation path.
            saveVault() has the guard. If a new direct localStorage.setItem(SK)
            call is ever added (currently there are none), it must also check
            decoyMode. The real vault must never be overwritten in decoy mode.

  [RULE-19] GitHub PAT is stored in localStorage key 'cv_gh_pat' separately
            from the main settings JSON. Never include it in the exported
            vault JSON. Never log it in any toast or console message.

  [RULE-20] CF Worker round-robin: banWorkerIdx is incremented after each use
            AND after each network error. This ensures a failed worker is
            skipped on the next request, not retried immediately.

  [RULE-21] #powerdown exists in HTML and CSS (CRT shutoff animation) but has
            no JS trigger. Do not remove it. Reserve it for a future feature.

  [RULE-22] PALETTE array (10 entries) must not be reordered. Hash % 10 assigns
            colors — reordering visually re-colors all existing groups.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 7. GUIDELINES  [soft preferences]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [GUIDE-01] Prefer partial DOM updates over full render() for single-card
             changes (pin, ban, cookie count). Use render() only when vault
             structure changes (groups added/removed, server renamed).

  [GUIDE-02] New Group fields: initialize in confirmAdd(), add defensive fallback
             (||default) at every read site, and update DATA MODELS in this header.

  [GUIDE-03] Toast types: 'ok' (green), 'warn' (yellow), 'err' (red) only.

  [GUIDE-04] New detail panel sections must live inside #p-scroll, not in
             .detail-panel root, to stay within the scroll region.

  [GUIDE-05] Do not reorder PALETTE entries. New color entries can be appended
             (increment the modulus if you do — currently 10).

  [GUIDE-06] Animation durations: card entrance stagger 30ms/card, delete 350ms,
             new-glow 3s, fly-in 400ms, stat counter 500ms, PIN glitch 500ms,
             sync dot pulse 1s. Keep new animations within these ranges.

  [GUIDE-07] New persistent settings fields: add to defSettings() with a default.
             loadSettings() spread merge is backwards-compatible by design.

  [GUIDE-08] flavorCount() strings are intentional flavor text. Do not replace.

  [GUIDE-09] When calling mkCkItem() for alt cookies: always pass BOTH
             opts.isAlt:true AND opts.altIdx:N. Never pass only one.

  [GUIDE-10] Ban checker log lines should use btLog(msg, type) — never write to
             bt-log div directly — to ensure consistent formatting and scrolling.

  [GUIDE-11] GitHub sync errors should update the sync dot to 'err' AND set
             ghPendingSync=true so the next saveVault() retries. Never clear
             ghPendingSync without a confirmed successful sync response.

  [GUIDE-12] Health score factors can be tuned, but the maximum must stay 100
             and minimum 0. Grade thresholds: A≥90, B≥75, C≥60, D≥45, F<45.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 8. DEPENDENCIES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  External (CDN, load-time only):
    - Google Fonts: 'Share Tech Mono', 'Rajdhani' (display only)

  External (runtime, optional, user-initiated):
    - GitHub Gist API (https://api.github.com/gists/) — only when GitHub sync
      is enabled and configured. PATCH method only.
    - User-provided Cloudflare Worker URLs — only during ban check runs.
      No data is sent without explicit user action.

  Internal:
    - None. Self-contained single file.

  Browser APIs:
    - localStorage (read/write; quota errors surfaced as toast)
    - navigator.clipboard.writeText() (async, secure context)
    - document.execCommand('copy') (fallback)
    - FileReader API (file import)
    - requestAnimationFrame (tilt, stat animation)
    - fetch() + AbortSignal.timeout() (GitHub sync, ban checker)
    - navigator.onLine + window 'online' event (offline queue)
    - data: URI download (programmatic anchor click)
    - CSS backdrop-filter (blur)
    - CSS.escape() (sidebar scroll-to)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 9. FUNCTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ── PIN Lock ───────────────────────────────────────────

  initPin()
    Params  : none
    Returns : void
    Behavior: Sets vault name in the PIN screen header. Wires .pin-pad click
              handler and keyboard listener (0–9, Backspace, Escape).
              Calls checkPinLock() to restore any active lockout from localStorage.
    Edge    : Must be called AFTER render() so vault name in settings is available.

  checkPinLock()
    Params  : none
    Returns : void
    Behavior: Reads cv_pin_lock_until and cv_pin_fails from localStorage.
              If lockout is active, sets pinLocked=true and calls showPinLockCountdown().

  showPinLockCountdown()
    Params  : none
    Returns : void
    Behavior: Polling loop (500ms) that updates #pin-lock-msg with remaining
              seconds. Clears lockout state and removes localStorage key when
              timer expires.

  handlePinKey(v)
    Params  : v:string — '0'–'9' | 'del' | 'clear'
    Returns : void
    Behavior: Appends digit to pinBuffer (max 6). 'del' removes last char.
              'clear' resets buffer. At 6 digits: calls submitPin().

  updatePinDots()
    Params  : none
    Returns : void
    Behavior: Toggles 'filled' class on .pin-dot elements based on pinBuffer.length.

  submitPin()
    Params  : none
    Returns : void
    Behavior: Compares pinBuffer to REAL_PIN and cv_decoy_pin.
              REAL_PIN match: clears fails, hides screen, decoyMode=false.
              Decoy match: hides screen, decoyMode=true, calls render() (shows empty).
              Wrong: increments pinFails, saves to localStorage, applies lockout
              (≥3 fails: 30s, ≥5 fails: 120s), triggers glitch+shake animations,
              shows fail count in error message.
    Edge    : pinBuffer is always cleared after submit regardless of outcome.
              decoyMode is false by default — only set to true on decoy entry.

  ── GitHub Gist Sync ───────────────────────────────────

  ghEnabled()
    Params  : none
    Returns : boolean — true if PAT, Gist ID, and enabled flag are all set.

  scheduleGhSync()
    Params  : none
    Returns : void
    Behavior: Sets sync dot to 'syncing'. Clears and resets 3s debounce timer
              that calls doGhSync(). Called by saveVault() on every successful write.
    Edge    : No-op if ghEnabled() is false. Does not guard decoyMode separately
              because saveVault() already returns early in decoy mode.

  doGhSync()  [async]
    Params  : none
    Returns : Promise<void>
    Behavior: If offline: sets dot to 'queue', sets ghPendingSync=true, returns.
              Sends PATCH to GitHub Gist API with full vault JSON as file content.
              On success: sets dot to 'ok', saves lastGithubSync to settings,
              clears ghPendingSync.
              On failure: sets dot to 'err', sets ghPendingSync=true, shows toast.

  testGhConnection()  [async]
    Params  : none (reads from #vs-gh-pat and #vs-gh-gist DOM inputs)
    Returns : void
    Behavior: GET /gists/{id} with PAT. Shows 'ok' or error toast. Does not
              modify localStorage — test only.

  ── Vault Settings ─────────────────────────────────────

  openVaultSettings()
    Params  : none
    Returns : void
    Behavior: Populates vault-settings-modal fields from localStorage.
              Opens modal.

  saveVaultSettings()
    Params  : none (reads from DOM inputs)
    Returns : void
    Behavior: Validates decoy PIN (4–8 digits, must differ from REAL_PIN).
              Writes PAT, Gist ID, enabled flag, worker URLs, decoy PIN to
              their respective localStorage keys. Updates sync dot and worker
              status label. Closes modal with success toast.

  ── Filter Bar + Health Score ──────────────────────────

  applyFilter()
    Params  : none (reads activeFilter and #search-in value)
    Returns : void
    Behavior: Iterates all .gcard elements. For each: determines hide based on
              activeFilter (checks data-pinned/banned/alts/empty attributes)
              AND the current search query. Toggles 'dim' class. Both filter
              and search are composited — a card must satisfy both to be shown.
    Edge    : Called after render() via setTimeout(applyFilter, 20) to ensure
              DOM is stable. Also called directly on search input event and
              on filter pill click.

  calcHealthScore()
    Params  : none
    Returns : {score:number, grade:'A'|'B'|'C'|'D'|'F'}
    Behavior: Computes 0–100 score from weighted factors:
              - Backup recency: up to -25 (never=-25, >30d=-25, >7d=-15, >3d=-8, >1d=-3)
              - Ban ratio: up to -20 (proportional to banned groups / total)
              - Empty groups: up to -20 (proportional to empty groups / total)
              - Streak bonus: up to +15 (min(15, floor(streak/2)))
              - GitHub sync: +10 if synced within 24h, +5 within 3 days
              Grade: A≥90, B≥75, C≥60, D≥45, F<45.
    Edge    : Returns {score:0, grade:'F'} for empty vault.

  updateHealthScore()
    Params  : none
    Returns : void
    Behavior: Calls calcHealthScore() and updates #health-score and #health-grade
              elements including the grade CSS class.

  ── Ban Checker Terminal ───────────────────────────────

  getWorkerUrls()
    Params  : none
    Returns : string[] — array of CF Worker URLs from cv_worker_urls (filtered empty)

    Params  : none
    Returns : void
    Behavior: Updates #bt-worker-status text with worker count and color
              (ok if configured, dim if not).

  openBanTerminal() / closeBanTerminal()
    Params  : none
    Returns : void
    Behavior: Adds/removes 'open' class on #ban-terminal-ov. Close also sets
              banCheckAbort=true to halt any running check.

  btLog(msg, type)
    Params  : msg:string, type:'info'|'ok'|'ban'|'warn'|'facelock'|'err'|'muted'
    Returns : void
    Behavior: Appends a timestamped line to #bt-log and auto-scrolls. The msg
              is NOT HTML-escaped — only pass internally-generated strings here.

  btSetProgress(cur, total)
    Params  : cur:number, total:number
    Returns : void
    Behavior: Updates #bt-progress text "N/total".

  callWorker(url, cookie, username)  [async]
    Params  : url:string, cookie:string, username:string
    Returns : Promise<{status:string, duration?:string}>
    Behavior: POST to worker URL with 10s timeout. Throws on non-ok status.

  runBanCheck()  [async]
    Params  : none
    Returns : Promise<void>
    Behavior: Reads getWorkerUrls(), bt-skip-banned checkbox, bt-all-groups checkbox.
              For each group (filtered by skipBanned if checked): for each cookie:
                - Selects url = urls[banWorkerIdx % urls.length]; banWorkerIdx++
                - Calls callWorker() with 120ms inter-request delay (rate limit buffer)
                - On success: classifies by status, logs, increments counters.
                  Pushes banned/expired/facelock cookies to banFailedCookies[].
                - On error: increments banWorkerIdx again (skip failed worker),
                  logs error, increments errors counter.
              Respects banCheckAbort at top of inner loop.
              On completion: enables export button if banFailedCookies.length > 0.
    Edge    : All groups/cookies are from vault[] at call time — not live-updated
              if vault changes during a check. banFailedCookies is reset on each run.

  ── Storage / Existing Functions (unchanged) ──────────────────────────────

  getColor(name) — hash → PALETTE entry, memoized in ccache{}.
  loadSettings() — merge {...defSettings(), ...stored}, correctly preserves firstCreated.
  defSettings()  — defaults object; firstCreated only meaningful on first-ever load.
  saveSettings() — JSON to cv_settings, no error handling (small data).
  saveVault()    — decoyMode guard → localStorage write → scheduleGhSync(). QuotaExceededError toast.
  loadVault()    — parse cv_saturnity_vault_v1, silent on error.
  updateStreak() — daily open counter; open-based, not usage-based.
  setVaultTitle() / openRenameVault() / checkBackupReminder() — unchanged.
  customConfirm(msg, label) — Promise<boolean>, must be awaited, single dialog at a time.
  openMod(id) / closeMod(id) — class toggle only. Backdrop auto-close wired globally.
  openAddModal(parsed, prefillName) — stages pending[], opens add-modal.
  mergeIntoGroup(groupId) — pushes pending[] non-dupes into target group.
  confirmAdd() — creates group (id, name, serverName, createdAt, pinned:false, banned:false,
    alternatives:[], cookies, changelog:[]). Enforces 18-group server limit.
  openUpdateModal(incoming) / makeSection() / commitUpdate() — sync-vault review flow.
  sortVault(arr) — pinned-first, then by sort key. Non-mutating.
  buildSidebar() — rebuilds server items in #sb-nav.
  render() — full vault DOM rebuild + buildSidebar + updateHealthScore + applyFilter.
  mkGrid() / mkCard(group) — card element builder. Sets data-pinned/banned/alts/empty.
  flavorCount(n) — flavor text for cookie count.
  openPanel(id) / closePanel() / refreshPanel() — detail panel lifecycle.
  refreshChangelog(g) — appends .ck-changelog to p-scroll bottom.
  buildAltSection(g) — builds collapsible alternatives section with rebuildEntries().
  mkCkItem(c, i, gid, opts) — cookie item with blur reveal, getCopyFmt(), edit form.
    Edit save routes: opts.isAlt → g.alternatives[altIdx].cookies[i], else g.cookies[i].
  saveEdit() — patches group name/server; full render if server changed.
  openQC(groupId, anchor) / closeQC() — quick-copy popup (main cookies only).
  openBulk(label, groups) / showStats() / animStats() / aNum() — export/stats UI.
  delGroup(id) — animated delete, 5s undo slot (single slot only).
  buildChangelogModal() — renders APP_CHANGELOG into cl-scroll.
  parseLine(line) / parseInput(txt) / fmtLine(c, fmt) / expTxt(g) — data utils.
  fmtTime(ts) / logChange(group, msg) / copyText() / fallbackCopy() — helpers.
  esc(s) / sf(n) / dl(content, filename) / toast(msg, type) — output utils.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 10. KNOWN ISSUES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FIXED IN v4.6 (see VERSION HISTORY):
    BUG-01 through BUG-07, BUG-11 — all resolved.

  ACTIVE — DESIGN DECISIONS (not code bugs):
  [ISSUE-04] expTxt() exports only main g.cookies[]. Alternatives silently omitted.
  [ISSUE-08] Single undo slot. Two rapid deletes lose the first undo.
  [ISSUE-09] Ban flag does not filter exports. Intentional annotation-only design.
  [ISSUE-10] All ungrouped groups share PALETTE[0] color. Hash collision possible.
  [ISSUE-12] Quick Copy only accesses main g.cookies[]. Alts need detail panel.

  ACTIVE — NEW IN v4.7:
  [ISSUE-13] Ban checker uses banCheckAbort flag (cooperative cancellation), not
             AbortController on individual fetch calls. If a single worker request
             hangs at the 10s timeout, the stop button cannot interrupt it mid-request.
             The check pauses until that request resolves or times out.

  [ISSUE-14] decoyMode is a runtime-only flag. If the user closes the browser
             tab during a decoy session and reopens, the real vault is shown on
             the next load (after entering the real PIN). Decoy mode does not
             persist across sessions by design.

  [ISSUE-15] GitHub PAT is stored in localStorage as plain text. This is a
             deliberate trade-off for simplicity. Users should use PATs scoped
             to 'gist' only (minimum privilege) and rotate them periodically.
             Anyone with read access to localStorage can read the PAT.

  [ISSUE-16] Health score's GitHub sync factor only awards points if ghEnabled()
             is true at score calculation time. A user who synced yesterday but
             then disabled sync would score 0 for that factor, which is correct
             (sync is no longer active) but may be surprising.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 11. FAILED APPROACHES  [do not retry]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [FAILED-01] window.confirm() — removed v3.1. Blocks thread, un-styleable.
  [FAILED-02] PIN lock screen — removed v4.0, re-added v4.7 with hardcoded real PIN.
              The v4.0 PIN was stored in localStorage as hash → trivially bypassed
              by clearing localStorage. The v4.7 approach hardcodes the real PIN
              in the file. Do not revert to a stored/hashed PIN.
  [FAILED-03] Per-cookie tag buttons — removed v4.0. Replaced by smart copy button.
  [FAILED-04] Canvas-based animations — removed v3.1. Performance issues.
  [FAILED-05] Per-group color picker — intentionally avoided. Deterministic hash is simpler.
  [FAILED-06] innerHTML for blur spans — DOM nodes required for per-element listeners.
  [FAILED-07] Static copyFmt closure in mkCkItem — stale after inline edits. Fixed v4.6.
  [FAILED-08] AbortController per-request in ban checker — attempted but adds complexity
              when workers share banWorkerIdx state. Simple timeout + cooperative flag
              is sufficient for the 10s worst case.
  [FAILED-09] Storing GitHub PAT inside the main settings JSON — would include PAT
              in every vault export (.json download). Kept separate in cv_gh_pat key.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 12. EXPECTED BEHAVIORS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  INPUT: Open the file in browser
  OUTPUT: PIN lock screen shown. #app is rendered underneath (invisible behind screen).

  INPUT: Enter PIN 180801
  OUTPUT: PIN screen fades out. Real vault loads. decoyMode=false.

  INPUT: Enter configured decoy PIN (e.g. 9999)
  OUTPUT: PIN screen fades out. render() called — vault appears empty. decoyMode=true.
          saveVault() returns early for session duration. Real data untouched.

  INPUT: Enter wrong PIN 3 times
  OUTPUT: Glitch+shake animation on each failure. After 3rd: 30s lockout.
          #pin-lock-msg counts down. Input disabled during lockout.

  INPUT: Enter wrong PIN 5+ times
  OUTPUT: 120s lockout. Fail count shown in error text.

  INPUT: saveVault() called with GitHub sync enabled and device online
  OUTPUT: setSyncDot('syncing') immediately. After 3s debounce: PATCH Gist.
          On success: setSyncDot('ok'). On failure: setSyncDot('err') + toast.

  INPUT: saveVault() called while offline
  OUTPUT: scheduleGhSync() called → doGhSync() detects !navigator.onLine →
          setSyncDot('queue') + ghPendingSync=true. On 'online' event: doGhSync() retries.

  INPUT: Run ban check with 2 workers configured, Worker 1 fails
  OUTPUT: banWorkerIdx incremented twice (once for use, once for failure).
          Next cookie check uses Worker 2. Terminal log shows error for failed request.

  INPUT: Click "export failed" after ban check
  OUTPUT: banFailedCookies[] (banned+expired+facelock) exported as u:p:c .txt download.

  INPUT: Click filter pill "🚫 Banned"
  OUTPUT: All non-banned cards get 'dim' class (opacity 0.15, no pointer events).
          Banned cards remain visible. Search query is composited on top.

  INPUT: Click filter pill then type in search
  OUTPUT: applyFilter() applies BOTH conditions — card must match filter AND search query.

  INPUT: Vault health badge shown after render
  OUTPUT: Score 0–100, grade A/B/C/D/F calculated from backup age, ban ratio,
          empty groups, streak, GitHub sync freshness.

  INPUT: Export vault JSON with GitHub sync enabled
  OUTPUT: JSON does NOT contain the PAT. PAT is in cv_gh_pat key, not in vault JSON.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 13. AI INSTRUCTIONS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  READ ALL BEFORE MODIFYING.

  [AI-01] vault[] is sacred. Every mutation MUST be followed by saveVault().
          saveVault() guards decoyMode and calls scheduleGhSync() internally.

  [AI-02] All user strings into innerHTML MUST use esc(). No exceptions.
          esc() does NOT escape single quotes — use double-quote attributes.

  [AI-03] Do not split this file into multiple files. Single-file is required.

  [AI-04] New Group fields: add default in confirmAdd(), add defensive fallback
          at every read site, update DATA MODELS in this header.

  [AI-05] mkCkItem edit save MUST branch on opts.isAlt (RULE-15). This is
          the v4.6 fix for the critical BUG-01. Do not "simplify" this branch.

  [AI-06] mkCkItem copy button MUST use getCopyFmt() on every click (RULE-16).
          Do not revert to static pre-computed copyFmt.

  [AI-07] Do not use framework patterns. Vanilla JS + imperative DOM only.

  [AI-08] COOKIE_PFX is a load-bearing sentinel. Never change it (RULE-01).

  [AI-09] New modals: HTML with class "m-ov" auto-closes on backdrop click via
          existing querySelectorAll('.m-ov') listener. Use openMod/closeMod only.

  [AI-10] Detail panel additions belong inside #p-scroll (the scroll region).

  [AI-11] PALETTE must not be reordered (RULE-22).

  [AI-12] No additional network requests without user configuration and explicit
          user action. GitHub sync and ban check are both user-initiated and
          user-configured. Do not add silent telemetry or background fetches.

  [AI-13] buildAltSection / rebuildEntries uses closure over g, body, head, chev.
          Do not break closure refs. body.innerHTML is cleared at top of each
          rebuildEntries() call — all listeners inside body are re-created fresh.

  [AI-14] logChange() accepts trusted HTML strings only — never raw user input.

  [AI-15] Three file handlers (#import-f, #import-tf, #update-f) have completely
          different behaviors. Do not conflate them (RULE-13).

  [AI-16] JSON export wrapper { version:1, exported:ms, vault:[] } is contractual.
          Never include cv_gh_pat in the vault JSON export (RULE-19, FAILED-09).

  [AI-17] saveVault() decoyMode guard is at the TOP of the function (RULE-18).
          If you ever add a direct localStorage.setItem(SK,...) elsewhere,
          it MUST also check decoyMode. Currently there are zero such calls.

  [AI-18] GitHub PAT (cv_gh_pat) must never appear in: toast messages, console
          logs, exported JSON, or any visible UI element (RULE-19).

  [AI-19] Ban checker btLog() messages are NOT HTML-escaped. Only pass
          internally-generated strings. Never interpolate raw cookie content
          or usernames directly — use esc() first if you do.

  [AI-20] When calling mkCkItem() for alt cookies: pass BOTH opts.isAlt:true
          AND opts.altIdx:N. Never pass only one of these (GUIDE-09).

  [AI-21] applyFilter() composites activeFilter AND the search query. Any new
          filter dimension must be represented as a data attribute on .gcard
          (set in mkCard) so applyFilter() can read it without touching vault[].

  [AI-22] This documentation header must be updated whenever a function is added
          or removed, a data model field changes, a bug is fixed (move to FIXED),
          a new rule is established, or the version number changes.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 14. VERSION HISTORY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  v4.7 (current) — Feature release
    ADD   : PIN lock screen — 6-digit on-screen keypad, keyboard support,
            configurable decoy PIN (shows empty vault), 30s/120s lockout on
            repeated failures, glitch+shake animation on wrong PIN,
            lockout state survives page refresh via localStorage.
    ADD   : GitHub Gist auto-sync — PAT + Gist ID stored separately,
            3s debounced save, sync dot indicator (off/syncing/ok/err/queue),
            offline queue retries on reconnect, test connection button.
    ADD   : Ban checker terminal — slide-up terminal panel, CF Worker round-robin
            (up to 3 URLs), active/banned/expired/facelock classification,
            smart skip already-banned groups, per-request 120ms delay,
            failed worker rotation, export flagged cookies as u:p:c .txt.
    ADD   : Filter bar — All/Pinned/Banned/Has Alts/Empty filter pills,
            composited with search query, data-* attrs on .gcard for O(n) filter.
    ADD   : Vault health score — 0–100 score + A–F grade from backup age,
            ban ratio, empty groups, streak, GitHub sync freshness.
    ADD   : Vault Settings modal — unified GitHub, CF Workers, and decoy PIN config.
    ADD   : Sidebar dock: "ban check" and "vault settings" commands.

  v4.6 — Bug fix release
    FIXED : BUG-01 Alt cookie edit write routing. BUG-02 Alt ID collision.
            BUG-03 Dead sb-changelog reference. BUG-06 Quota error surfacing.
            BUG-07 Tilt/entrance animation conflict. BUG-11 Stale copy format.
    DOCS  : All inference markers resolved. 6 new RULES. 20 AI instructions.

  v4.5
    ADD   : Ban tag (group.banned, card overlay, panel button).
    ADD   : Alternatives system (named alt cookie sets per group).
    ADD   : Alt badge on cards.

  v4.0
    REMOVE: PIN lock screen (re-added v4.7 with hardcoded PIN).
    REMOVE: Per-cookie copy/tag buttons.
    ADD   : Smart copy button, inline edit, sync vault modal, header buttons.
    CHANGE: Sidebar → icon command dock.

  v3.1
    FIX   : 28 bugs. Custom confirm. PIN as hash. Dead code removed.
-->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Saturnity Vault</title>
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'%3E%3Ccircle cx='50' cy='50' r='18' fill='%237b2fff'/%3E%3Cellipse cx='50' cy='50' rx='40' ry='11' fill='none' stroke='%2300d4ff' stroke-width='4.5' transform='rotate(-25 50 50)'/%3E%3Ccircle cx='50' cy='50' r='8' fill='%239b4fff'/%3E%3C/svg%3E">
<link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Rajdhani:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
:root{
  --bg:#06090f;--surf:rgba(13,21,32,.88);--surf2:rgba(17,29,46,.92);
  --solid:#0d1520;--bdr:rgba(26,48,80,.8);--bdrb:rgba(15,111,255,.4);
  --ac:#0f6fff;--a2:#00d4ff;--a3:#7b2fff;
  --txt:#c8daf0;--dim:#4a6a8a;--bright:#eaf4ff;
  --danger:#ff3060;--ok:#00ffaa;--warn:#ffaa00;
  --mono:'Share Tech Mono',monospace;--sans:'Rajdhani',sans-serif;
  --sw:230px;--hh:56px;
}
*{margin:0;padding:0;box-sizing:border-box;}
html,body{height:100%;overflow:hidden;}
body{background:var(--bg);color:var(--txt);font-family:var(--sans);display:flex;flex-direction:column;}
body::before{content:'';position:fixed;inset:0;pointer-events:none;z-index:0;
  background-image:
    radial-gradient(ellipse 60% 50% at 15% 10%,rgba(15,111,255,.07) 0%,transparent 70%),
    radial-gradient(ellipse 50% 40% at 85% 85%,rgba(123,47,255,.06) 0%,transparent 70%),
    linear-gradient(rgba(15,111,255,.012) 1px,transparent 1px),
    linear-gradient(90deg,rgba(15,111,255,.012) 1px,transparent 1px);
  background-size:100% 100%,100% 100%,38px 38px,38px 38px;}

/* ── APP SHELL ── */
#app{display:flex;flex-direction:column;height:100%;position:relative;z-index:1;overflow:hidden;}

/* ── HEADER ── */
.hdr{height:var(--hh);display:flex;align-items:center;padding:0 14px;gap:10px;
  border-bottom:1px solid var(--bdr);background:rgba(6,9,15,.92);backdrop-filter:blur(14px);
  flex-shrink:0;position:relative;z-index:10;}
.hdr-icon{width:30px;height:30px;background:linear-gradient(135deg,var(--ac),var(--a3));
  border-radius:8px;display:flex;align-items:center;justify-content:center;
  box-shadow:0 0 14px rgba(15,111,255,.35);flex-shrink:0;cursor:pointer;transition:transform .15s;}
.hdr-icon:hover{transform:scale(1.08);}
.hdr-title{font-family:var(--sans);font-weight:700;font-size:16px;letter-spacing:2px;
  text-transform:uppercase;color:var(--bright);cursor:pointer;white-space:nowrap;}
.hdr-title span{color:var(--a2);}
.hdr-stats{display:flex;gap:1px;border:1px solid var(--bdr);border-radius:8px;overflow:hidden;flex-shrink:0;}
.stat-chip{display:flex;flex-direction:column;align-items:center;justify-content:center;
  padding:4px 12px;background:rgba(255,255,255,.02);border-right:1px solid var(--bdr);}
.stat-chip:last-child{border-right:none;}
.stat-v{font-family:var(--mono);font-size:13px;font-weight:700;color:var(--bright);line-height:1;}
.stat-l{font-family:var(--mono);font-size:8px;color:var(--dim);letter-spacing:1.5px;text-transform:uppercase;margin-top:2px;}
.hdr-search{flex:1;max-width:320px;position:relative;}
.hdr-search input{width:100%;background:rgba(255,255,255,.04);border:1px solid var(--bdr);
  border-radius:8px;padding:8px 32px 8px 32px;font-family:var(--mono);font-size:12px;color:var(--txt);
  outline:none;transition:all .15s;}
.hdr-search input:focus{border-color:var(--ac);background:rgba(15,111,255,.06);}
.hdr-search input::placeholder{color:var(--dim);}
.srch-ico{position:absolute;left:9px;top:50%;transform:translateY(-50%);color:var(--dim);pointer-events:none;}
.srch-clear{position:absolute;right:8px;top:50%;transform:translateY(-50%);background:none;border:none;
  color:var(--dim);cursor:pointer;font-size:13px;line-height:1;padding:2px 4px;display:none;
  transition:color .12s;}
.srch-clear:hover{color:var(--bright);}
.srch-clear.visible{display:block;}
.hdr-right{display:flex;align-items:center;gap:6px;margin-left:auto;flex-shrink:0;}
.sort-btn,.card-size-btn{background:rgba(255,255,255,.04);border:1px solid var(--bdr);border-radius:7px;
  padding:6px 9px;font-family:var(--mono);font-size:10px;color:var(--dim);cursor:pointer;
  letter-spacing:1px;transition:all .12s;white-space:nowrap;}
.sort-btn:hover,.card-size-btn:hover{border-color:var(--ac);color:var(--a2);}
.col-pills{display:flex;gap:3px;background:rgba(255,255,255,.03);border:1px solid var(--bdr);border-radius:8px;padding:3px;}
.col-pill{font-family:var(--mono);font-size:10px;width:24px;height:24px;border-radius:5px;border:none;
  background:transparent;color:var(--dim);cursor:pointer;transition:all .12s;display:flex;align-items:center;justify-content:center;}
.col-pill.on{background:var(--ac);color:#fff;}
.col-pill:not(.on):hover{color:var(--a2);}
.btn-add{background:linear-gradient(135deg,var(--ac),var(--a3));border:none;border-radius:8px;
  padding:7px 14px;font-family:var(--sans);font-weight:700;font-size:12px;letter-spacing:1.5px;
  color:#fff;cursor:pointer;box-shadow:0 0 14px rgba(15,111,255,.3);transition:all .15s;white-space:nowrap;}
.btn-add:hover{box-shadow:0 0 22px rgba(15,111,255,.5);transform:translateY(-1px);}
/* Header meta buttons: stats + changelog */
.hdr-meta{display:flex;gap:0px;}
.hdr-meta-btn{background:none;border:none;border-bottom:2px solid transparent;border-radius:0;
  padding:5px 9px 4px;cursor:pointer;transition:color .12s,border-color .12s;display:flex;align-items:center;gap:5px;
  font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;text-transform:uppercase;}
.hdr-meta-btn:hover{color:var(--bright);border-bottom-color:rgba(0,212,255,.35);}
.hdr-meta-btn.hdr-active{color:var(--a2);border-bottom-color:var(--a2);}
.hdr-meta-btn svg{opacity:.45;transition:opacity .12s;}
.hdr-meta-btn:hover svg,.hdr-meta-btn.hdr-active svg{opacity:1;}

/* ── BODY LAYOUT ── */
.app-body{flex:1;display:flex;overflow:hidden;}

/* ── SIDEBAR ── */
.sidebar{width:var(--sw);flex-shrink:0;border-right:1px solid var(--bdr);
  background:rgba(6,9,15,.7);display:flex;flex-direction:column;overflow:hidden;}
.sb-hd{padding:12px 13px 9px;border-bottom:1px solid var(--bdr);flex-shrink:0;}
.sb-lbl{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;}
.sb-nav{flex:1;overflow-y:auto;padding:6px 0;}
.sb-nav::-webkit-scrollbar{width:3px;}
.sb-nav::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.sb-all{font-family:var(--mono);font-size:10px;letter-spacing:1px;color:var(--dim);
  padding:8px 13px;cursor:pointer;transition:color .12s;display:flex;align-items:center;gap:8px;}
.sb-all:hover,.sb-all.on{color:var(--a2);}
.sb-div{height:1px;background:var(--bdr);margin:5px 13px;}
.sb-item{display:flex;align-items:center;gap:9px;padding:8px 13px;cursor:pointer;transition:all .12s;position:relative;}
.sb-item::before{content:'';position:absolute;left:0;top:0;bottom:0;width:2px;background:transparent;transition:background .15s;}
.sb-item:hover{background:rgba(15,111,255,.06);}
.sb-item.on{background:rgba(15,111,255,.1);}
.sb-item.on::before{background:var(--a2);}
.sb-dot{width:7px;height:7px;border-radius:50%;flex-shrink:0;box-shadow:0 0 6px currentColor;}
.sb-name{font-family:var(--sans);font-weight:600;font-size:13px;color:var(--txt);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;}
.sb-item.on .sb-name{color:var(--bright);}
.sb-badge{font-family:var(--mono);font-size:9px;color:var(--dim);flex-shrink:0;}

/* ── SIDEBAR COMMAND DOCK ── */
.sb-dock{padding:10px;border-top:1px solid var(--bdr);flex-shrink:0;
  background:rgba(0,0,0,.3);}
.sb-dock-label{font-family:var(--sans);font-weight:700;font-size:11px;color:var(--dim);letter-spacing:2px;
  text-transform:uppercase;margin-bottom:10px;padding:0 2px;}
.sb-dock-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px;}
.dock-cmd{display:flex;align-items:center;gap:10px;padding:12px 14px;
  background:rgba(255,255,255,.02);border:1px solid var(--bdr);border-radius:10px;
  cursor:pointer;transition:all .15s;position:relative;overflow:hidden;min-height:56px;}
.dock-cmd::before{content:'';position:absolute;inset:0;
  background:linear-gradient(135deg,rgba(255,255,255,.03),transparent);pointer-events:none;}
.dock-cmd:hover{border-color:var(--cc,var(--ac));background:rgba(var(--cr,15,111,255),.08);
  box-shadow:0 0 12px rgba(var(--cr,15,111,255),.15);}
.dock-cmd svg{flex-shrink:0;opacity:.6;transition:opacity .15s;}
.dock-cmd:hover svg{opacity:1;}
.dock-cmd-txt{font-family:var(--sans);font-weight:600;font-size:13px;color:var(--dim);letter-spacing:.3px;
  line-height:1.2;transition:color .15s;}
.dock-cmd:hover .dock-cmd-txt{color:var(--bright);}
.dock-cmd.full{grid-column:1/-1;}
.dock-cmd.danger:hover{border-color:var(--danger);background:rgba(255,48,96,.08);}
.dock-cmd.danger:hover svg{color:var(--danger);}
.dock-cmd.danger:hover .dock-cmd-txt{color:var(--danger);}
.dock-cmd.update-cmd{--cc:var(--a2);--cr:0,212,255;}
.dock-cmd.update-cmd:hover{border-color:var(--a2);}

/* ── MAIN ── */
.main{flex:1;overflow-y:auto;overflow-x:hidden;padding:16px;scroll-behavior:smooth;}
.main::-webkit-scrollbar{width:5px;}
.main::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:3px;}

/* ── PASTE PANEL ── */
.paste-panel{background:rgba(4,8,14,.95);border:1px solid rgba(0,212,255,.2);border-radius:10px;
  margin-bottom:16px;overflow:hidden;transition:border-color .2s;
  box-shadow:0 0 20px rgba(0,212,255,.04);}
.paste-panel:focus-within{border-color:var(--a2);box-shadow:0 0 0 1px rgba(0,212,255,.12);}
.paste-hd{display:flex;align-items:center;gap:10px;padding:8px 14px;border-bottom:1px solid rgba(0,212,255,.12);
  cursor:pointer;user-select:none;background:rgba(0,212,255,.04);}
.paste-hd-title{font-family:var(--mono);font-size:10px;letter-spacing:2px;color:var(--a2);flex:1;text-transform:uppercase;}
.paste-hd-title::before{content:'> ';opacity:.5;}
.paste-chev{color:var(--dim);font-size:11px;transition:transform .2s;}
.paste-panel.open .paste-chev{transform:rotate(180deg);}
.paste-body{display:none;}
.paste-panel.open .paste-body{display:block;}
.paste-ta{width:100%;background:transparent;border:none;outline:none;padding:14px 16px;
  font-family:var(--mono);font-size:12px;color:var(--ok);resize:none;min-height:100px;line-height:1.8;
  caret-color:var(--a2);}
.paste-ta::placeholder{color:var(--dim);opacity:.4;}
.paste-ft{display:flex;align-items:center;justify-content:space-between;padding:8px 14px;
  border-top:1px solid rgba(0,212,255,.1);background:rgba(0,0,0,.2);gap:8px;}
.paste-info{font-family:var(--mono);font-size:10px;color:var(--dim);}
.paste-info span{color:var(--ok);}
.paste-ft-btns{display:flex;gap:8px;flex-shrink:0;}
.btn-primary{background:linear-gradient(135deg,var(--ac),var(--a3));border:none;border-radius:7px;
  padding:8px 16px;font-family:var(--sans);font-weight:700;font-size:12px;letter-spacing:1.5px;
  color:#fff;cursor:pointer;box-shadow:0 0 12px rgba(15,111,255,.3);transition:all .15s;}
.btn-primary:hover{box-shadow:0 0 20px rgba(15,111,255,.5);transform:translateY(-1px);}
.btn-primary:disabled{opacity:.3;pointer-events:none;}

/* ── BACKUP BANNER ── */
.backup-banner{background:rgba(255,170,0,.08);border:1px solid rgba(255,170,0,.25);border-radius:9px;
  padding:9px 14px;margin-bottom:14px;display:none;align-items:center;gap:10px;}
.backup-banner.show{display:flex;}
.bb-txt{font-family:var(--mono);font-size:10px;color:var(--warn);flex:1;letter-spacing:.5px;}
.bb-btn{background:rgba(255,170,0,.15);border:1px solid rgba(255,170,0,.3);border-radius:5px;
  padding:4px 10px;font-family:var(--mono);font-size:9px;color:var(--warn);cursor:pointer;transition:all .12s;}
.bb-btn:hover{background:rgba(255,170,0,.25);}
.bb-x{background:none;border:none;color:var(--dim);cursor:pointer;font-size:13px;}

/* ── UPDATE LOG BANNER ── */
.update-log{background:rgba(0,212,255,.05);border:1px solid rgba(0,212,255,.2);border-radius:9px;
  padding:10px 14px;margin-bottom:14px;display:none;flex-direction:column;gap:7px;}
.update-log.show{display:flex;}
.update-log-hd{display:flex;align-items:center;justify-content:space-between;}
.update-log-title{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--a2);text-transform:uppercase;}
.update-log-x{background:none;border:none;color:var(--dim);cursor:pointer;font-size:13px;}
.update-log-list{display:flex;flex-direction:column;gap:3px;max-height:120px;overflow-y:auto;}
.update-log-list::-webkit-scrollbar{width:3px;}
.update-log-list::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.update-log-row{display:flex;align-items:center;gap:8px;padding:3px 0;border-bottom:1px solid rgba(26,48,80,.4);}
.update-log-row:last-child{border-bottom:none;}
.update-log-user{font-family:var(--mono);font-size:10px;color:var(--bright);flex:1;}
.update-log-group{font-family:var(--mono);font-size:9px;color:var(--dim);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:120px;}
.update-log-badge{font-family:var(--mono);font-size:8px;color:var(--a2);background:rgba(0,212,255,.1);
  border:1px solid rgba(0,212,255,.2);border-radius:3px;padding:1px 5px;flex-shrink:0;}

/* ── SECTIONS ── */
.server-sec{margin-bottom:24px;scroll-margin-top:14px;}
.sec-head{display:flex;align-items:center;gap:10px;margin-bottom:10px;padding-bottom:8px;border-bottom:1px solid var(--bdr);}
.sec-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;}
.sec-name{font-family:var(--sans);font-weight:700;font-size:15px;letter-spacing:1px;color:var(--bright);flex:1;}
.sec-name-wrap{display:flex;align-items:center;gap:6px;flex:1;min-width:0;}
.sec-rename-btn{background:none;border:none;color:var(--dim);cursor:pointer;font-size:13px;
  padding:2px 5px;border-radius:4px;transition:all .12s;opacity:.5;flex-shrink:0;}
.sec-rename-btn:hover{opacity:1;color:var(--a2);}
.sec-name-input{background:rgba(0,0,0,.4);border:1px solid var(--ac);border-radius:5px;
  font-family:var(--sans);font-weight:700;font-size:15px;letter-spacing:1px;color:var(--bright);
  padding:2px 8px;outline:none;width:100%;max-width:200px;}
.sec-meta{font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;}
.sec-expbtn{background:none;border:1px solid var(--bdr);border-radius:6px;padding:4px 9px;
  font-family:var(--mono);font-size:9px;letter-spacing:1px;color:var(--dim);cursor:pointer;transition:all .12s;}
.sec-expbtn:hover{border-color:var(--a3);color:var(--a3);}
.sec-copybtn{background:none;border:1px solid var(--bdr);border-radius:6px;padding:4px 7px;
  color:var(--dim);cursor:pointer;transition:all .12s;display:inline-flex;align-items:center;}
.sec-copybtn:hover{border-color:var(--ok);color:var(--ok);}
.sec-warn{font-family:var(--mono);font-size:9px;color:var(--warn);background:rgba(255,170,0,.08);
  border:1px solid rgba(255,170,0,.2);border-radius:5px;padding:2px 7px;letter-spacing:1px;}
.card-grid{display:grid;grid-template-columns:repeat(var(--cols,2),1fr);gap:10px;}
.ug-sec{margin-bottom:20px;}
.ug-lbl{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;
  margin-bottom:10px;padding-bottom:8px;border-bottom:1px solid var(--bdr);}

/* ── CARDS ── */
.gcard{background:var(--surf);border:1px solid var(--bdr);border-radius:14px;
  overflow:hidden;cursor:pointer;aspect-ratio:1/1;
  transition:border-color .2s,box-shadow .2s,opacity .3s;
  position:relative;display:flex;flex-direction:column;
  opacity:0;transform:translateY(10px);user-select:none;touch-action:manipulation;will-change:opacity,transform;}
.gcard.vis{opacity:1;transform:translateY(0);
  transition:opacity .35s ease,transform .35s cubic-bezier(.34,1.3,.64,1),border-color .2s,box-shadow .2s;}
.gcard.new-glow{animation:newglow 3s ease forwards;}
@keyframes newglow{
  0%{border-color:var(--cc,var(--ac));box-shadow:0 0 30px rgba(var(--cr,15,111,255),.5);}
  100%{border-color:var(--bdr);box-shadow:none;}}
.gcard::before{content:'';position:absolute;inset:0;
  background:linear-gradient(135deg,rgba(255,255,255,.025) 0%,transparent 55%);pointer-events:none;z-index:1;}
.gcard:hover{border-color:var(--cc,var(--ac));box-shadow:0 0 18px rgba(var(--cr,15,111,255),.25);}
.gcard.dim{opacity:.15;pointer-events:none;}
.gcard.deleting{animation:cardDel .35s ease forwards;}
@keyframes cardDel{to{opacity:0;transform:scale(.85) translateY(6px);}}
.gcard.fly-in{animation:flyIn .4s cubic-bezier(.34,1.5,.64,1);}
@keyframes flyIn{from{opacity:0;transform:translateX(60px) scale(.95)}to{opacity:1;transform:none}}
.card-qc-btn{position:absolute;bottom:5px;right:5px;z-index:5;
  background:rgba(0,0,0,.55);border:1px solid rgba(255,255,255,.1);border-radius:4px;
  font-family:var(--mono);font-size:7px;color:rgba(255,255,255,.3);
  padding:2px 5px;cursor:pointer;letter-spacing:.5px;transition:all .15s;line-height:1.3;}
.card-qc-btn:hover,.card-qc-btn:active{color:var(--a2);border-color:var(--bdrb);background:rgba(15,111,255,.2);}
.gcard-bar{height:2px;flex-shrink:0;opacity:.7;}
.gcard-body{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;
  gap:clamp(4px,1vw,7px);padding:clamp(7px,2vw,12px);text-align:center;min-width:0;}
.gcard-dot{border-radius:50%;flex-shrink:0;box-shadow:0 0 8px currentColor;}
.gcard-name{font-family:var(--sans);font-weight:700;color:var(--bright);letter-spacing:.5px;line-height:1.2;word-break:break-word;max-width:100%;}
.gcard-count{font-family:var(--mono);color:var(--cc,var(--a2));background:rgba(var(--cr,0,212,255),.08);
  border:1px solid rgba(var(--cr,0,212,255),.15);border-radius:20px;white-space:nowrap;}
.gcard-status{font-family:var(--mono);font-size:10px;color:var(--dim);margin-top:2px;line-height:1.4;text-align:center;}
.gcard-status .s-ban{color:var(--danger);}
.gcard-status .s-exp{color:var(--warn);}
.gcard-status .s-face{color:#ff6b00;}
.gcard-status .s-ok{color:var(--ok);}
.gcard-srv{font-family:var(--mono);color:var(--cc,var(--a3));background:rgba(var(--cr,123,47,255),.1);
  border:1px solid rgba(var(--cr,123,47,255),.2);border-radius:20px;max-width:100%;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.gcard-pin{position:absolute;top:7px;right:8px;font-size:11px;opacity:.7;}

body[data-csize="sm"] .gcard-dot{width:6px;height:6px;}
body[data-csize="sm"] .gcard-name{font-size:clamp(8px,1.4vw,11px);}
body[data-csize="sm"] .gcard-count{font-size:clamp(7px,1vw,9px);padding:1px clamp(3px,.8vw,6px);}
body[data-csize="sm"] .gcard-srv{font-size:clamp(6px,.9vw,8px);padding:1px clamp(3px,.8vw,6px);}
body[data-csize="md"] .gcard-dot{width:clamp(6px,1.2vw,9px);height:clamp(6px,1.2vw,9px);}
body[data-csize="md"] .gcard-name{font-size:clamp(9px,1.8vw,14px);}
body[data-csize="md"] .gcard-count{font-size:clamp(8px,1.2vw,10px);padding:1px clamp(4px,1vw,8px);}
body[data-csize="md"] .gcard-srv{font-size:clamp(7px,1vw,9px);padding:1px clamp(4px,1vw,8px);}
body[data-csize="lg"] .gcard-dot{width:clamp(8px,1.6vw,12px);height:clamp(8px,1.6vw,12px);}
body[data-csize="lg"] .gcard-name{font-size:clamp(11px,2.2vw,17px);}
body[data-csize="lg"] .gcard-count{font-size:clamp(10px,1.5vw,13px);padding:2px clamp(6px,1.2vw,11px);}
body[data-csize="lg"] .gcard-srv{font-size:clamp(9px,1.2vw,11px);padding:2px clamp(6px,1.2vw,11px);}

.exp-tile{aspect-ratio:1/1;border:1px dashed rgba(123,47,255,.3);border-radius:14px;
  display:flex;flex-direction:column;align-items:center;justify-content:center;gap:6px;cursor:pointer;
  background:rgba(123,47,255,.04);transition:all .15s;color:var(--a3);user-select:none;
  opacity:0;transform:translateY(10px);}
.exp-tile.vis{opacity:1;transform:translateY(0);transition:opacity .35s ease,transform .35s cubic-bezier(.34,1.3,.64,1);}
.exp-tile:hover{background:rgba(123,47,255,.12);border-color:var(--a3);box-shadow:0 0 16px rgba(123,47,255,.2);}
.exp-tile span{font-family:var(--mono);font-size:9px;letter-spacing:1px;}

.empty-state{text-align:center;padding:70px 20px;color:var(--dim);}

/* ── LIST VIEW ── */
body.list-view .card-grid{display:flex;flex-direction:column;gap:3px;}
body.list-view .exp-tile{display:none;}
body.list-view .gcard{aspect-ratio:unset;min-height:44px;height:auto;border-radius:8px;flex-direction:row;align-items:stretch;overflow:hidden;}
body.list-view .gcard-bar{width:3px;flex-shrink:0;}
body.list-view .gcard-body{flex-direction:column;align-items:flex-start;justify-content:center;gap:3px;padding:6px 44px 6px 10px;text-align:left;flex:1;min-width:0;}
body.list-view .gcard-dot{width:7px!important;height:7px!important;flex-shrink:0;display:none;}
body.list-view .gcard-row1{display:flex;align-items:center;gap:8px;width:100%;}
body.list-view .gcard-name{font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:200px;}
body.list-view .gcard-count{font-size:9px;padding:1px 7px;flex-shrink:0;white-space:nowrap;}
body.list-view .gcard-srv{font-size:9px;padding:1px 7px;flex-shrink:0;max-width:90px;overflow:hidden;text-overflow:ellipsis;}
body.list-view .gcard-status{margin-top:0;font-size:9px;flex-shrink:0;}
body.list-view .gcard-alt-badge{font-size:7px;padding:1px 5px;flex-shrink:0;}
body.list-view .gcard-pin{top:8px;right:60px;}
body.list-view .gcard-banned-tag{top:8px;left:8px;font-size:8px;padding:1px 4px;}
body.list-view .card-qc-btn{display:none;}
body.list-view .gcard::before{display:none;}
/* Username pills row */
.gcard-users-row{display:none;}
body.list-view .gcard-users-row{display:flex;flex-wrap:wrap;gap:3px;margin-top:1px;}
.gcard-rename-btn{display:none;background:none;border:1px solid rgba(255,255,255,.1);border-radius:4px;
  padding:2px 5px;color:var(--dim);cursor:pointer;flex-shrink:0;transition:all .12s;line-height:1;}
body.list-view .gcard-rename-btn{display:flex;align-items:center;}
body.list-view .gcard-rename-btn:hover{border-color:var(--a2);color:var(--a2);}
.gcard-user-pill{font-family:var(--mono);font-size:8px;color:var(--dim);background:rgba(255,255,255,.05);
  border:1px solid rgba(255,255,255,.08);border-radius:3px;padding:1px 5px;white-space:nowrap;line-height:1.5;}
.gcard-user-pill.banned-user{text-decoration:line-through;opacity:.5;color:var(--danger);}
.gcard-user-pill.more{color:var(--dim);border-style:dashed;}
.list-view-btn{background:none;border:1px solid var(--bdr);border-radius:7px;padding:6px 9px;
  font-family:var(--mono);font-size:10px;color:var(--dim);cursor:pointer;letter-spacing:1px;
  transition:all .12s;white-space:nowrap;display:flex;align-items:center;gap:5px;}
.list-view-btn:hover{border-color:var(--ac);color:var(--a2);}
.list-view-btn.active{border-color:var(--a2);color:var(--a2);background:rgba(0,212,255,.08);}
.list-view-btn svg{opacity:.6;}
.empty-state p{font-family:var(--mono);font-size:12px;letter-spacing:1px;line-height:1.9;}

/* ── SWAP / MOVE / SYNC CSS ── */
.swap-tabs{display:flex;gap:0;border-bottom:1px solid var(--bdr);}
.swap-tab{background:none;border:none;border-bottom:2px solid transparent;padding:7px 14px;
  font-family:var(--mono);font-size:10px;color:var(--dim);cursor:pointer;letter-spacing:.5px;
  transition:all .12s;text-transform:uppercase;}
.swap-tab.on{color:var(--a2);border-bottom-color:var(--a2);}
.swap-reason-btn{background:rgba(255,255,255,.04);border:1px solid var(--bdr);border-radius:7px;
  padding:7px 14px;font-family:var(--mono);font-size:10px;color:var(--dim);cursor:pointer;
  transition:all .12s;flex:1;}
.swap-reason-btn.on{border-color:var(--a2);color:var(--a2);background:rgba(0,212,255,.08);}
.move-group-opt{background:rgba(255,255,255,.03);border:1px solid var(--bdr);border-radius:7px;
  padding:9px 12px;cursor:pointer;transition:all .12s;font-family:var(--sans);font-size:12px;
  font-weight:600;color:var(--txt);text-align:left;width:100%;}
.move-group-opt:hover{border-color:var(--a2);color:var(--a2);background:rgba(0,212,255,.06);}
.swap-alt-opt{background:rgba(123,47,255,.05);border:1px solid rgba(123,47,255,.2);border-radius:7px;
  padding:8px 12px;cursor:pointer;transition:all .12s;font-family:var(--mono);font-size:11px;color:var(--txt);}
.swap-alt-opt:hover,.swap-alt-opt.selected{border-color:var(--a2);background:rgba(0,212,255,.08);}
.swap-alt-opt .alt-label{font-size:10px;color:var(--a3);font-weight:700;margin-bottom:2px;}
.swap-alt-opt .alt-cookies{font-size:9px;color:var(--dim);}

/* ── EXPORT POPUP ── */
.exp-popup{position:fixed;z-index:500;background:rgba(7,11,18,.98);border:1px solid var(--bdrb);
  border-radius:12px;padding:6px;min-width:220px;box-shadow:0 8px 32px rgba(0,0,0,.7);
  display:none;animation:qcIn .15s ease;}
.exp-popup.open{display:block;}
.exp-pop-label{font-family:var(--mono);font-size:8px;color:var(--dim);letter-spacing:2px;
  padding:6px 12px 4px;text-transform:uppercase;border-bottom:1px solid var(--bdr);margin-bottom:4px;}
.exp-pop-btn{display:flex;align-items:center;gap:10px;width:100%;background:none;border:none;
  border-radius:7px;padding:9px 12px;cursor:pointer;transition:all .12s;text-align:left;}
.exp-pop-btn:hover{background:rgba(15,111,255,.1);}
.exp-pop-btn svg{flex-shrink:0;opacity:.8;}
.exp-pop-btn-main{font-family:var(--mono);font-size:12px;font-weight:700;color:var(--bright);flex-shrink:0;min-width:60px;}
.exp-pop-btn-sub{font-family:var(--mono);font-size:9px;color:var(--dim);margin-left:auto;}
.exp-pop-sep{height:1px;background:var(--bdr);margin:4px 6px;}

/* ── SIDEBAR COMMANDS ── */
.sb-dock{padding:10px;border-top:1px solid var(--bdr);flex-shrink:0;}
.sb-dock-label{font-family:var(--sans);font-weight:700;font-size:10px;color:var(--dim);letter-spacing:2px;
  text-transform:uppercase;padding:0 4px 8px;opacity:.5;}
.sb-dock-grid{display:flex;flex-direction:column;gap:4px;}
.dock-cmd{display:flex;align-items:center;gap:10px;padding:9px 12px;border-radius:8px;
  border:1px solid var(--bdr);background:rgba(255,255,255,.02);cursor:pointer;
  transition:all .12s;position:relative;overflow:hidden;}
.dock-cmd:hover{border-color:var(--cc,var(--ac));background:rgba(var(--cr,15,111,255),.08);}
.dock-cmd svg{flex-shrink:0;opacity:.6;transition:opacity .15s;}
.dock-cmd:hover svg{opacity:1;}
.dock-cmd-txt{font-family:var(--sans);font-weight:600;font-size:12px;color:var(--dim);letter-spacing:.3px;}
.dock-cmd:hover .dock-cmd-txt{color:var(--bright);}
.dock-cmd.danger:hover{border-color:var(--danger);background:rgba(255,48,96,.08);}
.dock-cmd.danger:hover svg{color:var(--danger);}
.dock-cmd.danger:hover .dock-cmd-txt{color:var(--danger);}

/* ── VAULT SETTINGS MODAL ── */
.vault-settings-modal{width:min(92vw,420px);max-height:82vh;display:flex;flex-direction:column;}
.vault-settings-scroll{overflow-y:auto;flex:1;padding-right:4px;}
.vault-settings-scroll::-webkit-scrollbar{width:3px;}
.vault-settings-scroll::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.vsec{background:rgba(255,255,255,.02);border:1px solid var(--bdr);border-radius:10px;padding:14px 16px;margin-bottom:10px;}
.vsec:last-child{margin-bottom:0;}
.vsec-title{font-family:var(--sans);font-weight:700;font-size:12px;color:var(--bright);margin-bottom:12px;
  display:flex;align-items:center;gap:6px;}
.vtoggle{display:flex;align-items:center;gap:10px;font-family:var(--sans);font-size:13px;
  color:var(--txt);margin-bottom:10px;cursor:pointer;}
.vtoggle input{width:16px;height:16px;accent-color:var(--a2);cursor:pointer;}
.vrow{display:flex;flex-direction:column;gap:4px;margin-bottom:10px;}
.vrow:last-child{margin-bottom:0;}
.vrow label{font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;text-transform:uppercase;}
.vrow input{background:rgba(255,255,255,.04);border:1px solid var(--bdr);border-radius:7px;
  padding:8px 10px;font-family:var(--mono);font-size:11px;color:var(--bright);outline:none;
  transition:border-color .15s;}
.vrow input:focus{border-color:var(--a2);}
.vhint{font-family:var(--mono);font-size:9px;color:var(--dim);line-height:1.6;margin-top:6px;opacity:.7;}

/* ── QUICK COPY ── */
#qc-backdrop{display:none;position:fixed;inset:0;z-index:399;}
.qc-popup{position:fixed;z-index:400;background:var(--surf2);border:1px solid var(--bdrb);
  border-radius:11px;width:200px;box-shadow:0 8px 36px rgba(0,0,0,.6),0 0 24px rgba(15,111,255,.15);
  animation:qcIn .15s cubic-bezier(.34,1.56,.64,1);overflow:hidden;display:none;}
@keyframes qcIn{from{transform:scale(.9);opacity:0}to{transform:scale(1);opacity:1}}
.qc-hd{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);padding:9px 12px 6px;border-bottom:1px solid var(--bdr);}
.qc-btn{display:block;width:100%;background:none;border:none;border-bottom:1px solid var(--bdr);
  padding:10px 12px;font-family:var(--mono);font-size:11px;letter-spacing:.5px;color:var(--txt);
  cursor:pointer;text-align:left;transition:all .1s;}
.qc-btn:last-child{border-bottom:none;}
.qc-btn:hover{background:rgba(15,111,255,.08);color:var(--a2);}

/* ── SLIDE PANEL ── */
.p-overlay{position:fixed;inset:0;z-index:50;pointer-events:none;}
.p-back{position:absolute;inset:0;background:rgba(0,0,0,0);transition:background .25s;pointer-events:none;}
.p-overlay.open .p-back{background:rgba(0,0,0,.55);backdrop-filter:blur(3px);pointer-events:all;}
.detail-panel{position:absolute;right:0;top:0;bottom:0;width:min(480px,calc(100vw - 44px));
  background:rgba(7,11,18,.97);border-left:1px solid var(--bdr);transform:translateX(100%);
  transition:transform .3s cubic-bezier(.34,1.1,.64,1);display:flex;flex-direction:column;
  overflow:hidden;backdrop-filter:blur(16px);pointer-events:all;}
.p-overlay.open .detail-panel{transform:translateX(0);}
.p-hdr{padding:15px 18px 11px;border-bottom:1px solid var(--bdr);flex-shrink:0;background:rgba(15,111,255,.03);}
.p-title-row{display:flex;align-items:flex-start;gap:9px;margin-bottom:8px;}
.p-dot{width:10px;height:10px;border-radius:50%;margin-top:4px;flex-shrink:0;}
.p-name{font-family:var(--sans);font-weight:700;font-size:19px;letter-spacing:1px;color:var(--bright);flex:1;line-height:1.2;}
.p-close{background:rgba(255,255,255,.05);border:1px solid var(--bdr);border-radius:7px;color:var(--dim);
  font-size:12px;padding:5px 11px;cursor:pointer;transition:all .12s;font-family:var(--mono);flex-shrink:0;}
.p-close:hover{background:rgba(255,48,96,.1);border-color:var(--danger);color:var(--danger);}
.p-badges{display:flex;gap:6px;flex-wrap:wrap;}
.p-cnt{font-family:var(--mono);font-size:11px;color:var(--a2);background:rgba(0,212,255,.08);border:1px solid rgba(0,212,255,.15);padding:2px 10px;border-radius:20px;}
.p-srv{font-family:var(--mono);font-size:11px;color:var(--a3);background:rgba(123,47,255,.1);border:1px solid rgba(123,47,255,.2);padding:2px 10px;border-radius:20px;}
.p-tools{display:flex;align-items:center;gap:7px;padding:8px 18px;border-bottom:1px solid var(--bdr);flex-shrink:0;background:rgba(0,0,0,.15);flex-wrap:wrap;}
.p-btn{background:none;border:1px solid var(--bdr);border-radius:6px;padding:6px 11px;
  font-family:var(--mono);font-size:10px;letter-spacing:1px;color:var(--dim);cursor:pointer;transition:all .12s;}
.p-btn:hover{border-color:var(--ac);color:var(--a2);}
.p-btn.red:hover{border-color:var(--danger);color:var(--danger);}
.p-btn.pin-on{border-color:var(--warn);color:var(--warn);}
.p-cols{display:flex;gap:3px;margin-left:auto;}
.p-cpill{width:22px;height:22px;background:none;border:1px solid var(--bdr);border-radius:5px;
  font-family:var(--mono);font-size:10px;color:var(--dim);cursor:pointer;transition:all .12s;
  display:flex;align-items:center;justify-content:center;}
.p-cpill.on{background:var(--ac);border-color:var(--ac);color:#fff;}
.p-edit{padding:12px 18px;border-bottom:1px solid var(--bdr);background:rgba(15,111,255,.03);display:none;}
.p-edit.open{display:block;animation:sd .15s ease;}
@keyframes sd{from{opacity:0;transform:translateY(-5px)}to{opacity:1;transform:translateY(0)}}
.flbl{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;margin-bottom:5px;margin-top:9px;}
.flbl:first-child{margin-top:0;}
.finput{width:100%;background:var(--bg);border:1px solid var(--bdr);border-radius:7px;padding:8px 11px;
  font-family:var(--sans);font-size:14px;color:var(--bright);outline:none;transition:border-color .15s;}
.finput:focus{border-color:var(--ac);box-shadow:0 0 0 2px rgba(15,111,255,.12);}
.edit-act{display:flex;gap:8px;justify-content:flex-end;margin-top:10px;}
.p-scroll{flex:1;overflow-y:auto;padding:12px;}
.p-scroll::-webkit-scrollbar{width:3px;}
.p-scroll::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.ck-grid{display:grid;gap:8px;grid-template-columns:repeat(var(--pc,1),1fr);}

/* ── COOKIE ITEMS (terminal line style) ── */
.ck-item{background:rgba(6,10,16,.7);border:1px solid rgba(26,48,80,.5);border-radius:7px;
  padding:0;overflow:hidden;position:relative;font-family:var(--mono);}
.ck-item.editing{border-color:var(--ac);box-shadow:0 0 0 1px rgba(15,111,255,.15);}
.ck-item+.ck-item{border-top-left-radius:0;border-top-right-radius:0;margin-top:-1px;}
.ck-line{display:flex;align-items:baseline;gap:0;padding:3px 10px;border-bottom:1px solid rgba(26,48,80,.3);min-height:26px;}
.ck-line:last-of-type{border-bottom:none;}
.ck-line-key{font-size:9px;color:var(--dim);letter-spacing:1px;min-width:38px;flex-shrink:0;padding-top:1px;}
.ck-line-val{font-size:11px;color:var(--txt);flex:1;min-width:0;word-break:break-all;line-height:1.5;}
.ck-line-val.cookie-val{color:var(--a2);font-size:10px;}
.ck-line-val.status-ok{color:var(--ok);}
.ck-line-val.status-ban{color:var(--danger);}
.ck-line-val.status-exp{color:var(--warn);}
.ck-line-val.status-face{color:#ff6b00;}
.ck-item-hdr{display:flex;align-items:center;gap:6px;padding:5px 10px;
  background:rgba(15,111,255,.04);border-bottom:1px solid rgba(26,48,80,.5);}
.ck-idx{font-family:var(--mono);font-size:9px;color:var(--ac);background:rgba(15,111,255,.1);
  padding:1px 7px;border-radius:3px;flex-shrink:0;}
.ck-status-tag{font-family:var(--mono);font-size:8px;padding:1px 6px;border-radius:3px;
  letter-spacing:.5px;flex-shrink:0;}
.ck-status-tag.ok{background:rgba(0,255,170,.1);color:var(--ok);border:1px solid rgba(0,255,170,.2);}
.ck-status-tag.ban{background:rgba(255,48,96,.1);color:var(--danger);border:1px solid rgba(255,48,96,.2);}
.ck-status-tag.exp{background:rgba(255,170,0,.1);color:var(--warn);border:1px solid rgba(255,170,0,.2);}
.ck-status-tag.face{background:rgba(255,107,0,.1);color:#ff6b00;border:1px solid rgba(255,107,0,.2);}
.ck-item-actions{display:flex;gap:4px;margin-left:auto;}
.ck-fmt-row{display:flex;gap:4px;padding:5px 10px 0;flex-wrap:wrap;}
.ck-fmt-btn{background:rgba(255,255,255,.04);border:1px solid var(--bdr);border-radius:4px;
  font-family:var(--mono);font-size:9px;color:var(--dim);cursor:pointer;padding:3px 8px;
  transition:all .12s;letter-spacing:.5px;}
.ck-fmt-btn:hover{border-color:var(--a2);color:var(--a2);background:rgba(0,212,255,.08);}
.ck-copy-btn{background:rgba(15,111,255,.1);border:1px solid rgba(15,111,255,.2);border-radius:4px;
  padding:3px 8px;font-family:var(--mono);font-size:8px;color:var(--a2);cursor:pointer;
  transition:all .12s;letter-spacing:.5px;}
.ck-copy-btn:hover{background:rgba(15,111,255,.2);border-color:var(--ac);}
.ck-edit-btn{background:rgba(255,255,255,.03);border:1px solid var(--bdr);border-radius:4px;
  padding:3px 8px;font-family:var(--mono);font-size:8px;color:var(--dim);cursor:pointer;
  transition:all .12s;}
.ck-edit-btn:hover{border-color:var(--a2);color:var(--a2);}
.ck-del-btn{background:rgba(255,48,96,.06);border:1px solid rgba(255,48,96,.15);border-radius:4px;
  padding:3px 8px;font-family:var(--mono);font-size:8px;color:var(--danger);cursor:pointer;
  transition:all .12s;}
.ck-del-btn:hover{background:rgba(255,48,96,.15);border-color:var(--danger);}
/* keep blur class for alts compatibility but unused in main */
.blur{flex:1;min-width:0;color:var(--txt);}
.blur.show{user-select:text;}
.ck-val-wrap{display:none;}
.ck-val{display:none;}
.rv-hint{display:none;}
.ck-field{display:none;}
.ck-actions{display:flex;gap:4px;padding:5px 10px;border-top:1px solid rgba(26,48,80,.3);align-items:center;}
/* Edit mode fields */
.ck-edit-form{display:none;margin-top:8px;border-top:1px solid var(--bdr);padding-top:8px;}
.ck-item.editing .ck-edit-form{display:block;}
.ck-edit-lbl{font-family:var(--mono);font-size:8px;color:var(--dim);letter-spacing:1.5px;text-transform:uppercase;margin-bottom:3px;margin-top:6px;}
.ck-edit-lbl:first-child{margin-top:0;}
.ck-edit-in{width:100%;background:rgba(0,0,0,.5);border:1px solid var(--bdr);border-radius:5px;
  padding:6px 8px;font-family:var(--mono);font-size:10px;color:var(--bright);outline:none;
  transition:border-color .15s;resize:none;}
.ck-edit-in:focus{border-color:var(--ac);}
.ck-edit-in.cookie-in{min-height:60px;word-break:break-all;}
.ck-edit-act{display:flex;gap:5px;justify-content:flex-end;margin-top:7px;}
.ck-save-btn{background:linear-gradient(135deg,var(--ac),var(--a3));border:none;border-radius:5px;
  padding:4px 11px;font-family:var(--mono);font-size:9px;color:#fff;cursor:pointer;}
.ck-cancel-btn{background:none;border:1px solid var(--bdr);border-radius:5px;
  padding:4px 11px;font-family:var(--mono);font-size:9px;color:var(--dim);cursor:pointer;}
.ck-cancel-btn:hover{border-color:var(--danger);color:var(--danger);}

.ck-changelog{margin-top:16px;padding-top:12px;border-top:1px solid var(--bdr);}
.ck-clog-title{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;margin-bottom:8px;}
.ck-clog-entry{display:flex;gap:8px;align-items:baseline;padding:4px 0;border-bottom:1px solid rgba(26,48,80,.4);}
.ck-clog-entry:last-child{border-bottom:none;}
.ck-clog-time{font-family:var(--mono);font-size:9px;color:var(--dim);white-space:nowrap;flex-shrink:0;}
.ck-clog-msg{font-family:var(--mono);font-size:10px;color:var(--txt);}
.ck-clog-msg span{color:var(--a2);}

/* ── MODALS ── */
.m-ov{display:none;position:fixed;inset:0;background:rgba(0,0,0,.65);backdrop-filter:blur(6px);z-index:200;align-items:center;justify-content:center;}
.m-ov.open{display:flex;}
.modal{background:var(--solid);border:1px solid var(--bdrb);border-radius:16px;padding:22px;
  width:min(90vw,400px);box-shadow:0 0 60px rgba(15,111,255,.2);animation:mi .2s ease;}
@keyframes mi{from{transform:scale(.94) translateY(8px);opacity:0}to{transform:scale(1) translateY(0);opacity:1}}
.modal h3{font-family:var(--sans);font-weight:700;font-size:18px;color:var(--bright);letter-spacing:1px;margin-bottom:5px;}
.modal p{font-size:12px;color:var(--dim);margin-bottom:14px;line-height:1.6;}
.modal p span{color:var(--a2);font-family:var(--mono);}
.m-act{display:flex;gap:8px;justify-content:flex-end;margin-top:4px;}
.bsm{font-family:var(--mono);font-size:10px;padding:7px 13px;border-radius:6px;cursor:pointer;transition:all .12s;letter-spacing:1px;}
.b-ghost{background:none;border:1px solid var(--bdr);color:var(--dim);}
.b-ghost:hover{border-color:var(--ac);color:var(--a2);}
.b-save{background:linear-gradient(135deg,var(--ac),var(--a3));border:none;color:#fff;box-shadow:0 0 12px rgba(15,111,255,.3);}
.b-danger{background:rgba(255,48,96,.15);border:1px solid rgba(255,48,96,.3);color:var(--danger);}
.b-danger:hover{background:rgba(255,48,96,.25);}
.import-preview{background:rgba(0,0,0,.3);border:1px solid var(--bdr);border-radius:7px;padding:10px 12px;margin-bottom:12px;max-height:120px;overflow-y:auto;}
.import-preview-row{font-family:var(--mono);font-size:10px;color:var(--dim);padding:2px 0;display:flex;gap:8px;}
.import-preview-row.dup{color:var(--warn);}
.import-preview-row.ok{color:var(--ok);}
.bulk-modal{width:min(90vw,310px);}
.bulk-opt{background:none;border:1px solid var(--bdr);border-radius:8px;padding:10px 12px;
  font-family:var(--mono);font-size:11px;letter-spacing:1px;color:var(--txt);cursor:pointer;
  transition:all .12s;text-align:left;width:100%;margin-bottom:5px;display:flex;align-items:center;gap:9px;}
.bulk-opt:last-of-type{margin-bottom:0;}
.bulk-opt:hover{background:rgba(15,111,255,.08);border-color:var(--ac);color:var(--a2);}
.bulk-tag{font-size:9px;color:var(--dim);background:rgba(255,255,255,.05);border:1px solid var(--bdr);padding:1px 6px;border-radius:3px;flex-shrink:0;}
/* Stats modal */
.stats-modal{width:min(92vw,440px);}
.stats-grid{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-bottom:14px;}
.stat-card{background:rgba(0,0,0,.3);border:1px solid var(--bdr);border-radius:9px;padding:12px;text-align:center;}
.stat-card .sv{font-family:var(--mono);font-size:22px;font-weight:700;color:var(--a2);line-height:1;}
.stat-card .sl{font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;margin-top:4px;text-transform:uppercase;}
.stat-fun{font-family:var(--mono);font-size:10px;color:var(--dim);line-height:1.8;background:rgba(0,0,0,.2);border-radius:7px;padding:10px 12px;border:1px solid var(--bdr);}
.stat-fun span{color:var(--a2);}
/* Changelog modal */
.changelog-modal{width:min(92vw,480px);max-height:80vh;display:flex;flex-direction:column;}
.changelog-scroll{overflow-y:auto;flex:1;padding-right:4px;}
.changelog-scroll::-webkit-scrollbar{width:3px;}
.changelog-scroll::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.cl-version{margin-bottom:20px;}
.cl-ver-head{display:flex;align-items:center;gap:10px;margin-bottom:10px;padding-bottom:6px;border-bottom:1px solid var(--bdr);}
.cl-ver-num{font-family:var(--mono);font-size:12px;color:var(--a2);font-weight:700;letter-spacing:1px;}
.cl-ver-date{font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;}
.cl-ver-latest{font-family:var(--mono);font-size:8px;color:var(--ok);background:rgba(0,255,170,.1);border:1px solid rgba(0,255,170,.2);border-radius:3px;padding:1px 6px;letter-spacing:1px;}
.cl-entry{display:flex;gap:8px;align-items:baseline;padding:4px 0;}
.cl-type{font-family:var(--mono);font-size:8px;padding:1px 5px;border-radius:3px;flex-shrink:0;letter-spacing:.5px;text-transform:uppercase;}
.cl-type.add{background:rgba(0,255,170,.1);color:var(--ok);border:1px solid rgba(0,255,170,.2);}
.cl-type.fix{background:rgba(15,111,255,.1);color:var(--a2);border:1px solid rgba(15,111,255,.2);}
.cl-type.remove{background:rgba(255,48,96,.1);color:var(--danger);border:1px solid rgba(255,48,96,.2);}
.cl-type.change{background:rgba(255,170,0,.1);color:var(--warn);border:1px solid rgba(255,170,0,.2);}
.cl-desc{font-family:var(--mono);font-size:11px;color:var(--txt);line-height:1.5;}

/* ── COOKIE ACTIVITY LOG ── */
.cklog-modal{width:min(94vw,540px);max-height:82vh;display:flex;flex-direction:column;}
.cklog-toolbar{display:flex;align-items:center;gap:8px;margin-bottom:12px;flex-wrap:wrap;}
.cklog-filter{background:none;border:1px solid var(--bdr);border-radius:6px;padding:4px 10px;
  font-family:var(--mono);font-size:9px;color:var(--dim);cursor:pointer;letter-spacing:.5px;transition:all .12s;}
.cklog-filter:hover{border-color:var(--ac);color:var(--a2);}
.cklog-filter.on{border-color:var(--a2);color:var(--a2);background:rgba(0,212,255,.08);}
.cklog-count{font-family:var(--mono);font-size:9px;color:var(--dim);margin-left:auto;}
.cklog-scroll{overflow-y:auto;flex:1;min-height:0;}
.cklog-scroll::-webkit-scrollbar{width:3px;}
.cklog-scroll::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.cklog-empty{text-align:center;padding:40px 0;font-family:var(--mono);font-size:11px;color:var(--dim);letter-spacing:1px;}
.cklog-entry{display:grid;grid-template-columns:52px 58px 1fr;gap:6px;align-items:baseline;
  padding:6px 0;border-bottom:1px solid rgba(255,255,255,.04);font-family:var(--mono);font-size:10px;}
.cklog-entry:last-child{border-bottom:none;}
.cklog-ts{color:var(--dim);font-size:9px;white-space:nowrap;}
.cklog-type{font-size:8px;padding:1px 5px;border-radius:3px;text-align:center;letter-spacing:.5px;text-transform:uppercase;white-space:nowrap;}
.cklog-type.added{background:rgba(0,255,170,.1);color:var(--ok);border:1px solid rgba(0,255,170,.2);}
.cklog-type.edited{background:rgba(0,212,255,.1);color:var(--a2);border:1px solid rgba(0,212,255,.2);}
.cklog-type.deleted{background:rgba(255,48,96,.1);color:var(--danger);border:1px solid rgba(255,48,96,.2);}
.cklog-type.banned{background:rgba(255,48,96,.08);color:var(--danger);border:1px solid rgba(255,48,96,.15);}
.cklog-type.active{background:rgba(0,255,170,.08);color:var(--ok);border:1px solid rgba(0,255,170,.15);}
.cklog-type.expired{background:rgba(255,170,0,.1);color:var(--warn);border:1px solid rgba(255,170,0,.2);}
.cklog-type.facelock{background:rgba(255,107,0,.1);color:#ff6b00;border:1px solid rgba(255,107,0,.2);}
.cklog-type.copied{background:rgba(123,47,255,.1);color:var(--a3);border:1px solid rgba(123,47,255,.2);}
.cklog-msg{color:var(--txt);font-size:10px;line-height:1.4;word-break:break-word;}
/* Update modal */
.update-modal{width:min(92vw,460px);max-height:80vh;display:flex;flex-direction:column;}
.update-scroll{overflow-y:auto;flex:1;padding-right:4px;}
.update-scroll::-webkit-scrollbar{width:3px;}
.update-scroll::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.upd-section{margin-bottom:14px;}
.upd-section-title{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;margin-bottom:8px;}
.upd-row{display:flex;align-items:center;gap:8px;padding:7px 10px;background:rgba(0,0,0,.2);
  border:1px solid var(--bdr);border-radius:7px;margin-bottom:5px;}
.upd-row:last-child{margin-bottom:0;}
.upd-name{font-family:var(--mono);font-size:11px;color:var(--bright);flex:1;}
.upd-meta{font-family:var(--mono);font-size:9px;color:var(--dim);}
.upd-badge{font-family:var(--mono);font-size:8px;padding:2px 7px;border-radius:4px;flex-shrink:0;}
.upd-badge.new{background:rgba(0,255,170,.1);color:var(--ok);border:1px solid rgba(0,255,170,.2);}
.upd-badge.changed{background:rgba(255,170,0,.1);color:var(--warn);border:1px solid rgba(255,170,0,.2);}
.upd-badge.same{background:rgba(255,255,255,.04);color:var(--dim);border:1px solid var(--bdr);}
.upd-toggle{background:none;border:1px solid var(--bdr);border-radius:5px;padding:3px 8px;
  font-family:var(--mono);font-size:8px;color:var(--dim);cursor:pointer;transition:all .12s;flex-shrink:0;}
.upd-toggle.on{background:rgba(0,212,255,.1);border-color:var(--a2);color:var(--a2);}
.upd-toggle:hover{border-color:var(--a2);color:var(--a2);}

/* ── TOAST ── */
#toast{position:fixed;bottom:18px;right:18px;background:var(--solid);border:1px solid var(--bdrb);
  border-radius:9px;padding:10px 14px;font-family:var(--mono);font-size:11px;color:var(--bright);
  box-shadow:0 0 26px rgba(15,111,255,.2);transform:translateY(60px);opacity:0;
  transition:all .25s cubic-bezier(.34,1.5,.64,1);z-index:600;display:flex;align-items:center;gap:10px;}
#toast.show{transform:translateY(0);opacity:1;}
#toast.ok{border-color:var(--ok);}
#toast.err{border-color:var(--danger);}
#toast.warn{border-color:var(--warn);}
.toast-undo{background:rgba(255,255,255,.08);border:1px solid var(--bdr);border-radius:5px;
  padding:3px 9px;font-family:var(--mono);font-size:10px;color:var(--a2);cursor:pointer;transition:all .1s;flex-shrink:0;}
.toast-undo:hover{background:rgba(15,111,255,.2);}

/* ── POWER DOWN ── */
#powerdown{position:fixed;inset:0;z-index:950;background:var(--bg);pointer-events:none;opacity:0;}
#powerdown.active{animation:pwrdown .6s ease forwards;}
@keyframes pwrdown{
  0%{opacity:0;transform:none}30%{opacity:1;transform:scaleY(1)}70%{opacity:1;transform:scaleY(.04)}
  85%{opacity:1;transform:scaleY(.01) scaleX(1)}95%{opacity:1;transform:scaleY(.005) scaleX(.3)}
  100%{opacity:1;transform:scaleY(0) scaleX(0)}}

#import-f,#import-tf,#update-f{display:none;}
::-webkit-scrollbar{width:4px;}
::-webkit-scrollbar-track{background:transparent;}
::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:3px;}
@media(max-width:600px){
  :root{--sw:0px;}
  .sidebar{display:none;}
  .hdr-stats{display:none;}
  .hdr-search{flex:1;max-width:none;min-width:0;}
  .hdr-search input{min-width:0;width:100%;}
  .hdr-right{gap:4px;flex-shrink:0;max-width:none;}
  .hdr-meta{display:none;}
  .list-view-btn,.sort-btn,.card-size-btn,.col-pills{display:none!important;}
  .data-switch{display:flex!important;flex-shrink:0;}
  .hdr-title{display:none;}
}

/* ── BAN TAG ── */
.gcard-banned-tag{position:absolute;top:7px;left:8px;z-index:5;pointer-events:none;
  background:rgba(255,48,96,.82);border:1px solid rgba(255,48,96,.6);border-radius:4px;
  font-family:var(--mono);font-size:7px;color:#fff;padding:1px 6px;letter-spacing:.5px;
  text-transform:uppercase;}
.gcard.banned{border-color:rgba(255,48,96,.45)!important;}
.gcard.banned .gcard-bar{background:var(--danger)!important;}
.gcard.banned .gcard-dot{background:var(--danger)!important;color:var(--danger)!important;}
.p-ban-btn{border-color:rgba(255,48,96,.3)!important;color:rgba(255,100,120,.7)!important;}
.p-ban-btn:hover{border-color:var(--danger)!important;color:var(--danger)!important;}
.p-ban-btn.ban-on{background:rgba(255,48,96,.15)!important;border-color:var(--danger)!important;color:var(--danger)!important;}
.p-banned-badge{font-family:var(--mono);font-size:10px;color:var(--danger);background:rgba(255,48,96,.1);
  border:1px solid rgba(255,48,96,.25);padding:2px 10px;border-radius:20px;}

/* ── BULK SELECT ── */
.gcard-chk{position:absolute;top:8px;right:8px;z-index:10;width:18px;height:18px;
  border-radius:5px;border:2px solid rgba(255,255,255,.25);background:rgba(0,0,0,.5);
  cursor:pointer;display:none;align-items:center;justify-content:center;
  transition:all .12s;}
.gcard:hover .gcard-chk,.gcard.bulk-selected .gcard-chk{display:flex;}
.gcard.bulk-selected .gcard-chk{border-color:var(--a2);background:var(--a2);}
.gcard.bulk-selected .gcard-chk::after{content:'✓';font-size:11px;color:#000;font-weight:900;line-height:1;}
.gcard.bulk-selected{border-color:var(--a2)!important;box-shadow:0 0 14px rgba(0,212,255,.3)!important;}
/* List view: tick always visible, right side */
body.list-view .gcard-chk{
  display:flex;position:static;transform:none;
  width:28px;height:28px;flex-shrink:0;border-radius:7px;
  margin-left:auto;margin-right:8px;order:99;
  border:2px solid rgba(255,255,255,.15);background:rgba(255,255,255,.04);
}
body.list-view .gcard.bulk-selected .gcard-chk{border-color:var(--a2);background:var(--a2);}
body.list-view .gcard.bulk-selected .gcard-chk::after{content:'✓';font-size:13px;color:#000;font-weight:900;line-height:1;}
.bulk-bar{position:fixed;bottom:0;left:0;right:0;z-index:400;
  background:rgba(7,11,18,.97);border-top:1px solid var(--bdrb);
  padding:10px 20px;display:flex;align-items:center;gap:10px;
  transform:translateY(100%);transition:transform .25s cubic-bezier(.34,1.3,.64,1);}
.bulk-bar.open{transform:translateY(0);}
.bulk-bar-count{font-family:var(--mono);font-size:11px;color:var(--a2);margin-right:auto;letter-spacing:1px;}
.bulk-bar-btn{background:rgba(255,255,255,.05);border:1px solid var(--bdr);border-radius:8px;
  padding:8px 14px;font-family:var(--mono);font-size:10px;color:var(--dim);cursor:pointer;
  letter-spacing:.5px;transition:all .12s;white-space:nowrap;display:flex;align-items:center;gap:6px;}
.bulk-bar-btn:hover{border-color:var(--ac);color:var(--a2);}
.bulk-bar-btn.danger:hover{border-color:var(--danger);color:var(--danger);}
.bulk-bar-cancel{background:none;border:none;color:var(--dim);cursor:pointer;font-family:var(--mono);
  font-size:10px;padding:8px 6px;transition:color .12s;}
.bulk-bar-cancel:hover{color:var(--bright);}

/* ── ALTERNATIVES ── */
.alt-section{margin-top:14px;border-top:1px solid var(--bdr);padding-top:10px;}
.alt-sec-head{display:flex;align-items:center;gap:8px;cursor:pointer;padding:4px 0;user-select:none;margin-bottom:6px;}
.alt-sec-title{font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--a3);text-transform:uppercase;flex:1;}
.alt-sec-count{font-family:var(--mono);font-size:9px;color:var(--dim);}
.alt-sec-chev{color:var(--dim);font-size:10px;transition:transform .2s;}
.alt-sec-body{display:none;}
.alt-sec-body.open{display:block;}
.alt-sec-head.open .alt-sec-chev{transform:rotate(180deg);}
.alt-entry{background:rgba(123,47,255,.05);border:1px solid rgba(123,47,255,.18);
  border-radius:9px;margin-bottom:8px;overflow:hidden;}
.alt-entry-head{display:flex;align-items:center;gap:8px;padding:7px 11px;
  border-bottom:1px solid rgba(123,47,255,.12);background:rgba(123,47,255,.06);}
.alt-entry-label{font-family:var(--sans);font-weight:700;font-size:12px;color:var(--a3);flex:1;letter-spacing:.5px;}
.alt-entry-count{font-family:var(--mono);font-size:9px;color:var(--dim);}
.alt-entry-del{background:none;border:none;color:var(--dim);cursor:pointer;font-size:11px;
  padding:2px 5px;transition:color .12s;border-radius:4px;}
.alt-entry-del:hover{color:var(--danger);background:rgba(255,48,96,.08);}
.alt-entry-cookies{padding:8px;}
.ck-item.alt-ck{background:rgba(123,47,255,.04);border-color:rgba(123,47,255,.15);}
.ck-item.alt-ck .ck-idx{background:rgba(123,47,255,.12);color:var(--a3);}
.btn-add-alt{width:100%;background:rgba(123,47,255,.06);border:1px dashed rgba(123,47,255,.3);
  border-radius:8px;padding:8px 12px;font-family:var(--mono);font-size:9px;
  color:var(--a3);cursor:pointer;letter-spacing:1px;transition:all .15s;margin-top:6px;display:block;}
.btn-add-alt:hover{background:rgba(123,47,255,.15);border-color:var(--a3);border-style:solid;}
.add-alt-form{background:rgba(123,47,255,.04);border:1px solid rgba(123,47,255,.2);
  border-radius:9px;padding:12px;margin-top:8px;display:none;animation:sd .15s ease;}
.add-alt-form.open{display:block;}
.gcard-alt-badge{font-family:var(--mono);font-size:7px;color:var(--a3);
  background:rgba(123,47,255,.12);border:1px solid rgba(123,47,255,.2);
  border-radius:3px;padding:1px 5px;display:inline-block;margin-top:2px;}
/* ── PIN LOCK SCREEN ── */
#pin-screen{position:fixed;inset:0;z-index:1000;background:var(--bg);display:flex;align-items:center;justify-content:center;flex-direction:column;transition:opacity .3s;}
#pin-screen.hidden{opacity:0;pointer-events:none;}
.pin-box{display:flex;flex-direction:column;align-items:center;gap:18px;animation:pinIn .35s cubic-bezier(.34,1.3,.64,1);}
@keyframes pinIn{from{opacity:0;transform:scale(.9) translateY(12px)}to{opacity:1;transform:none}}
.pin-logo{font-size:36px;filter:drop-shadow(0 0 18px rgba(15,111,255,.5));}
.pin-vault-name{font-family:var(--sans);font-weight:700;font-size:20px;letter-spacing:3px;color:var(--bright);text-transform:uppercase;}
.pin-vault-name span{color:var(--a2);}
.pin-sub{font-family:var(--mono);font-size:10px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;}
.pin-dots{display:flex;gap:12px;margin:4px 0;}
.pin-dot{width:14px;height:14px;border-radius:50%;border:2px solid var(--bdr);background:transparent;transition:all .15s;}
.pin-dot.filled{background:var(--a2);border-color:var(--a2);box-shadow:0 0 10px var(--a2);}
.pin-pad{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;width:220px;}
.pin-key{background:rgba(255,255,255,.04);border:1px solid var(--bdr);border-radius:10px;font-family:var(--mono);font-size:18px;color:var(--bright);padding:14px 0;cursor:pointer;text-align:center;transition:all .12s;user-select:none;}
.pin-key:hover{background:rgba(15,111,255,.12);border-color:var(--bdrb);color:var(--a2);}
.pin-key:active{transform:scale(.94);}
.pin-key.clear{font-size:12px;letter-spacing:1px;color:var(--dim);}
.pin-key.del{font-size:16px;}
.pin-err{font-family:var(--mono);font-size:11px;color:var(--danger);letter-spacing:1px;min-height:18px;text-align:center;}
.pin-lock-msg{font-family:var(--mono);font-size:10px;color:var(--warn);letter-spacing:1px;text-align:center;}
@keyframes glitch{
  0%{transform:none;filter:none;opacity:1}5%{transform:translateX(-4px) skewX(-5deg);filter:hue-rotate(90deg);opacity:.8}
  10%{transform:translateX(4px) skewX(5deg);filter:hue-rotate(180deg) brightness(1.5);opacity:.6}
  15%{transform:translateX(-6px);filter:hue-rotate(270deg);opacity:.9}
  20%{transform:translateX(2px) skewX(-3deg);filter:brightness(2) saturate(3);opacity:.7}
  25%{transform:none;filter:none;opacity:1}60%{transform:none;filter:none;}
  62%{transform:translateX(-3px);filter:hue-rotate(45deg);}64%{transform:none;filter:none;}
  100%{transform:none;filter:none;opacity:1}}
.glitching .pin-box{animation:glitch .5s ease forwards;}
@keyframes pinShake{
  0%,100%{transform:translateX(0)}15%{transform:translateX(-8px)}30%{transform:translateX(8px)}
  45%{transform:translateX(-6px)}60%{transform:translateX(6px)}75%{transform:translateX(-3px)}90%{transform:translateX(3px)}}
.pin-shaking .pin-box{animation:pinShake .5s ease;}
.pin-decoy-hint{font-family:var(--mono);font-size:8px;color:rgba(74,106,138,.4);letter-spacing:1px;cursor:pointer;margin-top:-8px;}
.pin-decoy-hint:hover{color:var(--dim);}

/* ── GITHUB SYNC DOT ── */
.sync-dot{width:8px;height:8px;border-radius:50%;flex-shrink:0;cursor:pointer;transition:all .3s;}
.sync-dot[data-state="off"]{background:var(--dim);opacity:.35;}
.sync-dot[data-state="syncing"]{background:var(--ac);box-shadow:0 0 8px var(--ac);animation:syncPulse 1s ease infinite;}
.sync-dot[data-state="ok"]{background:var(--ok);box-shadow:0 0 6px var(--ok);}
.sync-dot[data-state="err"]{background:var(--danger);box-shadow:0 0 6px var(--danger);}
.sync-dot[data-state="queue"]{background:var(--warn);box-shadow:0 0 6px var(--warn);animation:syncPulse 1.5s ease infinite;}
@keyframes syncPulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.4;transform:scale(.7)}}

/* ── FILTER BAR ── */
.filter-bar{display:flex;align-items:stretch;gap:0;padding:0 0 12px 0;border-bottom:1px solid var(--bdr);margin-bottom:12px;}
.filter-pill{background:none;border:none;border-bottom:2px solid transparent;border-radius:0;
  font-family:var(--mono);font-size:9px;letter-spacing:1px;color:var(--dim);padding:6px 12px;
  cursor:pointer;transition:color .12s,border-color .12s;white-space:nowrap;
  display:flex;align-items:center;gap:5px;}
.filter-pill svg{opacity:.45;transition:opacity .12s;}
.filter-pill:hover{color:var(--bright);}
.filter-pill:hover svg{opacity:.8;}
.filter-pill.on{color:var(--a2);border-bottom-color:var(--a2);}
.filter-pill.on svg{opacity:1;}
.filter-pill.on.f-banned{color:var(--danger);border-bottom-color:var(--danger);}
.filter-pill.on.f-alts{color:var(--a3);border-bottom-color:var(--a3);}
.health-badge{margin-left:auto;display:flex;align-items:center;gap:6px;background:rgba(0,0,0,.3);border:1px solid var(--bdr);border-radius:20px;padding:3px 10px;cursor:pointer;transition:all .12s;}
.health-badge:hover{border-color:var(--bdrb);}
.health-score{font-family:var(--mono);font-size:11px;font-weight:700;color:var(--bright);}
.health-lbl{font-family:var(--mono);font-size:8px;color:var(--dim);letter-spacing:1px;}
.health-grade{font-family:var(--mono);font-size:9px;padding:1px 6px;border-radius:10px;}
.health-grade.A{background:rgba(0,255,170,.12);color:var(--ok);border:1px solid rgba(0,255,170,.25);}
.health-grade.B{background:rgba(0,212,255,.12);color:var(--a2);border:1px solid rgba(0,212,255,.25);}
.health-grade.C{background:rgba(255,170,0,.12);color:var(--warn);border:1px solid rgba(255,170,0,.25);}
.health-grade.D{background:rgba(255,107,0,.12);color:#ff6b00;border:1px solid rgba(255,107,0,.25);}
.health-grade.F{background:rgba(255,48,96,.12);color:var(--danger);border:1px solid rgba(255,48,96,.25);}

/* ── COOKIE EXTRACTOR ── */
.cx-panel{background:rgba(4,8,14,.95);border:1px solid rgba(0,212,255,.2);border-radius:10px;
  margin-bottom:16px;overflow:hidden;box-shadow:0 0 20px rgba(0,212,255,.04);}
.cx-hdr{display:flex;align-items:center;gap:10px;padding:8px 14px;border-bottom:1px solid rgba(0,212,255,.1);
  cursor:pointer;user-select:none;background:rgba(0,212,255,.04);}
.cx-title{font-family:var(--mono);font-size:10px;letter-spacing:2px;color:var(--a2);text-transform:uppercase;flex:1;}
.cx-title::before{content:'⟁ ';opacity:.6;}
.cx-match-count{font-family:var(--mono);font-size:9px;color:var(--dim);margin-right:4px;}
.cx-chev{font-family:var(--mono);font-size:10px;color:var(--dim);transition:transform .2s;}
.cx-body{padding:12px 14px;display:none;flex-direction:column;gap:8px;}
.cx-ta{width:100%;background:rgba(0,0,0,.4);border:1px solid rgba(0,212,255,.2);border-radius:7px;
  padding:10px 12px;font-family:var(--mono);font-size:11px;color:var(--txt);outline:none;
  resize:vertical;min-height:80px;line-height:1.6;transition:border-color .15s;}
.cx-ta:focus{border-color:var(--a2);}
.cx-ta::placeholder{color:var(--dim);opacity:.4;}
.cx-info{font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:.5px;min-height:14px;}
.cx-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap;}
.cx-results{display:flex;flex-direction:column;gap:4px;max-height:400px;overflow-y:auto;}
.cx-results::-webkit-scrollbar{width:3px;}
.cx-results::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}
.cx-result-row{display:flex;align-items:center;gap:8px;padding:7px 10px;border-radius:7px;
  border:1px solid var(--bdr);background:rgba(255,255,255,.02);transition:background .12s;}
.cx-result-row.matched{border-color:rgba(0,212,255,.2);background:rgba(0,212,255,.04);}
.cx-result-row.unmatched{opacity:.4;}
.cx-result-user{font-family:var(--mono);font-size:11px;color:var(--bright);flex-shrink:0;min-width:140px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.cx-result-meta{font-family:var(--mono);font-size:9px;color:var(--dim);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.cx-result-group{font-family:var(--mono);font-size:9px;color:var(--a3);background:rgba(123,47,255,.1);
  border:1px solid rgba(123,47,255,.2);border-radius:3px;padding:1px 6px;white-space:nowrap;flex-shrink:0;}
.cx-result-copy{background:none;border:1px solid var(--bdr);border-radius:5px;padding:3px 8px;
  font-family:var(--mono);font-size:8px;color:var(--dim);cursor:pointer;transition:all .12s;flex-shrink:0;}
.cx-result-copy:hover{border-color:var(--a2);color:var(--a2);}
.cx-no-match{font-family:var(--mono);font-size:10px;color:var(--dim);text-align:center;padding:16px 0;letter-spacing:1px;}
/* ── SWITCH DATA ── */
.data-switch{display:flex;align-items:center;gap:6px;background:rgba(255,255,255,.03);
  border:1px solid var(--bdr);border-radius:8px;padding:5px 10px;cursor:pointer;
  transition:all .12s;position:relative;}
.data-switch:hover{border-color:var(--a3);background:rgba(123,47,255,.08);}
.data-switch-lbl{font-family:var(--mono);font-size:10px;color:var(--dim);letter-spacing:.5px;
  max-width:80px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.data-switch-lbl.active{color:var(--a3);}
.data-switch-chev{color:var(--dim);font-size:10px;}
.ds-dropdown{position:fixed;top:auto;right:8px;background:rgba(7,11,18,.97);
  border:1px solid var(--bdrb);border-radius:12px;padding:6px;min-width:240px;max-width:calc(100vw - 16px);
  box-shadow:0 8px 32px rgba(0,0,0,.6);display:none;z-index:500;animation:qcIn .15s ease;}
.ds-dropdown.open{display:block;}
.ds-item{display:flex;align-items:center;gap:8px;padding:9px 12px;border-radius:7px;
  cursor:pointer;transition:all .12s;font-family:var(--sans);font-size:13px;font-weight:600;color:var(--txt);}
.ds-item:hover{background:rgba(123,47,255,.1);color:var(--bright);}
.ds-item.active{background:rgba(123,47,255,.12);color:var(--a3);}
.ds-item-dot{width:7px;height:7px;border-radius:50%;background:var(--a3);flex-shrink:0;}
.ds-item.active .ds-item-dot{background:var(--a3);box-shadow:0 0 6px var(--a3);}
.ds-item-name{flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.ds-item-actions{display:flex;gap:2px;flex-shrink:0;opacity:.45;transition:opacity .12s;}
.ds-item:hover .ds-item-actions{opacity:1;}
.ds-action-btn{background:none;border:1px solid var(--bdr);color:var(--dim);cursor:pointer;padding:4px 8px;
  border-radius:5px;font-size:11px;transition:all .12s;line-height:1;display:flex;align-items:center;}
.ds-action-btn:hover,.ds-action-btn:active{background:rgba(255,255,255,.1);}
.ds-action-btn.rename{color:var(--a2);border-color:rgba(0,212,255,.3);}
.ds-action-btn.del{color:var(--danger);border-color:rgba(255,48,96,.3);}
.ds-rename-input{flex:1;background:rgba(255,255,255,.06);border:1px solid var(--a2);border-radius:5px;
  padding:2px 7px;font-family:var(--sans);font-size:12px;font-weight:600;color:var(--bright);outline:none;min-width:0;}
.ds-sep{height:1px;background:var(--bdr);margin:4px 0;}
.ds-new-btn{display:flex;align-items:center;gap:8px;padding:9px 12px;border-radius:7px;
  cursor:pointer;transition:all .12s;font-family:var(--sans);font-size:12px;color:var(--dim);
  background:none;border:none;width:100%;}
.ds-new-btn:hover{color:var(--a3);background:rgba(123,47,255,.06);}

/* ── GROUP METADATA (Account ID + Private Server) ── */
.p-meta-section{padding:10px 18px;border-bottom:1px solid var(--bdr);background:rgba(0,0,0,.1);}
.p-meta-row{display:flex;align-items:center;gap:8px;margin-bottom:6px;}
.p-meta-row:last-child{margin-bottom:0;}
.p-meta-lbl{font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;
  min-width:80px;flex-shrink:0;}
.p-meta-val{font-family:var(--mono);font-size:10px;color:var(--txt);flex:1;
  min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
.p-meta-val.empty{color:var(--dim);font-style:italic;}
.p-meta-edit-in{flex:1;background:var(--bg);border:1px solid var(--bdr);border-radius:5px;
  padding:4px 8px;font-family:var(--mono);font-size:10px;color:var(--bright);outline:none;
  transition:border-color .15s;}
.p-meta-edit-in:focus{border-color:var(--ac);}
.p-meta-btn{background:rgba(255,255,255,.04);border:1px solid var(--bdr);border-radius:4px;
  padding:3px 8px;font-family:var(--mono);font-size:8px;color:var(--dim);cursor:pointer;
  transition:all .12s;white-space:nowrap;flex-shrink:0;}
.p-meta-btn:hover{border-color:var(--a2);color:var(--a2);}
.p-meta-btn.copy{border-color:rgba(0,212,255,.2);color:var(--a2);}
.p-meta-btn.copy:hover{background:rgba(0,212,255,.1);}
.p-notes-wrap{padding:10px 12px;border-bottom:1px solid var(--bdr);background:rgba(0,0,0,.08);}
.p-notes-hd{display:flex;align-items:center;justify-content:space-between;margin-bottom:4px;}
#p-notes-actions{display:flex;}

/* ── IMPORT REVIEW MODAL ── */
.import-modal{width:min(92vw,460px);max-height:80vh;display:flex;flex-direction:column;}
.import-scroll{overflow-y:auto;flex:1;}
.import-scroll::-webkit-scrollbar{width:3px;}
.import-scroll::-webkit-scrollbar-thumb{background:var(--bdr);border-radius:2px;}


/* ── SORT/DISTRIBUTE MODAL ── */
.sort-modal{width:min(92vw,460px);}
.sort-preview{margin-top:12px;max-height:160px;overflow-y:auto;background:rgba(0,0,0,.3);
  border:1px solid var(--bdr);border-radius:7px;padding:8px 12px;display:none;}
.sort-preview.show{display:block;}
.sort-preview-row{font-family:var(--mono);font-size:10px;color:var(--dim);padding:2px 0;
  border-bottom:1px solid rgba(26,48,80,.3);}
.sort-preview-row:last-child{border-bottom:none;}
.sort-preview-row .srv{color:var(--a3);}
.sort-preview-row .grp{color:var(--a2);}
.sort-preview-row .cnt{color:var(--ok);}

</style>
</head>
<body data-csize="md">
<div id="powerdown"></div>
<div id="pin-screen">
  <div class="pin-box">
    <div class="pin-logo">🔐</div>
    <div class="pin-vault-name" id="pin-vault-name">Cookie <span>Vault</span></div>
    <div class="pin-sub">Enter PIN to unlock</div>
    <div class="pin-dots" id="pin-dots">
      <div class="pin-dot"></div><div class="pin-dot"></div><div class="pin-dot"></div>
      <div class="pin-dot"></div><div class="pin-dot"></div><div class="pin-dot"></div>
    </div>
    <div class="pin-pad" id="pin-pad">
      <button class="pin-key" data-v="1">1</button><button class="pin-key" data-v="2">2</button><button class="pin-key" data-v="3">3</button>
      <button class="pin-key" data-v="4">4</button><button class="pin-key" data-v="5">5</button><button class="pin-key" data-v="6">6</button>
      <button class="pin-key" data-v="7">7</button><button class="pin-key" data-v="8">8</button><button class="pin-key" data-v="9">9</button>
      <button class="pin-key clear" data-v="clear">CLR</button>
      <button class="pin-key" data-v="0">0</button>
      <button class="pin-key del" data-v="del">⌫</button>
    </div>
    <div class="pin-err" id="pin-err"></div>
    <div class="pin-lock-msg" id="pin-lock-msg"></div>
    <div class="pin-decoy-hint" id="pin-decoy-hint" style="display:none" title="Configure decoy PIN in Vault Settings">configure decoy →</div>
  </div>
</div>

<!-- VAULT SETTINGS MODAL (GitHub + Workers + PIN Config) -->
<div class="m-ov" id="vault-settings-modal">
  <div class="modal vault-settings-modal">
    <h3>Vault Settings</h3>
    <div class="vault-settings-scroll">
      <div class="vsec">
        <div class="vsec-title">🔐 PIN Configuration</div>
        <div class="vrow"><label>Decoy PIN</label><input type="password" id="vs-decoy-pin" maxlength="8" placeholder="leave blank to disable" autocomplete="off"></div>
        <div class="vhint">Decoy PIN shows an empty vault to anyone who enters it. Real PIN is always 180801.</div>
      </div>
      <div class="vsec">
        <div class="vsec-title">☁ GitHub Gist Sync</div>
        <div class="vtoggle"><input type="checkbox" id="vs-gh-enabled"><span>Enable auto-sync to GitHub Gist</span></div>
        <div class="vrow"><label>PAT Token</label><input type="password" id="vs-gh-pat" placeholder="ghp_xxxxxxxxxxxx" autocomplete="off"></div>
        <div class="vrow"><label>Gist ID</label><input type="text" id="vs-gh-gist" placeholder="abc123def456..." autocomplete="off"></div>
        <div class="vhint">Create a secret Gist at gist.github.com, then generate a PAT at github.com/settings/tokens with the "gist" scope. Vault auto-syncs 3s after any change.</div>
        <button class="bt-ctrl-btn" id="vs-gh-test" style="margin-top:4px">test connection</button>
      </div>
    </div>
    <div class="m-act" style="margin-top:14px">
      <button class="bsm b-ghost" id="vs-cancel">cancel</button>
      <button class="bsm b-save" id="vs-save">save settings</button>
    </div>
  </div>
</div>


<div id="app">
  <header class="hdr">
    <div class="hdr-icon" title="Vault Stats" id="stats-btn">
      <svg width="20" height="20" viewBox="0 0 40 40" fill="none">
        <circle cx="20" cy="20" r="8" fill="#7b2fff"/>
        <ellipse cx="20" cy="20" rx="17" ry="5" fill="none" stroke="#00d4ff" stroke-width="2" transform="rotate(-25 20 20)"/>
        <circle cx="20" cy="20" r="3.5" fill="#9b4fff"/>
      </svg>
    </div>
    <div class="hdr-title" id="vault-title"></div>
    <div class="hdr-stats">
      <div class="stat-chip"><div class="stat-v" id="sv-g">0</div><div class="stat-l">Groups</div></div>
      <div class="stat-chip"><div class="stat-v" id="sv-c">0</div><div class="stat-l">Cookies</div></div>
      <div class="stat-chip"><div class="stat-v" id="sv-s">0</div><div class="stat-l">Servers</div></div>
    </div>
    <div class="hdr-search">
      <svg class="srch-ico" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
      <input type="text" id="search-in" placeholder="Search groups or usernames...">
      <button class="srch-clear" id="srch-clear" title="Clear search">✕</button>
    </div>
    <div class="hdr-right">
      <div class="hdr-meta">
        <button class="hdr-meta-btn" id="hdr-stats-btn" title="Vault Stats">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="18" y1="20" x2="18" y2="10"/><line x1="12" y1="20" x2="12" y2="4"/><line x1="6" y1="20" x2="6" y2="14"/>
          </svg>Stats
        </button>
        <button class="hdr-meta-btn" id="hdr-cl-btn" title="Changelog">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
            <polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>
          </svg>Log
        </button>
        <button class="hdr-meta-btn" id="hdr-cklog-btn" title="Cookie Activity Log">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
          </svg>Activity
        </button>
        <button class="hdr-meta-btn" id="hdr-alts-btn" title="All Alternative Cookies">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <line x1="6" y1="3" x2="6" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/>
          </svg>Alts
        </button>
      </div>
      <button class="list-view-btn" id="list-view-btn" title="Toggle list view">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>List
      </button>
      <button class="sort-btn" id="sort-btn">A→Z</button>
      <button class="card-size-btn" id="size-btn">M</button>
      <div class="col-pills">
        <button class="col-pill" data-c="1">1</button>
        <button class="col-pill on" data-c="2">2</button>
        <button class="col-pill" data-c="3">3</button>
        <button class="col-pill" data-c="4">4</button>
      </div>
      <button class="btn-add" id="hdr-add">+ Add</button>
      <button class="hdr-meta-btn" id="hdr-sync-btn" title="Sync Vault">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.75"/>
        </svg>Sync
      </button>
      <button class="hdr-meta-btn" id="hdr-refresh-btn" title="Refresh vault">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-.49-4.5"/>
        </svg>Refresh
      </button>
      <div class="sync-dot" id="sync-dot" data-state="off" title="GitHub sync status"></div>
      <div class="data-switch" id="data-switch-btn">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="var(--a3)" stroke-width="2">
          <ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/>
          <path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/>
        </svg>
        <span class="data-switch-lbl active" id="data-switch-lbl">Default</span>
        <span class="data-switch-chev">▾</span>
        <div class="ds-dropdown" id="ds-dropdown"></div>
      </div>
    </div>
  </header>

  <div class="app-body">
    <aside class="sidebar">
      <div class="sb-hd"><div class="sb-lbl">Servers</div></div>
      <nav class="sb-nav" id="sb-nav">
        <div class="sb-all on" data-t="all">
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
            <rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/>
          </svg>All groups
        </div>
        <div class="sb-div"></div>
      </nav>

      <!-- COMMAND DOCK -->
      <div class="sb-dock">
        <div class="sb-dock-label">⌘ Commands</div>
        <div class="sb-dock-grid">
          <div class="dock-cmd" id="sb-exp" style="--cc:#00ffaa;--cr:0,255,170" title="Export vault">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#00ffaa" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
            <div class="dock-cmd-txt">Export</div>
          </div>
          <div class="dock-cmd" id="sb-clip" style="--cc:#ffaa00;--cr:255,170,0" title="Copy all cookies u:p:c">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#ffaa00" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
            <div class="dock-cmd-txt">Copy</div>
          </div>
          <div class="dock-cmd" id="sb-imp" style="--cc:var(--a3);--cr:123,47,255" title="Import (.json or .txt)">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--a3)" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
            <div class="dock-cmd-txt">Import</div>
          </div>
          <div class="dock-cmd" id="sb-vault-settings" style="--cc:var(--a2);--cr:0,212,255" title="Vault Settings">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--a2)" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
            <div class="dock-cmd-txt">Settings</div>
          </div>
          <div class="dock-cmd full danger" id="sb-clr" title="Forget Everything">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--danger)" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>
            <div class="dock-cmd-txt">Forget Everything</div>
          </div>
        </div>
      </div>
    </aside>

    <main class="main" id="main">
      <div class="backup-banner" id="backup-banner">
        <div class="bb-txt" id="bb-txt"></div>
        <button class="bb-btn" id="bb-do">backup now</button>
        <button class="bb-x" id="bb-x">✕</button>
      </div>
      <div class="update-log" id="update-log">
        <div class="update-log-hd">
          <div class="update-log-title" id="update-log-title"></div>
          <button class="update-log-x" id="update-log-x">✕</button>
        </div>
        <div class="update-log-list" id="update-log-list"></div>
      </div>
      <div class="paste-panel" id="paste-panel">
        <div class="paste-hd" id="paste-toggle">
          <div class="paste-hd-title">Paste Cookies</div>
          <div class="paste-chev">▾</div>
        </div>
        <div class="paste-body">
          <div style="display:flex;gap:6px;margin-bottom:6px;align-items:center;">
            <button class="btn-primary" id="paste-from-clip-btn" style="background:rgba(0,212,255,.08);border:1px solid rgba(0,212,255,.25);box-shadow:none;font-size:10px;padding:5px 10px;">
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right:4px;vertical-align:middle"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><rect x="8" y="2" width="8" height="4" rx="1" ry="1"/></svg>Paste from clipboard
            </button>
            <span id="paste-fmt-label" style="font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:.5px;"></span>
          </div>
          <textarea class="paste-ta" id="paste-ta"
            placeholder="username:password:cookie&#10;username:cookie&#10;cookie only"></textarea>
          <div class="paste-ft">
            <div class="paste-info" id="paste-info">Awaiting input...</div>
            <div class="paste-ft-btns">
              <button class="btn-primary" id="create-group-btn" style="background:rgba(123,47,255,.2);border:1px solid rgba(123,47,255,.4);box-shadow:none;font-size:11px;padding:7px 12px;" title="Create an empty group">+ Empty Group</button>
              <button class="btn-primary" id="distribute-btn" style="display:none;background:rgba(0,212,255,.12);border:1px solid rgba(0,212,255,.35);box-shadow:none;font-size:11px;padding:7px 12px;" title="Distribute into multiple groups">⟁ Distribute</button>
              <button class="btn-primary" id="add-btn" disabled>+ Add to Vault</button>
            </div>
          </div>
        </div>
      </div>

      <!-- COOKIE EXTRACTOR -->
      <div class="cx-panel" id="cx-panel">
        <div class="cx-hdr" id="cx-toggle">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>
          <div class="cx-title">Cookie Extractor</div>
          <div id="cx-match-count" class="cx-match-count"></div>
          <span class="cx-chev" id="cx-chev">▾</span>
        </div>
        <div class="cx-body" id="cx-body">
          <textarea class="cx-ta" id="cx-ta" placeholder="Paste usernames — one per line, or username:anything:anything&#10;gam3sNoahstudioyt:Failed_Recovery:Captcha_Required&#10;Aria3ll4playzrrbx492:..."></textarea>
          <div class="cx-info" id="cx-info"></div>
          <div class="cx-actions">
            <button class="btn-primary" id="cx-search-btn" style="font-size:11px;padding:7px 14px;">
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="margin-right:5px;vertical-align:middle"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>Extract
            </button>
            <button class="bsm b-ghost" id="cx-copy-all-btn" style="display:none;font-size:11px;">Copy all matched (u:p:c)</button>
            <button class="bsm b-ghost" id="cx-clear-btn" style="font-size:11px;">Clear</button>
          </div>
          <div class="cx-results" id="cx-results"></div>
        </div>
      </div>

      <div class="filter-bar" id="filter-bar">
        <button class="filter-pill on" data-filter="all">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/></svg>All
        </button>
        <button class="filter-pill" data-filter="pinned">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/><circle cx="12" cy="10" r="3"/></svg>Pinned
        </button>
        <button class="filter-pill f-banned" data-filter="banned">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>Banned
        </button>
        <button class="filter-pill f-alts" data-filter="alts">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="6" y1="3" x2="6" y2="15"/><circle cx="18" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M18 9a9 9 0 0 1-9 9"/></svg>Has Alts
        </button>
        <button class="filter-pill" data-filter="empty">
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>Empty
        </button>
        <div class="health-badge" id="health-badge" title="Vault Health Score — click for breakdown">
          <span class="health-lbl">health</span>
          <span class="health-score" id="health-score">—</span>
          <span class="health-grade" id="health-grade">?</span>
        </div>
      </div>
      <div id="vault"></div>
    </main>
  </div>
</div>

<!-- EXPORT POPUP -->
<div class="exp-popup" id="exp-popup">
  <div class="exp-pop-label">Export Format</div>
  <button class="exp-pop-btn" data-expfmt="user:pass:cookie">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#00ffaa" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
    <span class="exp-pop-btn-main">u:p:c</span><span class="exp-pop-btn-sub">user:pass:cookie</span>
  </button>
  <button class="exp-pop-btn" data-expfmt="user:cookie">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#00ffaa" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
    <span class="exp-pop-btn-main">u:c</span><span class="exp-pop-btn-sub">user:cookie</span>
  </button>
  <button class="exp-pop-btn" data-expfmt="cookie">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#00ffaa" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
    <span class="exp-pop-btn-main">cookie</span><span class="exp-pop-btn-sub">raw only</span>
  </button>
  <button class="exp-pop-btn" data-expfmt="username">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#00ffaa" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
    <span class="exp-pop-btn-main">u</span><span class="exp-pop-btn-sub">username only</span>
  </button>
  <div class="exp-pop-sep"></div>
  <button class="exp-pop-btn" data-expfmt="json">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="var(--a2)" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
    <span class="exp-pop-btn-main">vault.json</span><span class="exp-pop-btn-sub">full backup</span>
  </button>
</div>

<!-- MOVE COOKIE MODAL -->
<div class="m-ov" id="move-cookie-modal">
  <div class="modal" style="width:min(92vw,380px)">
    <h3>Move Cookie</h3>
    <p id="move-cookie-desc" style="margin-bottom:12px;font-size:12px;color:var(--dim)"></p>
    <div style="font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;margin-bottom:6px;text-transform:uppercase;">Select destination group</div>
    <div id="move-cookie-list" style="max-height:260px;overflow-y:auto;display:flex;flex-direction:column;gap:4px;"></div>
    <div class="m-act" style="margin-top:14px">
      <button class="bsm b-ghost" id="move-cookie-cancel">Cancel</button>
    </div>
  </div>
</div>

<!-- SWAP COOKIE MODAL -->
<div class="m-ov" id="swap-modal">
  <div class="modal" style="width:min(94vw,420px)">
    <h3>Swap Cookie</h3>
    <p id="swap-modal-desc" style="margin-size:11px;color:var(--dim);margin-bottom:12px;"></p>
    <div class="swap-tabs">
      <button class="swap-tab on" id="swap-tab-paste">Paste new</button>
      <button class="swap-tab" id="swap-tab-alts">From alts</button>
    </div>
    <div id="swap-paste-panel" style="margin-top:10px;">
      <textarea class="finput" id="swap-paste-ta" rows="3" placeholder="username:password:cookie" style="font-family:var(--mono);font-size:11px;resize:none;"></textarea>
      <div id="swap-paste-info" style="font-family:var(--mono);font-size:9px;color:var(--dim);margin-top:4px;"></div>
    </div>
    <div id="swap-alts-panel" style="display:none;margin-top:10px;">
      <div id="swap-alts-list" style="display:flex;flex-direction:column;gap:6px;max-height:200px;overflow-y:auto;"></div>
    </div>
    <div style="margin-top:14px;">
      <div style="font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;margin-bottom:8px;text-transform:uppercase;">Reason for swap</div>
      <div style="display:flex;gap:8px;">
        <button class="swap-reason-btn on" data-reason="1d">1 day ban</button>
        <button class="swap-reason-btn" data-reason="7d">7 day ban</button>
        <button class="swap-reason-btn" data-reason="perm">Permanent</button>
        <button class="swap-reason-btn" data-reason="expired">Expired</button>
      </div>
    </div>
    <div class="m-act" style="margin-top:14px;">
      <button class="bsm b-ghost" id="swap-cancel">Cancel</button>
      <button class="bsm b-save" id="swap-confirm">Swap</button>
    </div>
  </div>
</div>

<!-- SYNC NOW POPUP -->
<div class="m-ov" id="sync-now-modal">
  <div class="modal" style="width:min(92vw,380px)">
    <h3>Sync Vault</h3>
    <p style="margin-bottom:14px;font-size:12px;color:var(--dim)">Paste u:p:c lines or upload a vault .json file to merge into the current vault.</p>
    <div class="swap-tabs" style="margin-bottom:10px;">
      <button class="swap-tab on" id="sync-tab-paste">Paste u:p:c</button>
      <button class="swap-tab" id="sync-tab-file">Upload file</button>
    </div>
    <div id="sync-paste-panel">
      <textarea class="finput" id="sync-paste-ta" rows="5" placeholder="username:password:cookie&#10;one per line" style="font-family:var(--mono);font-size:11px;resize:none;"></textarea>
      <div id="sync-paste-info" style="font-family:var(--mono);font-size:9px;color:var(--dim);margin-top:4px;"></div>
    </div>
    <div id="sync-file-panel" style="display:none;">
      <button class="bsm b-ghost" style="width:100%;" id="sync-file-pick">Choose .json or .txt file</button>
      <div id="sync-file-info" style="font-family:var(--mono);font-size:10px;color:var(--dim);margin-top:8px;"></div>
    </div>
    <div class="m-act" style="margin-top:14px;">
      <button class="bsm b-ghost" id="sync-now-cancel">Cancel</button>
      <button class="bsm b-save" id="sync-now-confirm">Sync</button>
    </div>
  </div>
</div>

<!-- BULK ACTION BAR -->
<div class="bulk-bar" id="bulk-bar">
  <div class="bulk-bar-count" id="bulk-bar-count">0 selected</div>
  <button class="bulk-bar-btn" id="bulk-bar-export">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>Export
  </button>
  <button class="bulk-bar-btn" id="bulk-bar-copy">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>Copy All
  </button>
  <button class="bulk-bar-btn" id="bulk-bar-ban">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/></svg>Ban All
  </button>
  <button class="bulk-bar-btn danger" id="bulk-bar-delete">
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>Delete All
  </button>
  <button class="bulk-bar-cancel" id="bulk-bar-cancel">✕ Cancel</button>
</div>


<div class="m-ov" id="new-data-modal">
  <div class="modal" style="width:min(90vw,340px)">
    <h3>New Data Config</h3>
    <p style="margin-bottom:12px">Give this config a name. It will have its own separate vault data.</p>
    <input class="finput" id="new-data-name" maxlength="30" placeholder="e.g. Server 2, Backup..." style="margin-bottom:10px">
    <p style="font-size:11px;color:var(--dim);margin-bottom:14px">Or load from a .json vault file:</p>
    <button class="bsm b-ghost" style="width:100%;margin-bottom:14px" id="new-data-from-file">Load from .json file</button>
    <div class="m-act">
      <button class="bsm b-ghost" id="new-data-cancel">Cancel</button>
      <button class="bsm b-save" id="new-data-ok">Create</button>
    </div>
  </div>
</div>

<!-- IMPORT REVIEW MODAL -->
<div class="m-ov" id="import-review-modal">
  <div class="modal import-modal">
    <h3 id="import-review-title">Review Import</h3>
    <p id="import-review-summary" style="margin-bottom:12px"></p>
    <div class="import-scroll" id="import-review-scroll"></div>
    <div class="m-act" style="margin-top:14px">
      <button class="bsm b-ghost" id="import-review-cancel">Cancel</button>
      <button class="bsm b-save" id="import-review-ok">Apply Selected</button>
    </div>
  </div>
</div>


<!-- SORT/DISTRIBUTE PANEL (shown when 6+ cookies pasted) -->
<div class="m-ov" id="sort-modal">
  <div class="modal sort-modal">
    <h3>Distribute Cookies</h3>
    <p id="sort-modal-desc">Split <span id="sort-count">0</span> cookies into groups automatically.</p>
    <div class="flbl">Server name prefix (e.g. WH → WH 1, WH 2…)</div>
    <input class="finput" id="sort-server-pfx" placeholder="e.g. WH, SEC, FARM" maxlength="20">
    <div class="flbl">Group name prefix (e.g. SP → SP 1, SP 2…)</div>
    <input class="finput" id="sort-group-pfx" placeholder="e.g. SP, GRP, ALT" maxlength="20">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-top:10px;">
      <div>
        <div class="flbl">Max groups per server</div>
        <input class="finput" id="sort-groups-per-srv" type="number" min="1" max="18" value="18">
      </div>
      <div>
        <div class="flbl">Cookies per group</div>
        <input class="finput" id="sort-cookies-per-grp" type="number" min="1" max="50" value="5">
      </div>
    </div>
    <div class="sort-preview" id="sort-preview"></div>
    <div class="m-act">
      <button class="bsm b-ghost" id="sort-cancel">Cancel</button>
      <button class="bsm b-ghost" id="sort-preview-btn" style="border-color:var(--a2);color:var(--a2);">Preview</button>
      <button class="bsm b-save" id="sort-confirm">Create Groups</button>
    </div>
  </div>
</div>

<!-- ADD GROUP MODAL -->
<div class="m-ov" id="add-modal">
  <div class="modal">
    <h3>Name this group</h3>
    <p>Detected <span id="mc">0</span> cookie(s).
      <span id="mc-dup" style="color:var(--warn);display:none">(<span id="mc-dup-n">0</span> duplicates will be skipped)</span>
    </p>
    <div class="import-preview" id="import-preview"></div>
    <div class="flbl">Group name *</div>
    <input class="finput" id="mn" placeholder="e.g. Main Alts..." maxlength="40" style="margin-bottom:10px">
    <div class="flbl">Server name (optional)</div>
    <input class="finput" id="ms" placeholder="e.g. Bloxburg, Arsenal..." maxlength="60">
    <!-- merge suggestion shown when server matches existing -->
    <div id="merge-suggestion" style="display:none;margin-top:10px;background:rgba(0,212,255,.06);border:1px solid rgba(0,212,255,.2);border-radius:8px;padding:9px 12px;">
      <div style="font-family:var(--mono);font-size:9px;color:var(--a2);letter-spacing:1.5px;text-transform:uppercase;margin-bottom:7px;">↳ merge into existing group?</div>
      <div id="merge-list" style="display:flex;flex-direction:column;gap:4px;max-height:100px;overflow-y:auto;"></div>
    </div>
    <div class="m-act">
      <button class="bsm b-ghost" id="mc-cancel">cancel</button>
      <button class="bsm b-save" id="mc-ok">save group</button>
    </div>
  </div>
</div>

<!-- BULK EXPORT MODAL -->
<div class="m-ov" id="bulk-modal">
  <div class="modal bulk-modal">
    <h3 id="bk-title">Export all</h3>
    <p><span id="bk-meta"></span></p>
    <button class="bulk-opt" data-f="username"><span class="bulk-tag">u</span>username only</button>
    <button class="bulk-opt" data-f="cookie"><span class="bulk-tag">c</span>cookies only</button>
    <button class="bulk-opt" data-f="user:cookie"><span class="bulk-tag">u:c</span>username:cookie</button>
    <button class="bulk-opt" data-f="user:pass"><span class="bulk-tag">u:p</span>username:password</button>
    <button class="bulk-opt" data-f="user:pass:cookie"><span class="bulk-tag">u:p:c</span>username:password:cookie</button>
    <div class="m-act" style="margin-top:10px">
      <button class="bsm b-ghost" id="bk-cancel">cancel</button>
    </div>
  </div>
</div>

<!-- VAULT STATS MODAL -->
<div class="m-ov" id="stats-modal">
  <div class="modal stats-modal">
    <h3>Vault Stats</h3>
    <div class="stats-grid" id="stats-grid"></div>
    <div class="stat-fun" id="stats-fun"></div>
    <div class="m-act" style="margin-top:14px">
      <button class="bsm b-ghost" id="stats-close">close</button>
    </div>
  </div>
</div>

<!-- COOKIE ACTIVITY LOG MODAL -->
<div class="m-ov" id="cklog-modal">
  <div class="modal cklog-modal">
    <h3>Cookie Activity Log</h3>
    <div class="cklog-toolbar">
      <button class="cklog-filter on" data-ckfilter="all">All</button>
      <button class="cklog-filter" data-ckfilter="added">Added</button>
      <button class="cklog-filter" data-ckfilter="edited">Edited</button>
      <button class="cklog-filter" data-ckfilter="deleted">Deleted</button>
      <button class="cklog-filter" data-ckfilter="banned">Banned</button>
      <button class="cklog-filter" data-ckfilter="active">Active</button>
      <button class="cklog-filter" data-ckfilter="copied">Copied</button>
      <span class="cklog-count" id="cklog-count">0 entries</span>
    </div>
    <div class="cklog-scroll" id="cklog-scroll"></div>
    <div class="m-act" style="margin-top:14px;gap:8px;">
      <button class="bsm b-ghost" id="cklog-close">close</button>
      <button class="bsm b-ghost" id="cklog-dl-txt" title="Download full log as .txt">download .txt</button>
      <button class="bsm b-ghost" id="cklog-dl-json" title="Download full log as .json">download .json</button>
      <button class="bsm b-ghost" id="cklog-clear" style="color:var(--danger);border-color:rgba(255,48,96,.3)">clear log</button>
    </div>
  </div>
</div>

<!-- GLOBAL ALTS MODAL -->
<div class="m-ov" id="alts-modal">
  <div class="modal" style="width:min(96vw,560px);max-height:85vh;display:flex;flex-direction:column;">
    <h3>All Alternative Cookies</h3>
    <p style="font-size:11px;color:var(--dim);margin-bottom:12px;">All alt sets across the vault — tap Swap to move an alt into its group as the main cookie.</p>
    <div id="alts-modal-list" style="overflow-y:auto;flex:1;display:flex;flex-direction:column;gap:8px;"></div>
    <div class="m-act" style="margin-top:14px;">
      <button class="bsm b-ghost" id="alts-modal-close">Close</button>
    </div>
  </div>
</div>

<!-- APP CHANGELOG MODAL -->
<div class="m-ov" id="cl-modal">
  <div class="modal changelog-modal">
    <h3>App Changelog</h3>
    <p style="margin-bottom:14px">Version history of Saturnity Vault</p>
    <div class="changelog-scroll" id="cl-scroll"></div>
    <div class="m-act" style="margin-top:14px">
      <button class="bsm b-ghost" id="cl-close">close</button>
    </div>
  </div>
</div>

<!-- CUSTOM CONFIRM MODAL -->
<div class="m-ov" id="confirm-modal">
  <div class="modal" style="width:min(90vw,340px)">
    <h3 id="confirm-title">Confirm</h3>
    <p id="confirm-msg" style="margin-bottom:20px"></p>
    <div class="m-act">
      <button class="bsm b-ghost" id="confirm-cancel">cancel</button>
      <button class="bsm b-danger" id="confirm-ok">confirm</button>
    </div>
  </div>
</div>

<!-- RENAME VAULT MODAL -->
<div class="m-ov" id="rename-modal">
  <div class="modal" style="width:min(90vw,340px)">
    <h3>Rename Vault</h3>
    <p style="margin-bottom:12px">Choose a new name for your vault.</p>
    <input class="finput" id="rename-in" maxlength="40" placeholder="Saturnity Vault" style="margin-bottom:0">
    <div class="m-act">
      <button class="bsm b-ghost" id="rename-cancel">cancel</button>
      <button class="bsm b-save" id="rename-ok">rename</button>
    </div>
  </div>
</div>

<!-- UPDATE VAULT MODAL -->
<div class="m-ov" id="update-modal">
  <div class="modal update-modal">
    <h3>Sync Vault</h3>
    <p id="update-summary" style="margin-bottom:12px"></p>
    <div class="update-scroll" id="update-scroll"></div>
    <div class="m-act" style="margin-top:14px">
      <button class="bsm b-ghost" id="update-cancel">cancel</button>
      <button class="bsm b-save" id="update-commit">apply selected</button>
    </div>
  </div>
</div>

<!-- DETAIL PANEL -->
<div class="p-overlay" id="p-ov">
  <div class="p-back" id="p-back"></div>
  <div class="detail-panel">
    <div class="p-hdr">
      <div class="p-title-row">
        <div class="p-dot" id="p-dot"></div>
        <div class="p-name" id="p-name"></div>
        <button class="p-close" id="p-close">close</button>
      </div>
      <div class="p-badges">
        <div class="p-cnt" id="p-cnt"></div>
        <div class="p-srv" id="p-srv" style="display:none"></div>
      </div>
    </div>
    <div class="p-meta-section" id="p-meta-section">
      <div class="p-meta-row">
        <div class="p-meta-lbl">Account ID</div>
        <div class="p-meta-val empty" id="p-acct-id-val">Not set</div>
        <button class="p-meta-btn" id="p-acct-id-edit">Edit</button>
      </div>
      <div class="p-meta-row">
        <div class="p-meta-lbl">Private Server</div>
        <div class="p-meta-val empty" id="p-pslink-val">Not set</div>
        <button class="p-meta-btn copy" id="p-pslink-copy" style="display:none">Copy</button>
        <button class="p-meta-btn" id="p-pslink-edit">Edit</button>
      </div>
    </div>
    <div class="p-tools">
      <button class="p-btn" id="p-edit">Edit</button>
      <button class="p-btn" id="p-padd">+ Add</button>
      <button class="p-btn" id="p-exp">Export .txt</button>
      <button class="p-btn" id="p-pin-btn">Pin</button>
      <button class="p-btn p-ban-btn" id="p-ban-btn">Ban</button>
      <button class="p-btn red" id="p-del">Remove</button>
      <div class="p-cols">
        <button class="p-cpill on" data-pc="1">1</button>
        <button class="p-cpill" data-pc="2">2</button>
        <button class="p-cpill" data-pc="3">3</button>
      </div>
    </div>
    <div class="p-edit" id="p-edit-form">
      <div class="flbl">Group name</div>
      <input class="finput" id="p-en" maxlength="40">
      <div class="flbl">Server name</div>
      <input class="finput" id="p-es" maxlength="60" placeholder="leave blank to remove">
      <div class="edit-act">
        <button class="bsm b-ghost" id="p-ecancel">cancel</button>
        <button class="bsm b-save" id="p-esave">save</button>
      </div>
    </div>
    <div class="p-edit" id="p-padd-form">
      <div class="flbl">Paste new cookies</div>
      <textarea class="finput" id="p-padd-ta" rows="4" placeholder="username:password:cookie&#10;username:cookie&#10;cookie only" style="font-family:var(--mono);font-size:11px;resize:none;line-height:1.7;"></textarea>
      <div style="font-family:var(--mono);font-size:10px;color:var(--dim);margin-top:5px;" id="p-padd-info">Awaiting input...</div>
      <div class="edit-act">
        <button class="bsm b-ghost" id="p-padd-cancel">cancel</button>
        <button class="bsm b-save" id="p-padd-ok">add to group</button>
      </div>
    </div>
    <div class="p-scroll" id="p-scroll">
      <!-- Notes field -->
      <div class="p-notes-wrap" id="p-notes-wrap">
        <div class="p-notes-hd">
          <span style="font-family:var(--mono);font-size:9px;color:var(--dim);letter-spacing:1px;text-transform:uppercase;">Notes</span>
          <button class="p-meta-btn" id="p-notes-edit-btn">Edit</button>
        </div>
        <div class="p-notes-val" id="p-notes-val" style="font-family:var(--mono);font-size:11px;color:var(--dim);line-height:1.6;padding:4px 0;min-height:16px;white-space:pre-wrap;word-break:break-word;"></div>
        <textarea class="finput p-notes-ta" id="p-notes-ta" rows="3" placeholder="Add notes..." style="display:none;font-size:11px;resize:vertical;font-family:var(--mono);line-height:1.6;"></textarea>
        <div id="p-notes-actions" style="display:none;gap:6px;margin-top:6px;">
          <button class="bsm b-ghost" id="p-notes-cancel" style="font-size:10px;padding:4px 10px;">cancel</button>
          <button class="bsm b-save" id="p-notes-save" style="font-size:10px;padding:4px 10px;">save</button>
        </div>
      </div>
      <div class="ck-grid" id="p-grid" style="--pc:1"></div>
    </div>
  </div>
</div>

<!-- QUICK COPY -->
<div id="qc-backdrop"></div>
<div class="qc-popup" id="qc-popup">
  <div class="qc-hd">QUICK COPY</div>
  <button class="qc-btn" data-qf="cookie">cookies only</button>
  <button class="qc-btn" data-qf="user:cookie">username:cookie</button>
  <button class="qc-btn" data-qf="user:pass:cookie">username:password:cookie</button>
  <button class="qc-btn" data-qf="username">usernames only</button>
</div>

<input type="file" id="import-f" accept=".json" style="display:none">
<input type="file" id="import-tf" accept=".txt" style="display:none">
<input type="file" id="update-f" accept=".json,.txt" style="display:none">
<input type="file" id="import-unified" accept=".json,.txt" style="display:none">
<input type="file" id="ds-import-f" accept=".json" style="display:none">
<div id="toast"><span id="toast-msg"></span></div>

<script>
// ═══════════════════════════════════════
// STATE
// ═══════════════════════════════════════
const SK='saturnity_vault_v1',CK='cv_cols',SORT_K='cv_sort',SET_K='cv_settings';
const COOKIE_PFX='_|WARNING:-DO-NOT-SHARE-THIS.';
const DS_K='cv_data_configs',DS_ACTIVE_K='cv_active_config';
// Active config storage key — resolved before any vault read
let SK_ACTIVE=(()=>{const id=localStorage.getItem('cv_active_config')||'default';return'saturnity_vault_'+id;})();
// Data migration: if default config is empty but old key has data, migrate it
(()=>{
  try{
    const newKey='saturnity_vault_default';
    const oldKey='saturnity_vault_v1';
    if(!localStorage.getItem(newKey)&&localStorage.getItem(oldKey)){
      localStorage.setItem(newKey,localStorage.getItem(oldKey));
    }
  }catch(e){}
})();
const PALETTE=[
  {c:'#00d4ff',r:'0,212,255'},{c:'#7b2fff',r:'123,47,255'},
  {c:'#00ffaa',r:'0,255,170'},{c:'#ff6b00',r:'255,107,0'},
  {c:'#ff3060',r:'255,48,96'},{c:'#ffaa00',r:'255,170,0'},
  {c:'#00aaff',r:'0,170,255'},{c:'#ff00aa',r:'255,0,170'},
  {c:'#aaff00',r:'170,255,0'},{c:'#aa00ff',r:'170,0,255'},
];
const ccache={};

let vault=loadVault();
let pending=[],panelId=null,bulkGroups=[],bulkLabel='';
let lastDeleted=null,undoTimer=null;
let cols=parseInt(localStorage.getItem(CK))||2;
let sort=(()=>{const s=localStorage.getItem(SORT_K);return['az','za','newest','most'].includes(s)?s:'az';})();
let listView=localStorage.getItem('cv_list_view')==='1';
let settings=loadSettings();
let qcGroupId=null,activeSrv='all';
let staggerTimers=[];
let confirmResolve=null;
let updateCandidates=[];

// ── v4.7 state ──
const REAL_PIN='180801';
const GH_PAT_K='cv_gh_pat',GH_GIST_K='cv_gh_gist',GH_EN_K='cv_gh_enabled';
let pinBuffer='',pinFails=0,pinLocked=false,pinLockUntil=0,decoyMode=false;
let ghPendingSync=false,ghDebounceTimer=null;
let activeFilter='all';

function getColor(name){
  if(!name)return PALETTE[0];
  const k=(name||'').trim().toLowerCase();
  if(ccache[k])return ccache[k];
  let h=0;for(const c of k)h=(h*31+c.charCodeAt(0))>>>0;
  return ccache[k]=PALETTE[h%PALETTE.length];
}
function loadSettings(){
  try{const r=localStorage.getItem(SET_K);return r?{...defSettings(),...JSON.parse(r)}:defSettings();}
  catch{return defSettings();}
}
function defSettings(){return{vaultName:'Saturnity Vault',firstCreated:Date.now(),lastOpen:null,lastBackup:null,cardSize:'md',streak:0};}
function saveSettings(){localStorage.setItem(SET_K,JSON.stringify(settings));}
function saveVault(){
  if(decoyMode)return; // decoy mode: never persist
  const _sk=typeof SK_ACTIVE!=='undefined'?SK_ACTIVE:SK;
  try{localStorage.setItem(_sk,JSON.stringify(vault));}
  catch(e){
    if(e&&(e.name==='QuotaExceededError'||e.name==='NS_ERROR_DOM_QUOTA_REACHED'||e.code===22)){
      toast('Storage full — vault not saved. Export a backup now.','err');
      return;
    }
  }
  scheduleGhSync();
}
function loadVault(){
  const _sk=typeof SK_ACTIVE!=='undefined'?SK_ACTIVE:SK;
  try{const r=localStorage.getItem(_sk);return r?JSON.parse(r):[]}catch{return[];}
}

// ═══════════════════════════════════════
// INIT
// ═══════════════════════════════════════
function updateStreak(){
  const today=new Date().toDateString();
  if(settings.lastOpen===today)return;
  const yesterday=new Date(Date.now()-86400000).toDateString();
  settings.streak=settings.lastOpen===yesterday?(settings.streak||0)+1:1;
  settings.lastOpen=today;saveSettings();
}

updateStreak();
setVaultTitle();

document.getElementById('vault-title').addEventListener('click',openRenameVault);
document.getElementById('stats-btn').addEventListener('click',showStats);
document.getElementById('hdr-stats-btn').addEventListener('click',showStats);
document.getElementById('hdr-cl-btn').addEventListener('click',()=>{buildChangelogModal();openMod('cl-modal');});

// Column pills
document.querySelectorAll('.col-pill').forEach(p=>{
  p.classList.toggle('on',parseInt(p.dataset.c)===cols);
  p.addEventListener('click',()=>{
    cols=parseInt(p.dataset.c);localStorage.setItem(CK,cols);
    document.querySelectorAll('.col-pill').forEach(x=>x.classList.toggle('on',parseInt(x.dataset.c)===cols));
    document.querySelectorAll('.card-grid').forEach(g=>g.style.setProperty('--cols',cols));
  });
});

// Card size
document.body.dataset.csize=settings.cardSize||'md';
document.getElementById('size-btn').textContent=(settings.cardSize||'md').toUpperCase();
document.getElementById('size-btn').addEventListener('click',()=>{
  const sizes=['sm','md','lg'];
  const idx=sizes.indexOf(settings.cardSize||'md');
  settings.cardSize=sizes[(idx+1)%sizes.length];saveSettings();
  document.body.dataset.csize=settings.cardSize;
  document.getElementById('size-btn').textContent=settings.cardSize.toUpperCase();
});

// Sort
const sb2=document.getElementById('sort-btn');
const SLBL={az:'A→Z',za:'Z→A',newest:'Newest',most:'Most'};
sb2.textContent=SLBL[sort];
sb2.addEventListener('click',()=>{
  const o=['az','za','newest','most'];sort=o[(o.indexOf(sort)+1)%o.length];
  localStorage.setItem(SORT_K,sort);sb2.textContent=SLBL[sort];render();
});

// List View
function applyListView(){
  document.body.classList.toggle('list-view',listView);
  const btn=document.getElementById('list-view-btn');
  if(btn)btn.classList.toggle('active',listView);
}
applyListView();
document.getElementById('list-view-btn').addEventListener('click',()=>{
  listView=!listView;
  localStorage.setItem('cv_list_view',listView?'1':'0');
  applyListView();
});

// Search
document.getElementById('search-in').addEventListener('input',()=>{
  const val=document.getElementById('search-in').value;
  document.getElementById('srch-clear').classList.toggle('visible',val.length>0);
  applyFilter();
});
document.getElementById('srch-clear').addEventListener('click',()=>{
  document.getElementById('search-in').value='';
  document.getElementById('srch-clear').classList.remove('visible');
  applyFilter();
  document.getElementById('search-in').focus();
});

// Paste
const ppanel=document.getElementById('paste-panel');
document.getElementById('paste-toggle').addEventListener('click',()=>ppanel.classList.toggle('open'));
['hdr-add'].forEach(id=>document.getElementById(id).addEventListener('click',()=>{
  ppanel.classList.add('open');
  document.getElementById('main').scrollTo({top:0,behavior:'smooth'});
  setTimeout(()=>document.getElementById('paste-ta').focus(),200);
}));
const ta=document.getElementById('paste-ta'),pi=document.getElementById('paste-info'),ab=document.getElementById('add-btn');
ta.addEventListener('input',()=>{
  const raw=ta.value.trim();
  const fmtLabel=document.getElementById('paste-fmt-label');
  if(!raw){pi.innerHTML='Awaiting input...';ab.disabled=true;
    document.getElementById('distribute-btn').style.display='none';
    if(fmtLabel)fmtLabel.textContent='';return;}
  const lines=raw.split('\n').filter(l=>l.trim());
  const p=parseInput(raw);
  const invalid=lines.filter(l=>!parseLine(l)).length;
  if(!p.length){pi.innerHTML='<span style="color:var(--danger)">No valid cookies</span>';ab.disabled=true;
    document.getElementById('distribute-btn').style.display='none';
    if(fmtLabel)fmtLabel.textContent='';
  }else{
    const invalidTxt=invalid>0?` · <span style="color:var(--danger)">${invalid} invalid</span>`:'';
    pi.innerHTML=`<span>${p.length} valid</span>${invalidTxt}`;ab.disabled=false;
    document.getElementById('distribute-btn').style.display=p.length>=6?'':'none';
    // Detect dominant format
    if(fmtLabel){
      const hasPwd=p.filter(c=>c.password).length;
      const hasUser=p.filter(c=>c.username).length;
      const fmt=hasPwd>p.length/2?'u:p:c':hasUser>p.length/2?'u:c':'cookie only';
      fmtLabel.textContent='detected: '+fmt;
      fmtLabel.style.color=fmt==='u:p:c'?'var(--ok)':fmt==='u:c'?'var(--a2)':'var(--dim)';
    }
  }
});
ab.addEventListener('click',()=>{const p=parseInput(ta.value);if(p.length)openAddModal(p);});
document.getElementById('distribute-btn').addEventListener('click',()=>{
  const p=parseInput(ta.value);if(p.length>=6)openSortModal(p);
});

// Add modal — merge suggestion on server name input
document.getElementById('ms').addEventListener('input',()=>{
  const srv=document.getElementById('ms').value.trim().toLowerCase();
  const sug=document.getElementById('merge-suggestion');
  const list=document.getElementById('merge-list');
  if(!srv){sug.style.display='none';return;}
  const matches=vault.filter(g=>(g.serverName||'').trim().toLowerCase()===srv);
  if(!matches.length){sug.style.display='none';return;}
  sug.style.display='block';
  list.innerHTML='';
  matches.forEach(g=>{
    const btn=document.createElement('button');
    btn.style.cssText='background:rgba(0,212,255,.08);border:1px solid rgba(0,212,255,.2);border-radius:6px;padding:5px 10px;font-family:var(--mono);font-size:10px;color:var(--a2);cursor:pointer;text-align:left;width:100%;transition:all .12s;';
    btn.textContent=`${g.name}  ·  ${g.cookies.length} cookies`;
    btn.addEventListener('mouseenter',()=>btn.style.background='rgba(0,212,255,.18)');
    btn.addEventListener('mouseleave',()=>btn.style.background='rgba(0,212,255,.08)');
    btn.addEventListener('click',e=>{
      e.preventDefault();
      mergeIntoGroup(g.id);
    });
    list.appendChild(btn);
  });
});

// Add modal
document.getElementById('mc-cancel').addEventListener('click',()=>closeMod('add-modal'));
document.getElementById('mc-ok').addEventListener('click',confirmAdd);
['mn','ms'].forEach(id=>document.getElementById(id).addEventListener('keydown',e=>{if(e.key==='Enter')confirmAdd();}));

// Bulk modal
document.getElementById('bk-cancel').addEventListener('click',()=>closeMod('bulk-modal'));
document.querySelectorAll('.bulk-opt').forEach(btn=>btn.addEventListener('click',()=>{
  const fmt=btn.dataset.f;
  // Sort groups in display order (sortVault) then flatten cookies in array order (top-to-bottom)
  const sortedGroups=sortVault(bulkGroups);
  const all=sortedGroups.flatMap(g=>g.cookies);
  const lines=all.map(c=>fmtLine(c,fmt)).filter(Boolean);
  dl(lines.join('\n'),sf(bulkLabel)+'.txt');
  toast(`Exported ${lines.length} entries as ${fmt}`,'ok');
  closeMod('bulk-modal');
}));

// Panel
document.getElementById('p-back').addEventListener('click',closePanel);
document.getElementById('p-close').addEventListener('click',closePanel);
document.getElementById('p-edit').addEventListener('click',()=>{
  const f=document.getElementById('p-edit-form'),g=vault.find(x=>x.id===panelId);if(!g)return;
  document.getElementById('p-padd-form').classList.remove('open'); // close add form if open
  if(f.classList.contains('open')){f.classList.remove('open');return;}
  document.getElementById('p-en').value=g.name;
  document.getElementById('p-es').value=g.serverName||'';
  f.classList.add('open');document.getElementById('p-en').focus();
});
document.getElementById('p-padd').addEventListener('click',()=>{
  const f=document.getElementById('p-padd-form');
  document.getElementById('p-edit-form').classList.remove('open'); // close edit form if open
  if(f.classList.contains('open')){f.classList.remove('open');return;}
  document.getElementById('p-padd-ta').value='';
  document.getElementById('p-padd-info').textContent='Awaiting input...';
  f.classList.add('open');
  setTimeout(()=>document.getElementById('p-padd-ta').focus(),120);
});
document.getElementById('p-padd-ta').addEventListener('input',()=>{
  const p=parseInput(document.getElementById('p-padd-ta').value);
  const info=document.getElementById('p-padd-info');
  if(!document.getElementById('p-padd-ta').value.trim()){info.textContent='Awaiting input...';return;}
  info.innerHTML=p.length?`<span style="color:var(--ok)">${p.length} detected</span>`:'<span style="color:var(--danger)">No valid cookies</span>';
});
document.getElementById('p-padd-cancel').addEventListener('click',()=>document.getElementById('p-padd-form').classList.remove('open'));
document.getElementById('p-padd-ok').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const parsed=parseInput(document.getElementById('p-padd-ta').value);
  if(!parsed.length){toast('No valid cookies','err');return;}
  const existingCookies=new Set(g.cookies.map(c=>c.cookie));
  const fresh=parsed.filter(c=>!existingCookies.has(c.cookie));
  const dupCount=parsed.length-fresh.length;
  if(!fresh.length){toast('All duplicates — nothing added','warn');return;}
  fresh.forEach(c=>g.cookies.push({...c}));
  logChange(g,`Added <span>${fresh.length}</span> cookie${fresh.length!==1?'s':''}${dupCount?` (${dupCount} dupes skipped)`:''}`);
  saveVault();
  document.getElementById('p-padd-form').classList.remove('open');
  refreshPanel();
  // update card count
  const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
  if(card){
    const countEl=card.querySelector('.gcard-count');if(countEl)countEl.textContent=flavorCount(g.cookies.length);
    card.dataset.users=g.cookies.map(c=>c.username||'').join(' ').toLowerCase();
  }
  toast(`Added ${fresh.length} cookies to "${g.name}"${dupCount?` · ${dupCount} dupes skipped`:''}`, 'ok');
});
document.getElementById('p-ecancel').addEventListener('click',()=>document.getElementById('p-edit-form').classList.remove('open'));
document.getElementById('p-esave').addEventListener('click',saveEdit);
['p-en','p-es'].forEach(id=>document.getElementById(id).addEventListener('keydown',e=>{if(e.key==='Enter')saveEdit();}));
document.getElementById('p-exp').addEventListener('click',()=>{const g=vault.find(x=>x.id===panelId);if(g)expTxt(g);});
document.getElementById('p-del').addEventListener('click',async()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const ok=await customConfirm(`Remove group "${g.name}"?`,'Remove');
  if(!ok)return;
  closePanel();delGroup(g.id);
});
document.getElementById('p-pin-btn').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  g.pinned=!g.pinned;
  logChange(g,g.pinned?'Pinned to top':'Unpinned');
  saveVault();buildSidebar();refreshPanel();
  document.getElementById('p-pin-btn').classList.toggle('pin-on',g.pinned);
  const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
  if(card){
    let pinEl=card.querySelector('.gcard-pin');
    if(g.pinned&&!pinEl){const p=document.createElement('div');p.className='gcard-pin';p.textContent='📌';card.appendChild(p);}
    else if(!g.pinned&&pinEl)pinEl.remove();
  }
  toast(g.pinned?'Group pinned':'Group unpinned','ok');
});
document.getElementById('p-ban-btn').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  g.banned=!g.banned;
  logChange(g,g.banned?'Marked as <span style="color:var(--danger)">BANNED</span>':'Ban tag removed');
  saveVault();refreshPanel();
  // update card
  const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
  if(card){
    card.classList.toggle('banned',g.banned);
    let banTag=card.querySelector('.gcard-banned-tag');
    if(g.banned&&!banTag){const t=document.createElement('div');t.className='gcard-banned-tag';t.textContent='🚫 banned';card.appendChild(t);}
    else if(!g.banned&&banTag)banTag.remove();
  }
  toast(g.banned?'Group marked as banned':'Ban tag removed',g.banned?'warn':'ok');
});
document.querySelectorAll('.p-cpill').forEach(p=>p.addEventListener('click',()=>{
  const v=parseInt(p.dataset.pc);
  document.getElementById('p-grid').style.setProperty('--pc',v);
  document.querySelectorAll('.p-cpill').forEach(x=>x.classList.toggle('on',parseInt(x.dataset.pc)===v));
  const g=vault.find(x=>x.id===panelId);if(g){g.pc=v;saveVault();}
}));

// QC
document.getElementById('qc-backdrop').addEventListener('click',closeQC);
document.querySelectorAll('.qc-btn').forEach(btn=>btn.addEventListener('click',()=>{
  const g=vault.find(x=>x.id===qcGroupId);if(!g){closeQC();return;}
  const lines=g.cookies.map(c=>fmtLine(c,btn.dataset.qf)).filter(Boolean);
  copyText(lines.join('\n'),()=>toast(`Copied ${lines.length} entries`,'ok'),()=>toast('Copy failed','err'));
  closeQC();
}));

// Sidebar nav
document.getElementById('sb-nav').addEventListener('click',e=>{
  const item=e.target.closest('[data-t]');if(!item)return;
  const t=item.dataset.t;activeSrv=t;
  document.querySelectorAll('.sb-all,.sb-item').forEach(x=>x.classList.remove('on'));
  item.classList.add('on');
  setTimeout(()=>{
    if(t==='all')document.getElementById('main').scrollTo({top:0,behavior:'smooth'});
    else{const s=document.querySelector(`.server-sec[data-srv="${CSS.escape(t)}"]`);if(s)s.scrollIntoView({behavior:'smooth'});}
  },200);
});

// Dock commands
// EXPORT button → show popup
document.getElementById('sb-exp').addEventListener('click',e=>{
  if(!vault.length){toast('Nothing to export','err');return;}
  openExpPopup(e.currentTarget,null);
});
// Unified export popup handler
let expPopupTarget=null; // null=whole vault, array=specific groups
function openExpPopup(anchor,groups){
  expPopupTarget=groups||null;
  const popup=document.getElementById('exp-popup');
  popup.classList.add('open');
  const rect=anchor.getBoundingClientRect();
  let left=rect.left,top=rect.bottom+6;
  if(left+220>window.innerWidth-8)left=window.innerWidth-228;
  if(top+240>window.innerHeight-8)top=rect.top-246;
  popup.style.left=left+'px';popup.style.top=top+'px';
}
function closeExpPopup(){document.getElementById('exp-popup').classList.remove('open');}
document.querySelectorAll('.exp-pop-btn[data-expfmt]').forEach(btn=>{
  btn.addEventListener('click',()=>{
    const fmt=btn.dataset.expfmt;
    const src=expPopupTarget||(sortVault(vault));
    if(fmt==='json'){
      const expVault=expPopupTarget?expPopupTarget:vault;
      dl(JSON.stringify({version:1,exported:Date.now(),vault:expVault},null,2),`saturnity-vault-${Date.now()}.json`);
      settings.lastBackup=Date.now();saveSettings();
      document.getElementById('backup-banner').classList.remove('show');
      toast('Vault exported as .json','ok');
    }else{
      const lines=src.flatMap(g=>g.cookies.map(c=>fmtLine(c,fmt))).filter(Boolean);
      dl(lines.join('\n'),`saturnity-vault-${Date.now()}.txt`);
      settings.lastBackup=Date.now();saveSettings();
      document.getElementById('backup-banner').classList.remove('show');
      toast(`Exported ${lines.length} lines (${fmt})`,'ok');
    }
    closeExpPopup();
  });
});
document.addEventListener('click',e=>{
  const popup=document.getElementById('exp-popup');
  if(popup.classList.contains('open')&&!popup.contains(e.target)&&!e.target.closest('#sb-exp')&&!e.target.closest('.bulk-bar-export-anchor')){
    closeExpPopup();
  }
});
// COPY button → all u:p:c
document.getElementById('sb-clip').addEventListener('click',()=>{
  if(!vault.length){toast('Nothing to copy','err');return;}
  // Use sortVault to copy in display order (top to bottom)
  const lines=sortVault(vault).flatMap(g=>g.cookies.map(c=>fmtLine(c,'user:pass:cookie'))).filter(Boolean);
  copyText(lines.join('\n'),()=>{
    toast(`Copied ${lines.length} cookies (u:p:c)`,'ok');
  },()=>toast('Clipboard copy failed','err'));
});
// IMPORT button → unified (.json or .txt)
document.getElementById('sb-imp').addEventListener('click',()=>document.getElementById('import-unified').click());
// Sync vault → header button
document.getElementById('hdr-sync-btn').addEventListener('click',()=>openSyncNowModal());
document.getElementById('sb-clr').addEventListener('click',async()=>{
  if(!vault.length){toast('Already empty','err');return;}
  const ok=await customConfirm(`Forget everything? This will delete all ${vault.length} groups permanently. This cannot be undone.`,'Forget Everything');
  if(!ok)return;
  vault=[];saveVault();render();toast('Vault cleared','ok');
});

// File inputs
document.getElementById('import-f').addEventListener('change',function(){
  const f=this.files[0];if(!f)return;
  const r=new FileReader();r.onload=e=>{
    try{
      const d=JSON.parse(e.target.result);
      if(!d.vault||!Array.isArray(d.vault))throw new Error('bad format');
      const valid=d.vault.filter(g=>g&&typeof g==='object'&&g.id&&g.name&&Array.isArray(g.cookies));
      if(!valid.length){toast('No valid groups found','err');this.value='';return;}
      const ids=new Set(vault.map(g=>g.id));
      const ng=valid.filter(g=>!ids.has(g.id));
      vault=[...ng,...vault];saveVault();render();
      toast(`Imported ${ng.length} group(s) (${valid.length-ng.length} dupes skipped)`,'ok');
    }catch{toast('Invalid JSON file','err');}
    this.value='';
  };r.readAsText(f);
});
document.getElementById('import-tf').addEventListener('change',function(){
  const f=this.files[0];if(!f)return;
  const r=new FileReader();r.onload=e=>{
    const p=parseInput(e.target.result);
    if(!p.length){toast('No valid cookies in file','err');this.value='';return;}
    openAddModal(p,f.name.replace(/\.[^.]+$/,'').replace(/[_-]/g,' ').trim());
    this.value='';
  };r.readAsText(f);
});
document.getElementById('update-f').addEventListener('change',function(){
  const f=this.files[0];if(!f)return;
  const isTxt=f.name.toLowerCase().endsWith('.txt');
  const r=new FileReader();r.onload=e=>{
    if(isTxt){
      const parsed=parseInput(e.target.result);
      if(!parsed.length){toast('No valid cookies found in .txt','err');this.value='';return;}
      let updated=0,notFound=0;
      const log=[];
      parsed.forEach(incoming=>{
        if(!incoming.username){notFound++;return;}
        const uLow=incoming.username.toLowerCase();
        let matched=false;
        vault.forEach(g=>{
          g.cookies.forEach(c=>{
            if((c.username||'').toLowerCase()===uLow){
              const what=[];
              if(c.cookie!==incoming.cookie)what.push('cookie');
              if(incoming.password&&c.password!==incoming.password)what.push('pass');
              c.cookie=incoming.cookie;
              if(incoming.password)c.password=incoming.password;
              if(what.length){
                logChange(g,`${c.username}: ${what.join('+')} updated`);
                log.push({username:c.username,groupName:g.name,what});
                updated++;
              }
              // Auto-update banStatus if cookie is now valid
              if(incoming.banStatus==='active'&&c.banStatus&&c.banStatus!=='active'){
                c.banStatus='active';
              }
              matched=true;
            }
          });
        });
        if(!matched)notFound++;
      });
      saveVault();
      if(panelId)refreshPanel();
      render();
      if(log.length){
        const logEl=document.getElementById('update-log');
        const listEl=document.getElementById('update-log-list');
        document.getElementById('update-log-title').textContent=`${updated} account${updated!==1?'s':''} updated${notFound?` · ${notFound} not found`:''}`;
        listEl.innerHTML='';
        log.forEach(entry=>{
          const row=document.createElement('div');row.className='update-log-row';
          row.innerHTML=`<div class="update-log-user">${esc(entry.username)}</div>
            <div class="update-log-group">${esc(entry.groupName)}</div>
            <div class="update-log-badge">${entry.what.join('+')} ✓</div>`;
          listEl.appendChild(row);
        });
        logEl.classList.add('show');
        document.getElementById('main').scrollTo({top:0,behavior:'smooth'});
      }
      toast(`Updated ${updated} account${updated!==1?'s':''}${notFound?` · ${notFound} not found`:''}`,updated?'ok':'warn');
    }else{
      try{
        const d=JSON.parse(e.target.result);
        if(!d.vault||!Array.isArray(d.vault))throw new Error('bad format');
        const valid=d.vault.filter(g=>g&&typeof g==='object'&&g.id&&g.name&&Array.isArray(g.cookies));
        if(!valid.length){toast('No valid groups in file','err');this.value='';return;}
        openUpdateModal(valid);
      }catch{toast('Invalid JSON file','err');}
    }
    this.value='';
  };r.readAsText(f);
});

// Backup banner
document.getElementById('bb-do').addEventListener('click',()=>document.getElementById('sb-exp').click());
document.getElementById('bb-x').addEventListener('click',()=>document.getElementById('backup-banner').classList.remove('show'));
document.getElementById('update-log-x').addEventListener('click',()=>document.getElementById('update-log').classList.remove('show'));

// Mouse tilt (throttled)
let tiltFrame=null;
document.addEventListener('mousemove',e=>{
  if(tiltFrame)return;
  tiltFrame=requestAnimationFrame(()=>{
    tiltFrame=null;
    const card=e.target.closest('.gcard');if(!card)return;
    if(!card.classList.contains('vis'))return; // skip if entrance animation not yet complete
    const rect=card.getBoundingClientRect();
    const cx=rect.left+rect.width/2,cy=rect.top+rect.height/2;
    const dx=(e.clientX-cx)/rect.width,dy=(e.clientY-cy)/rect.height;
    card.style.transform=`perspective(300px) rotateY(${dx*10}deg) rotateX(${-dy*10}deg) translateY(-2px)`;
  });
});
document.addEventListener('mouseleave',e=>{
  const card=e.target&&e.target.closest?e.target.closest('.gcard'):null;
  if(card&&!card.contains(e.relatedTarget))card.style.transform='';
},true);

// Close export popup on outside click
document.addEventListener('click',e=>{
  const popup=document.getElementById('exp-popup');
  if(popup&&!popup.contains(e.target)&&e.target.id!=='sb-exp')popup.classList.remove('open');
  const dsDrop=document.getElementById('ds-dropdown');
  if(dsDrop&&!document.getElementById('data-switch-btn').contains(e.target))dsDrop.classList.remove('open');
});
// Modal backdrop
document.querySelectorAll('.m-ov').forEach(o=>o.addEventListener('click',e=>{
  if(e.target!==o)return;
  o.classList.remove('open');
  if(o.id==='confirm-modal'&&confirmResolve){confirmResolve(false);confirmResolve=null;}
}));

// Stats / changelog / rename modals
document.getElementById('stats-close').addEventListener('click',()=>closeMod('stats-modal'));
document.getElementById('cl-close').addEventListener('click',()=>closeMod('cl-modal'));
document.getElementById('rename-ok').addEventListener('click',()=>{
  const n=document.getElementById('rename-in').value.trim();
  if(n&&n!==settings.vaultName){settings.vaultName=n;saveSettings();setVaultTitle();}
  closeMod('rename-modal');
});
document.getElementById('rename-cancel').addEventListener('click',()=>closeMod('rename-modal'));
document.getElementById('rename-in').addEventListener('keydown',e=>{
  if(e.key==='Enter'){e.preventDefault();document.getElementById('rename-ok').click();}
  if(e.key==='Escape')closeMod('rename-modal');
});
// Confirm modal
document.getElementById('confirm-ok').addEventListener('click',()=>{
  closeMod('confirm-modal');if(confirmResolve){confirmResolve(true);confirmResolve=null;}
});
document.getElementById('confirm-cancel').addEventListener('click',()=>{
  closeMod('confirm-modal');if(confirmResolve){confirmResolve(false);confirmResolve=null;}
});
// Update modal
document.getElementById('update-cancel').addEventListener('click',()=>closeMod('update-modal'));
document.getElementById('update-commit').addEventListener('click',commitUpdate);

// UNIFIED IMPORT
document.getElementById('import-unified').addEventListener('change',function(){
  const f=this.files[0];if(!f)return;
  const isTxt=f.name.toLowerCase().endsWith('.txt');
  const r=new FileReader();r.onload=e=>{
    if(isTxt){
      const parsed=parseInput(e.target.result);
      if(!parsed.length){toast('No valid cookies in file','err');this.value='';return;}
      openAddModal(parsed,f.name.replace(/\.[^.]+$/,'').replace(/[_-]/g,' ').trim());
    }else{
      try{
        const d=JSON.parse(e.target.result);
        if(!d.vault||!Array.isArray(d.vault))throw new Error('bad format');
        const valid=d.vault.filter(g=>g&&typeof g==='object'&&g.id&&g.name&&Array.isArray(g.cookies));
        if(!valid.length){toast('No valid groups found','err');this.value='';return;}
        openUpdateModal(valid);
      }catch{toast('Invalid JSON file','err');}
    }
    this.value='';
  };r.readAsText(f);
});

// CREATE EMPTY GROUP button
document.getElementById('create-group-btn').addEventListener('click',()=>{
  const name=prompt('Group name:');
  if(!name||!name.trim())return;
  const serverName=prompt('Server name (optional, press Enter to skip):')||null;
  const group={
    id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),
    name:name.trim(),serverName:serverName?serverName.trim():null,
    createdAt:Date.now(),pinned:false,banned:false,alternatives:[],cookies:[],changelog:[]
  };
  logChange(group,'Created as empty group');
  sortedInsert(group);saveVault();render();
  toast(`"${group.name}" created (empty)`,'ok');
});

// PANEL METADATA events
document.getElementById('p-acct-id-edit').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const val=prompt('Account ID:',g.accountId||'');
  if(val===null)return;
  g.accountId=val.trim()||null;
  logChange(g,g.accountId?`Account ID set: <span>${esc(g.accountId)}</span>`:'Account ID removed');
  saveVault();refreshPanel();
});
document.getElementById('p-pslink-edit').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const val=prompt('Private Server Link:',g.privateServer||'');
  if(val===null)return;
  g.privateServer=val.trim()||null;
  logChange(g,g.privateServer?'Private server link updated':'Private server link removed');
  saveVault();refreshPanel();
});
document.getElementById('p-pslink-copy').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g||!g.privateServer)return;
  copyText(g.privateServer,()=>toast('Server link copied','ok'),()=>toast('Copy failed','err'));
});



// SWITCH DATA feature
function loadDataConfigs(){
  try{const r=localStorage.getItem(DS_K);return r?JSON.parse(r):[{id:'default',name:'Default'}];}
  catch{return[{id:'default',name:'Default'}];}
}
function saveDataConfigs(cfgs){localStorage.setItem(DS_K,JSON.stringify(cfgs));}
function getActiveConfigId(){return localStorage.getItem(DS_ACTIVE_K)||'default';}
function setActiveConfig(id){
  localStorage.setItem(DS_ACTIVE_K,id);
  // swap vault storage key
  SK_ACTIVE='saturnity_vault_'+id;
  vault=loadVaultForConfig(id);
  saveVault();render();
  const cfg=loadDataConfigs().find(c=>c.id===id);
  document.getElementById('data-switch-lbl').textContent=cfg?cfg.name:'Default';
  renderDataSwitcher();
}
function loadVaultForConfig(id){
  try{const r=localStorage.getItem('saturnity_vault_'+id);return r?JSON.parse(r):[]}catch{return[];}
}
function renderDataSwitcher(){
  const cfgs=loadDataConfigs();
  const active=getActiveConfigId();
  const drop=document.getElementById('ds-dropdown');
  drop.innerHTML='';
  cfgs.forEach(cfg=>{
    const item=document.createElement('div');item.className='ds-item'+(cfg.id===active?' active':'');
    const isDefault=cfg.id==='default';
    item.innerHTML=`<div class="ds-item-dot"></div><div class="ds-item-name">${esc(cfg.name)}</div>`;
    // Rename for all, delete for non-default only
    const actions=document.createElement('div');actions.className='ds-item-actions';
    const renBtn=document.createElement('button');renBtn.className='ds-action-btn rename';renBtn.title='Rename';
    renBtn.innerHTML='<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>';
    renBtn.addEventListener('click',e=>{
      e.stopPropagation();
      const nameEl=item.querySelector('.ds-item-name');
      const inp=document.createElement('input');inp.className='ds-rename-input';
      inp.value=cfg.name;inp.maxLength=30;
      nameEl.replaceWith(inp);actions.style.display='none';
      inp.focus();inp.select();
      function commitRename(){
        const newName=inp.value.trim();
        if(newName&&newName!==cfg.name){
          const cfgs2=loadDataConfigs();
          const cc=cfgs2.find(x=>x.id===cfg.id);
          if(cc)cc.name=newName;
          saveDataConfigs(cfgs2);
          if(cfg.id===active)document.getElementById('data-switch-lbl').textContent=newName;
          toast(`Renamed to "${newName}"`,'ok');
        }
        renderDataSwitcher();
      }
      inp.addEventListener('blur',commitRename);
      inp.addEventListener('keydown',e2=>{
        if(e2.key==='Enter'){e2.preventDefault();inp.blur();}
        if(e2.key==='Escape'){inp.value=cfg.name;inp.blur();}
      });
    });
    actions.appendChild(renBtn);
    if(!isDefault){
      const delBtn=document.createElement('button');delBtn.className='ds-action-btn del';delBtn.title='Delete';
      delBtn.innerHTML='<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>';
      delBtn.addEventListener('click',async e=>{
        e.stopPropagation();
        const ok=await customConfirm(`Delete config "${cfg.name}"? This permanently deletes all groups in it.`,'Delete');
        if(!ok)return;
        const cfgs2=loadDataConfigs().filter(x=>x.id!==cfg.id);
        saveDataConfigs(cfgs2);
        localStorage.removeItem('saturnity_vault_'+cfg.id);
        if(cfg.id===active)setActiveConfig('default');
        else renderDataSwitcher();
        toast(`Deleted "${cfg.name}"`,'ok');
      });
      actions.appendChild(delBtn);
    }
    item.appendChild(actions);
    item.querySelector('.ds-item-dot').addEventListener('click',e=>{e.stopPropagation();setActiveConfig(cfg.id);drop.classList.remove('open');});
    item.querySelector('.ds-item-name')?.addEventListener('click',e=>{e.stopPropagation();setActiveConfig(cfg.id);drop.classList.remove('open');});
    drop.appendChild(item);
  });
  const sep=document.createElement('div');sep.className='ds-sep';drop.appendChild(sep);
  const newBtn=document.createElement('button');newBtn.className='ds-new-btn';
  newBtn.innerHTML='<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg> New Config';
  newBtn.addEventListener('click',e=>{e.stopPropagation();drop.classList.remove('open');openMod('new-data-modal');document.getElementById('new-data-name').focus();});
  drop.appendChild(newBtn);
}
document.getElementById('data-switch-btn').addEventListener('click',e=>{
  e.stopPropagation();
  const drop=document.getElementById('ds-dropdown');
  renderDataSwitcher();
  const rect=e.currentTarget.getBoundingClientRect();
  drop.style.top=(rect.bottom+6)+'px';
  drop.style.right=(window.innerWidth-rect.right)+'px';
  drop.classList.toggle('open');
});
document.getElementById('new-data-cancel').addEventListener('click',()=>closeMod('new-data-modal'));
document.getElementById('new-data-ok').addEventListener('click',()=>{
  const name=document.getElementById('new-data-name').value.trim();
  if(!name){document.getElementById('new-data-name').focus();return;}
  const cfgs=loadDataConfigs();
  const id='cfg_'+Date.now().toString(36);
  cfgs.push({id,name});saveDataConfigs(cfgs);
  closeMod('new-data-modal');
  document.getElementById('new-data-name').value='';
  setActiveConfig(id);
  toast(`Switched to "${name}"`,'ok');
});
document.getElementById('new-data-from-file').addEventListener('click',()=>document.getElementById('ds-import-f').click());
document.getElementById('ds-import-f').addEventListener('change',function(){
  const f=this.files[0];if(!f)return;
  const r=new FileReader();r.onload=e=>{
    try{
      const d=JSON.parse(e.target.result);
      if(!d.vault||!Array.isArray(d.vault))throw new Error('bad');
      const name=document.getElementById('new-data-name').value.trim()||f.name.replace(/\.[^.]+$/,'').replace(/[_-]/g,' ').trim()||'Imported';
      const cfgs=loadDataConfigs();
      const id='cfg_'+Date.now().toString(36);
      cfgs.push({id,name});saveDataConfigs(cfgs);
      localStorage.setItem('saturnity_vault_'+id,JSON.stringify(d.vault));
      closeMod('new-data-modal');
      setActiveConfig(id);
      toast(`Loaded "${name}" (${d.vault.length} groups)`,'ok');
    }catch{toast('Invalid vault file','err');}
    this.value='';
  };r.readAsText(f);
});
// Init switcher label
(()=>{
  const cfgs=loadDataConfigs();
  const active=getActiveConfigId();
  const cfg=cfgs.find(c=>c.id===active)||{name:'Default'};
  document.getElementById('data-switch-lbl').textContent=cfg.name;
})();


checkBackupReminder();
render();
initPin();
setSyncDot(ghEnabled()?'ok':'off');

// ═══════════════════════════════════════
// TITLE / RENAME
// ═══════════════════════════════════════
function setVaultTitle(){
  const n=settings.vaultName||'Saturnity Vault';
  const parts=n.split(' ');
  const el=document.getElementById('vault-title');
  if(parts.length>=2)el.innerHTML=esc(parts[0])+' <span>'+esc(parts.slice(1).join(' '))+'</span>';
  else el.innerHTML='<span>'+esc(n)+'</span>';
}
function openRenameVault(){
  document.getElementById('rename-in').value=settings.vaultName||'Saturnity Vault';
  openMod('rename-modal');
  setTimeout(()=>{const inp=document.getElementById('rename-in');inp.focus();inp.select();},120);
}
function checkBackupReminder(){
  if(!vault.length)return;
  const last=settings.lastBackup;
  const days=last?Math.floor((Date.now()-last)/86400000):999;
  if(days>=3){
    document.getElementById('bb-txt').textContent=last?`No backup in ${days} days. Protect your vault.`:`You've never backed up your vault.`;
    document.getElementById('backup-banner').classList.add('show');
  }
}

// ═══════════════════════════════════════
// CUSTOM CONFIRM
// ═══════════════════════════════════════
function customConfirm(msg,actionLabel='Confirm'){
  return new Promise(res=>{
    confirmResolve=res;
    document.getElementById('confirm-msg').textContent=msg;
    document.getElementById('confirm-ok').textContent=actionLabel;
    openMod('confirm-modal');
  });
}

// ═══════════════════════════════════════
// ADD GROUP
// ═══════════════════════════════════════
function openAddModal(parsed,prefillName=''){
  const existingCookies=new Set(vault.flatMap(g=>g.cookies.map(c=>c.cookie)));
  const dups=parsed.filter(c=>existingCookies.has(c.cookie));
  const clean=parsed.filter(c=>!existingCookies.has(c.cookie));
  pending=clean;
  const prev=document.getElementById('import-preview');
  prev.innerHTML='';
  parsed.slice(0,8).forEach(c=>{
    const dup=existingCookies.has(c.cookie);
    const row=document.createElement('div');row.className='import-preview-row '+(dup?'dup':'ok');
    row.textContent=(dup?'[DUP] ':'[OK]  ')+(c.username||'anonymous')+' — '+c.cookie.substring(0,28)+'...';
    prev.appendChild(row);
  });
  if(parsed.length>8){const m=document.createElement('div');m.className='import-preview-row';m.textContent=`... and ${parsed.length-8} more`;prev.appendChild(m);}
  document.getElementById('mc').textContent=parsed.length;
  document.getElementById('mc-dup-n').textContent=dups.length;
  document.getElementById('mc-dup').style.display=dups.length?'inline':'none';
  document.getElementById('mn').value=prefillName;
  document.getElementById('ms').value='';
  openMod('add-modal');
  document.getElementById('mn').focus();
}
// ═══════════════════════════════════════
// MERGE INTO EXISTING GROUP
// ═══════════════════════════════════════
function mergeIntoGroup(groupId){
  const g=vault.find(x=>x.id===groupId);if(!g||!pending.length)return;
  const existingCookies=new Set(g.cookies.map(c=>c.cookie));
  const fresh=pending.filter(c=>!existingCookies.has(c.cookie));
  const dupCount=pending.length-fresh.length;
  if(!fresh.length){toast('All duplicates — nothing merged','warn');closeMod('add-modal');return;}
  fresh.forEach(c=>g.cookies.push({...c}));
  logChange(g,`Merged <span>${fresh.length}</span> cookie${fresh.length!==1?'s':''}${dupCount?` (${dupCount} dupes skipped)`:''}`);
  saveVault();
  document.getElementById('paste-ta').value='';
  document.getElementById('paste-info').innerHTML='Awaiting input...';
  document.getElementById('add-btn').disabled=true;
  closeMod('add-modal');render();
  setTimeout(()=>{
    const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
    if(card){card.classList.add('new-glow');setTimeout(()=>card.classList.remove('new-glow'),3000);}
  },50);
  toast(`Merged ${fresh.length} cookies into "${g.name}"${dupCount?` · ${dupCount} dupes skipped`:''}`, 'ok');
}

async function confirmAdd(){
  const name=document.getElementById('mn').value.trim();if(!name){document.getElementById('mn').focus();return;}
  if(!pending.length){toast('No valid cookies to save','err');closeMod('add-modal');return;}
  const serverName=document.getElementById('ms').value.trim()||null;

  // Auto-detect exact name + server match → offer merge
  const exactMatch=vault.find(g=>
    g.name.toLowerCase()===name.toLowerCase()&&
    (g.serverName||'').trim().toLowerCase()===(serverName||'').trim().toLowerCase()
  );
  if(exactMatch){
    const ok=await customConfirm(`"${name}" on server "${serverName||'(none)'}" already exists. Merge cookies into it?`,'Merge');
    if(ok){mergeIntoGroup(exactMatch.id);return;}
    // user said no → fall through to create new anyway
  }

  if(serverName){
    const k=serverName.trim().toLowerCase();
    const existing=vault.filter(g=>(g.serverName||'').trim().toLowerCase()===k);
    if(existing.length>=18){toast(`Server "${serverName}" has reached the 18 group limit`,'warn');return;}
  }
  const nameLower=name.toLowerCase();
  if(!exactMatch&&vault.find(g=>g.name.toLowerCase()===nameLower)){
    const ok=await customConfirm(`A group named "${name}" already exists. Create anyway?`,'Create');
    if(!ok)return;
  }
  const group={
    id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),
    name,serverName,createdAt:Date.now(),pinned:false,banned:false,alternatives:[],
    cookies:pending.map(c=>({...c})),changelog:[]
  };
  logChange(group,`Created with <span>${pending.length} cookie${pending.length!==1?'s':''}</span>`);
  sortedInsert(group);saveVault();
  document.getElementById('paste-ta').value='';
  document.getElementById('paste-info').innerHTML='Awaiting input...';
  document.getElementById('add-btn').disabled=true;
  closeMod('add-modal');render();
  setTimeout(()=>{
    const card=document.querySelector(`.gcard[data-id="${group.id}"]`);
    if(card){card.classList.add('fly-in','new-glow');setTimeout(()=>card.classList.remove('fly-in'),500);}
  },50);
  toast(`"${name}" saved (${pending.length} cookies)`,'ok');
}

// ═══════════════════════════════════════
// UPDATE VAULT (SMART MERGE)
// ═══════════════════════════════════════
function openUpdateModal(incoming){
  updateCandidates=[];
  const existingMap=new Map(vault.map(g=>[g.id,g]));
  let newCount=0,changedCount=0,sameCount=0;

  incoming.forEach(g=>{
    const existing=existingMap.get(g.id);
    if(!existing){
      updateCandidates.push({type:'new',group:g,selected:true});
      newCount++;
    }else{
      const existingCookieSet=new Set(existing.cookies.map(c=>c.cookie));
      const newCookies=g.cookies.filter(c=>!existingCookieSet.has(c.cookie));
      const removedCount=existing.cookies.filter(c=>!g.cookies.some(nc=>nc.cookie===c.cookie)).length;
      if(newCookies.length>0||removedCount>0){
        updateCandidates.push({type:'changed',group:g,existing,newCookies,removedCount,selected:false});
        changedCount++;
      }else{
        updateCandidates.push({type:'same',group:g,existing,selected:false});
        sameCount++;
      }
    }
  });

  document.getElementById('update-summary').innerHTML=
    `<span style="color:var(--ok)">${newCount} new</span> · <span style="color:var(--warn)">${changedCount} updated</span> · <span style="color:var(--dim)">${sameCount} unchanged</span>`;

  const scroll=document.getElementById('update-scroll');
  scroll.innerHTML='';

  const newOnes=updateCandidates.filter(c=>c.type==='new');
  const changedOnes=updateCandidates.filter(c=>c.type==='changed');
  const sameOnes=updateCandidates.filter(c=>c.type==='same');

  function makeSection(title,items){
    if(!items.length)return;
    const sec=document.createElement('div');sec.className='upd-section';
    sec.innerHTML=`<div class="upd-section-title">${title}</div>`;
    items.forEach((item,idx)=>{
      const row=document.createElement('div');row.className='upd-row';
      const globalIdx=updateCandidates.indexOf(item);
      let badge='',meta='';
      if(item.type==='new'){
        badge=`<span class="upd-badge new">new</span>`;
        meta=`${item.group.cookies.length} cookies`;
      }else if(item.type==='changed'){
        badge=`<span class="upd-badge changed">changed</span>`;
        meta=`+${item.newCookies.length} new${item.removedCount?` · -${item.removedCount} removed`:''}`;
      }else{
        badge=`<span class="upd-badge same">same</span>`;
        meta=`${item.group.cookies.length} cookies`;
      }
      const srv=item.group.serverName?`<span style="color:var(--dim);font-size:9px"> / ${esc(item.group.serverName)}</span>`:'';
      const toggleClass=item.selected?'on':'';
      row.innerHTML=`
        ${badge}
        <div class="upd-name">${esc(item.group.name)}${srv}</div>
        <div class="upd-meta">${meta}</div>
        ${item.type!=='same'?`<button class="upd-toggle ${toggleClass}" data-idx="${globalIdx}">${item.selected?'✓ include':'include'}</button>`:''}`;
      sec.appendChild(row);
    });
    scroll.appendChild(sec);
  }
  makeSection('New groups',newOnes);
  makeSection('Updated groups',changedOnes);
  makeSection('Unchanged',sameOnes);

  // Wire toggle buttons
  scroll.querySelectorAll('.upd-toggle').forEach(btn=>{
    btn.addEventListener('click',()=>{
      const idx=parseInt(btn.dataset.idx);
      updateCandidates[idx].selected=!updateCandidates[idx].selected;
      btn.classList.toggle('on',updateCandidates[idx].selected);
      btn.textContent=updateCandidates[idx].selected?'✓ include':'include';
    });
  });

  openMod('update-modal');
}

function commitUpdate(){
  let added=0,replaced=0;
  const existingMap=new Map(vault.map(g=>[g.id,g]));
  updateCandidates.forEach(item=>{
    if(!item.selected)return;
    if(item.type==='new'){
      vault.unshift({...item.group,changelog:item.group.changelog||[]});
      added++;
    }else if(item.type==='changed'){
      const existing=existingMap.get(item.group.id);
      if(existing){
        existing.cookies=[...item.group.cookies];
        logChange(existing,`Synced — ${item.newCookies.length} new cookie${item.newCookies.length!==1?'s':''}`);
        replaced++;
      }
    }
  });
  saveVault();render();
  closeMod('update-modal');
  if(added||replaced)toast(`Sync complete — ${added} added, ${replaced} updated`,'ok');
  else toast('Nothing selected to apply','warn');
}

// ═══════════════════════════════════════
// SORT + RENDER
// ═══════════════════════════════════════
function sortVault(arr){
  const cmp=(a,b)=>{
    if(sort==='az')return a.name.localeCompare(b.name,undefined,{sensitivity:'base'});
    if(sort==='za')return b.name.localeCompare(a.name,undefined,{sensitivity:'base'});
    if(sort==='newest')return(b.createdAt||0)-(a.createdAt||0);
    if(sort==='most')return b.cookies.length-a.cookies.length;
    return 0;
  };
  return[...arr.filter(g=>g.pinned).sort(cmp),...arr.filter(g=>!g.pinned).sort(cmp)];
}

function buildSidebar(){
  const sorted=sortVault(vault);
  const srvMap=new Map();
  sorted.forEach(g=>{
    if(g.serverName&&g.serverName.trim()){
      const k=g.serverName.trim().toLowerCase();
      if(!srvMap.has(k))srvMap.set(k,{label:g.serverName.trim(),groups:[]});
      srvMap.get(k).groups.push(g);
    }
  });
  const nav=document.getElementById('sb-nav');
  nav.querySelectorAll('.sb-item').forEach(x=>x.remove());
  const div=nav.querySelector('.sb-div');
  srvMap.forEach(({label,groups},k)=>{
    const col=getColor(label);
    const it=document.createElement('div');it.className='sb-item';it.dataset.t=k;
    if(activeSrv===k)it.classList.add('on');
    it.innerHTML=`<div class="sb-dot" style="background:${col.c};color:${col.c}"></div>
      <div class="sb-name">${esc(label)}</div>
      <div class="sb-badge">${groups.length}g</div>`;
    nav.insertBefore(it,div.nextSibling);
  });
  document.querySelector('.sb-all').classList.toggle('on',activeSrv==='all');
}

function render(){
  staggerTimers.forEach(t=>clearTimeout(t));staggerTimers=[];
  const vEl=document.getElementById('vault');vEl.innerHTML='';
  const sorted=sortVault(vault);
  const srvMap=new Map(),ug=[];
  sorted.forEach(g=>{
    if(g.serverName&&g.serverName.trim()){
      const k=g.serverName.trim().toLowerCase();
      if(!srvMap.has(k))srvMap.set(k,{label:g.serverName.trim(),groups:[]});
      srvMap.get(k).groups.push(g);
    }else ug.push(g);
  });
  buildSidebar();
  if(!vault.length){
    vEl.innerHTML=`<div class="empty-state"><p>No cookies stored yet.<br>Paste or import to get started.</p></div>`;
    animStats(0,0,0);return;
  }
  if(ug.length){
    const sec=document.createElement('div');sec.className='ug-sec';
    sec.innerHTML='<div class="ug-lbl">Ungrouped</div>';
    const grid=mkGrid();ug.forEach(g=>grid.appendChild(mkCard(g)));
    sec.appendChild(grid);vEl.appendChild(sec);
  }
  srvMap.forEach(({label,groups},k)=>{
    const col=getColor(label);
    const totalC=groups.reduce((s,g)=>s+g.cookies.length,0);
    const sec=document.createElement('div');sec.className='server-sec';sec.dataset.srv=k;
    const hd=document.createElement('div');hd.className='sec-head';
    const warn=groups.length>=18?`<span class="sec-warn">⚠ ${groups.length}/18</span>`:'';
    hd.innerHTML=`
      <div class="sec-dot" style="background:${col.c};box-shadow:0 0 8px ${col.c}"></div>
      <div class="sec-name-wrap">
        <div class="sec-name">${esc(label)}</div>
        <button class="sec-rename-btn" title="Rename server">✎</button>
      </div>
      <div class="sec-meta">${groups.length}g · ${totalC}c</div>
      ${warn}
      <button class="sec-copybtn" title="Copy all as u:p:c">
        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
      </button>
      <button class="sec-expbtn">export</button>`;
    hd.querySelector('.sec-copybtn').addEventListener('click',e=>{
      e.stopPropagation();
      const live=vault.filter(g=>(g.serverName||'').trim().toLowerCase()===k);
      const lines=live.flatMap(g=>g.cookies.map(c=>fmtLine(c,'user:pass:cookie'))).filter(Boolean);
      const btn=hd.querySelector('.sec-copybtn');
      copyText(lines.join('\n'),()=>{
        btn.style.color='var(--ok)';
        setTimeout(()=>btn.style.color='',1400);
        toast(`Copied ${lines.length} cookies`,'ok');
      },()=>toast('Copy failed','err'));
    });
    hd.querySelector('.sec-expbtn').addEventListener('click',e=>{
      e.stopPropagation();
      const live=vault.filter(g=>(g.serverName||'').trim().toLowerCase()===k);
      openExpPopup(e.currentTarget,live);
    });
    hd.querySelector('.sec-rename-btn').addEventListener('click',e=>{
      e.stopPropagation();
      const nameEl=hd.querySelector('.sec-name');
      const renameBtn=hd.querySelector('.sec-rename-btn');
      const input=document.createElement('input');
      input.className='sec-name-input';input.value=label;
      nameEl.replaceWith(input);renameBtn.style.display='none';
      input.focus();input.select();
      function commitRename(){
        const newName=input.value.trim();
        if(newName&&newName!==label){
          vault.forEach(g=>{if((g.serverName||'').trim().toLowerCase()===label.trim().toLowerCase())g.serverName=newName;});
          vault.filter(g=>(g.serverName||'')===newName).forEach(g=>logChange(g,`Server renamed to <span>${esc(newName)}</span>`));
          saveVault();render();toast(`Server renamed to "${newName}"`,'ok');
        }else{
          const restored=document.createElement('div');restored.className='sec-name';restored.textContent=label;
          input.replaceWith(restored);renameBtn.style.display='';
        }
      }
      input.addEventListener('blur',commitRename);
      input.addEventListener('keydown',e2=>{
        if(e2.key==='Enter'){e2.preventDefault();input.blur();}
        if(e2.key==='Escape'){input.value=label;input.blur();}
      });
    });
    sec.appendChild(hd);
    const grid=mkGrid();groups.forEach(g=>grid.appendChild(mkCard(g)));
    const tile=document.createElement('div');tile.className='exp-tile';
    tile.innerHTML=`<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg><span>export all</span>`;
    tile.addEventListener('click',e=>{
      const live=vault.filter(g=>(g.serverName||'').trim().toLowerCase()===k);
      openExpPopup(e.currentTarget,live);
    });
    grid.appendChild(tile);sec.appendChild(grid);vEl.appendChild(sec);
  });
  requestAnimationFrame(()=>{
    vEl.querySelectorAll('.gcard,.exp-tile').forEach((el,i)=>{
      const t=setTimeout(()=>el.classList.add('vis'),i*30);staggerTimers.push(t);
    });
    // filter applied by applyFilter() via setTimeout after render
  });
  animStats(vault.length,vault.reduce((s,g)=>s+g.cookies.length,0),srvMap.size);
  updateHealthScore();
  setTimeout(applyFilter,20);
}

function mkGrid(){const g=document.createElement('div');g.className='card-grid';g.style.setProperty('--cols',cols);return g;}

function mkCard(group){
  const card=document.createElement('div');
  card.className='gcard';
  card.dataset.name=group.name.toLowerCase();
  card.dataset.srv=(group.serverName||'').toLowerCase();
  card.dataset.users=group.cookies.map(c=>c.username||'').join(' ').toLowerCase();
  card.dataset.id=group.id;
  card.dataset.pinned=group.pinned?'1':'0';
  card.dataset.banned=group.banned?'1':'0';
  card.dataset.alts=(group.alternatives&&group.alternatives.length)?'1':'0';
  card.dataset.empty=(!group.cookies||group.cookies.length===0)?'1':'0';
  card.dataset.pinned=group.pinned?'1':'0';
  card.dataset.banned=group.banned?'1':'0';
  card.dataset.alts=(group.alternatives&&group.alternatives.length)?'1':'0';
  card.dataset.empty=(!group.cookies||group.cookies.length===0)?'1':'0';
  const col=getColor(group.serverName);
  card.style.setProperty('--cc',col.c);card.style.setProperty('--cr',col.r);
  const bar=document.createElement('div');bar.className='gcard-bar';bar.style.background=col.c;card.appendChild(bar);
  const body=document.createElement('div');body.className='gcard-body';
  // Row 1: dot + name + count + server + alts + rename btn (list view only)
  const row1=document.createElement('div');row1.className='gcard-row1';
  row1.innerHTML=`
    <div class="gcard-dot" style="background:${col.c};color:${col.c};width:8px;height:8px"></div>
    <div class="gcard-name">${esc(group.name)}</div>
    <div class="gcard-count">${flavorCount(group.cookies.length)}</div>
    ${getCardStatusHTML(group)}
    ${group.serverName?`<div class="gcard-srv">${esc(group.serverName)}</div>`:''}
    ${(group.alternatives&&group.alternatives.length)?`<div class="gcard-alt-badge">⟁ ${group.alternatives.length} alt${group.alternatives.length!==1?'s':''}</div>`:''}`;
  // Inline rename button (list view only)
  const renameInlineBtn=document.createElement('button');
  renameInlineBtn.className='gcard-rename-btn';renameInlineBtn.title='Rename';
  renameInlineBtn.innerHTML='<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>';
  renameInlineBtn.addEventListener('click',e=>{
    e.stopPropagation();
    const nameEl=row1.querySelector('.gcard-name');
    const inp=document.createElement('input');
    inp.style.cssText='background:rgba(0,0,0,.6);border:1px solid var(--a2);border-radius:4px;padding:2px 6px;font-family:var(--sans);font-weight:700;font-size:12px;color:var(--bright);outline:none;max-width:160px;';
    inp.value=group.name;inp.maxLength=40;
    nameEl.replaceWith(inp);inp.focus();inp.select();
    function commitRename(){
      const newName=inp.value.trim();
      if(newName&&newName!==group.name){
        group.name=newName;logChange(group,`Renamed to <span>${esc(newName)}</span>`);
        saveVault();render();toast(`Renamed to "${newName}"`,'ok');
      }else{inp.replaceWith(nameEl);}
    }
    inp.addEventListener('blur',commitRename);
    inp.addEventListener('keydown',e2=>{
      if(e2.key==='Enter'){e2.preventDefault();inp.blur();}
      if(e2.key==='Escape'){inp.replaceWith(nameEl);}
    });
  });
  row1.appendChild(renameInlineBtn);
  body.appendChild(row1);
  // Row 2: username pills (list view only)
  const usersRow=document.createElement('div');usersRow.className='gcard-users-row';
  if(group.cookies&&group.cookies.length){
    const MAX_PILLS=5;
    const shown=group.cookies.slice(0,MAX_PILLS);
    const extra=group.cookies.length-MAX_PILLS;
    shown.forEach(c=>{
      if(!c.username)return;
      const pill=document.createElement('span');pill.className='gcard-user-pill'+(c.banStatus==='banned'?' banned-user':'');
      pill.textContent=c.username;
      usersRow.appendChild(pill);
    });
    if(extra>0){const more=document.createElement('span');more.className='gcard-user-pill more';more.textContent='+'+extra;usersRow.appendChild(more);}
  }
  body.appendChild(usersRow);
  if(group.pinned){const pin=document.createElement('div');pin.className='gcard-pin';pin.textContent='📌';card.appendChild(pin);}
  if(group.banned){
    card.classList.add('banned');
    const banTag=document.createElement('div');banTag.className='gcard-banned-tag';banTag.textContent='Banned';
    card.appendChild(banTag);
  }
  card.appendChild(body);
  const qcBtn=document.createElement('button');qcBtn.className='card-qc-btn';qcBtn.textContent='copy';qcBtn.title='Quick copy';
  const chkDiv=document.createElement('div');chkDiv.className='gcard-chk';
  chkDiv.addEventListener('click',e=>{e.stopPropagation();toggleBulkSelect(group.id);});
  card.appendChild(chkDiv);
  qcBtn.addEventListener('click',e=>{e.stopPropagation();openQC(group.id,qcBtn);});
  card.appendChild(qcBtn);
  // Long-press → bulk select
  let lpTimer=null;
  card.addEventListener('touchstart',e=>{
    if(e.target===qcBtn||qcBtn.contains(e.target)||chkDiv.contains(e.target))return;
    lpTimer=setTimeout(()=>{
      lpTimer=null;
      navigator.vibrate&&navigator.vibrate(40);
      toggleBulkSelect(group.id);
    },500);
  },{passive:true});
  card.addEventListener('touchend',()=>{if(lpTimer){clearTimeout(lpTimer);lpTimer=null;}});
  card.addEventListener('touchmove',()=>{if(lpTimer){clearTimeout(lpTimer);lpTimer=null;}});
  // Double-tap → quick rename
  let tapTimer=null,tapCount=0;
  card.addEventListener('click',e=>{
    if(e.target===qcBtn||qcBtn.contains(e.target)||chkDiv.contains(e.target))return;
    tapCount++;
    if(tapCount===1){
      tapTimer=setTimeout(()=>{tapCount=0;openPanel(group.id);},280);}
    else if(tapCount===2){
      clearTimeout(tapTimer);tapCount=0;
      // Quick rename inline on card name
      const nameEl=card.querySelector('.gcard-name');
      if(!nameEl)return;
      const inp=document.createElement('input');
      inp.style.cssText='background:rgba(0,0,0,.6);border:1px solid var(--a2);border-radius:4px;padding:2px 6px;font-family:var(--sans);font-weight:700;font-size:inherit;color:var(--bright);outline:none;width:100%;';
      inp.value=group.name;inp.maxLength=40;
      nameEl.replaceWith(inp);inp.focus();inp.select();
      function commitRename(){
        const newName=inp.value.trim();
        if(newName&&newName!==group.name){
          group.name=newName;
          logChange(group,`Renamed to <span>${esc(newName)}</span>`);
          saveVault();render();toast(`Renamed to "${newName}"`,'ok');
        }else{inp.replaceWith(nameEl);}
      }
      inp.addEventListener('blur',commitRename);
      inp.addEventListener('keydown',e2=>{
        if(e2.key==='Enter'){e2.preventDefault();inp.blur();}
        if(e2.key==='Escape'){inp.replaceWith(nameEl);}
      });
      e.stopPropagation();
    }
  });
  return card;
}

function flavorCount(n){
  if(n===0)return'Empty';if(n===1)return'1 Cookie';
  return`${n} Cookies`;
}
function getCardStatusHTML(group){
  const cs=group.cookies;
  if(!cs||!cs.length)return'';
  const banned=cs.filter(c=>c.banStatus==='banned').length;
  const expired=cs.filter(c=>c.banStatus==='expired').length;
  const facelock=cs.filter(c=>c.banStatus==='facelock').length;
  const active=cs.filter(c=>c.banStatus==='active').length;
  const unchecked=cs.filter(c=>!c.banStatus).length;
  // If all unchecked and nothing flagged
  if(!banned&&!expired&&!facelock&&!active)return'';
  if(!banned&&!expired&&!facelock){
    return`<div class="gcard-status"><span class="s-ok">${active} Active</span></div>`;
  }
  const parts=[];
  if(banned)parts.push(`<span class="s-ban">${banned} Banned</span>`);
  if(expired)parts.push(`<span class="s-exp">${expired} Expired</span>`);
  if(facelock)parts.push(`<span class="s-face">${facelock} Locked</span>`);
  if(unchecked)parts.push(`<span>${unchecked} Unchecked</span>`);
  return`<div class="gcard-status">${parts.join(' | ')}</div>`;
}

// ═══════════════════════════════════════
// DETAIL PANEL
// ═══════════════════════════════════════
function openPanel(id){panelId=id;refreshPanel();document.getElementById('p-edit-form').classList.remove('open');document.getElementById('p-padd-form').classList.remove('open');document.getElementById('p-ov').classList.add('open');}
function closePanel(){document.getElementById('p-ov').classList.remove('open');}

function refreshPanel(){
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const col=getColor(g.serverName);
  document.getElementById('p-dot').style.cssText=`background:${col.c};box-shadow:0 0 8px ${col.c}`;
  document.getElementById('p-name').textContent=g.name;
  document.getElementById('p-cnt').textContent=g.cookies.length+' cookie'+(g.cookies.length!==1?'s':'');
  const srv=document.getElementById('p-srv');
  if(g.serverName){srv.textContent=g.serverName;srv.style.display='';}else srv.style.display='none';
  // Banned badge in panel header
  const existBanned=document.getElementById('p-banned-badge');if(existBanned)existBanned.remove();
  if(g.banned){
    const bb=document.createElement('div');bb.className='p-banned-badge';bb.id='p-banned-badge';bb.textContent='🚫 BANNED';
    document.querySelector('.p-badges').appendChild(bb);
  }
  document.getElementById('p-ban-btn').classList.toggle('ban-on',!!g.banned);
  document.getElementById('p-ban-btn').textContent=g.banned?'Unban':'Ban';
  document.getElementById('p-pin-btn').classList.toggle('pin-on',g.pinned);
  // Metadata fields
  const acctVal=document.getElementById('p-acct-id-val');
  const psVal=document.getElementById('p-pslink-val');
  const psCopy=document.getElementById('p-pslink-copy');
  if(acctVal){acctVal.textContent=g.accountId||'Not set';acctVal.classList.toggle('empty',!g.accountId);}
  if(psVal){psVal.textContent=g.privateServer||'Not set';psVal.classList.toggle('empty',!g.privateServer);}
  if(psCopy){psCopy.style.display=g.privateServer?'':'none';}
  const pc=g.pc||1;
  document.getElementById('p-grid').style.setProperty('--pc',pc);
  document.querySelectorAll('.p-cpill').forEach(p=>p.classList.toggle('on',parseInt(p.dataset.pc)===pc));
  const grid=document.getElementById('p-grid');
  grid.innerHTML='';
  g.cookies.forEach((c,i)=>grid.appendChild(mkCkItem(c,i,g.id)));
  // Render alternatives section
  const pscroll=document.getElementById('p-scroll');
  const oldAlt=pscroll.querySelector('.alt-section');if(oldAlt)oldAlt.remove();
  pscroll.insertBefore(buildAltSection(g),pscroll.querySelector('.ck-changelog')||null);
  refreshChangelog(g);
}

function refreshChangelog(g){
  const pscroll=document.getElementById('p-scroll');
  const old=pscroll.querySelector('.ck-changelog');if(old)old.remove();
  if(!g.changelog||!g.changelog.length)return;
  const clog=document.createElement('div');clog.className='ck-changelog';
  clog.innerHTML='<div class="ck-clog-title">Group changelog</div>'+
    g.changelog.map(e=>`<div class="ck-clog-entry"><div class="ck-clog-time">${fmtTime(e.t)}</div><div class="ck-clog-msg">${e.msg}</div></div>`).join('');
  pscroll.appendChild(clog);
}

// ═══════════════════════════════════════
// ALTERNATIVES SECTION
// ═══════════════════════════════════════
function buildAltSection(g){
  if(!g.alternatives)g.alternatives=[];
  const sec=document.createElement('div');sec.className='alt-section';

  // Header (collapsible)
  const head=document.createElement('div');head.className='alt-sec-head';
  const updateHeadState=()=>{
    head.classList.toggle('open',body.classList.contains('open'));
    chev.textContent=body.classList.contains('open')?'▴':'▾';
  };
  head.innerHTML=`<div class="alt-sec-title">⟁ Alternatives</div>
    <div class="alt-sec-count">${g.alternatives.length} set${g.alternatives.length!==1?'s':''}</div>
    <span class="alt-sec-chev">▾</span>`;
  const chev=head.querySelector('.alt-sec-chev');
  sec.appendChild(head);

  // Body
  const body=document.createElement('div');body.className='alt-sec-body';
  if(g.alternatives.length)body.classList.add('open');
  sec.appendChild(body);

  head.addEventListener('click',()=>{body.classList.toggle('open');updateHeadState();});

  function rebuildEntries(){
    body.innerHTML='';
    g.alternatives.forEach((alt,ai)=>{
      const entry=document.createElement('div');entry.className='alt-entry';
      entry.innerHTML=`<div class="alt-entry-head">
        <div class="alt-entry-label">${esc(alt.label||`Alt ${ai+1}`)}</div>
        <div class="alt-entry-count">${alt.cookies.length} cookie${alt.cookies.length!==1?'s':''}</div>
        <button class="alt-entry-del" title="Remove this alternative">✕</button>
      </div>`;
      entry.querySelector('.alt-entry-del').addEventListener('click',async()=>{
        const ok=await customConfirm(`Remove alternative "${alt.label||`Alt ${ai+1}`}"?`,'Remove');
        if(!ok)return;
        g.alternatives.splice(ai,1);saveVault();
        head.querySelector('.alt-sec-count').textContent=g.alternatives.length+' set'+(g.alternatives.length!==1?'s':'');
        rebuildEntries();
        // refresh card alt badge
        const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
        if(card){
          const ab=card.querySelector('.gcard-alt-badge');
          if(g.alternatives.length){if(ab)ab.textContent=`⟁ ${g.alternatives.length} alt${g.alternatives.length!==1?'s':''}`;else{const nb=document.createElement('div');nb.className='gcard-alt-badge';nb.textContent=`⟁ ${g.alternatives.length} alt${g.alternatives.length!==1?'s':''}`;card.querySelector('.gcard-body').appendChild(nb);}}
          else if(ab)ab.remove();
        }
      });
      const ckDiv=document.createElement('div');ckDiv.className='alt-entry-cookies';
      alt.cookies.forEach((c,ci)=>{
        const item=mkCkItem(c,ci,g.id,{altIdx:ai,isAlt:true});
        item.classList.add('alt-ck');
        ckDiv.appendChild(item);
      });
      entry.appendChild(ckDiv);
      body.appendChild(entry);
    });
    // Add alternative button + form
    const addBtn=document.createElement('button');addBtn.className='btn-add-alt';addBtn.textContent='+ add alternative set';
    body.appendChild(addBtn);

    const addForm=document.createElement('div');addForm.className='add-alt-form';
    addForm.innerHTML=`
      <div class="flbl">Alternative label</div>
      <input class="finput" placeholder="e.g. Backup, Region 2..." maxlength="40" style="font-size:12px;margin-bottom:8px;">
      <div class="flbl">Paste cookies</div>
      <textarea class="finput" rows="3" placeholder="username:password:cookie&#10;username:cookie&#10;cookie only" style="font-family:var(--mono);font-size:11px;resize:none;line-height:1.6;"></textarea>
      <div class="ck-edit-act" style="margin-top:8px">
        <button class="ck-cancel-btn">cancel</button>
        <button class="ck-save-btn">save alt</button>
      </div>`;
    body.appendChild(addForm);
    const labelIn=addForm.querySelector('input');
    const taIn=addForm.querySelector('textarea');
    addBtn.addEventListener('click',()=>{addForm.classList.toggle('open');if(addForm.classList.contains('open')){labelIn.focus();}});
    addForm.querySelector('.ck-cancel-btn').addEventListener('click',()=>addForm.classList.remove('open'));
    addForm.querySelector('.ck-save-btn').addEventListener('click',()=>{
      const label=labelIn.value.trim()||`Alt ${g.alternatives.length+1}`;
      const parsed=parseInput(taIn.value);
      if(!parsed.length){toast('No valid cookies','err');return;}
      const altObj={id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),label,cookies:parsed.map(c=>({...c}))};
      g.alternatives.push(altObj);
      logChange(g,`Added alternative: <span>${esc(label)}</span> (${parsed.length} cookie${parsed.length!==1?'s':''})`);
      saveVault();
      addForm.classList.remove('open');labelIn.value='';taIn.value='';
      head.querySelector('.alt-sec-count').textContent=g.alternatives.length+' set'+(g.alternatives.length!==1?'s':'');
      rebuildEntries();
      // refresh card alt badge
      const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
      if(card){
        let ab=card.querySelector('.gcard-alt-badge');
        if(ab)ab.textContent=`⟁ ${g.alternatives.length} alt${g.alternatives.length!==1?'s':''}`;
        else{const nb=document.createElement('div');nb.className='gcard-alt-badge';nb.textContent=`⟁ ${g.alternatives.length} alt${g.alternatives.length!==1?'s':''}`;card.querySelector('.gcard-body').appendChild(nb);}
      }
      toast(`Alternative "${label}" added (${parsed.length} cookies)`,'ok');
    });
  }
  rebuildEntries();
  updateHeadState();
  return sec;
}

function mkCkItem(c,i,gid,opts){
  opts=opts||{};
  const wrap=document.createElement('div');wrap.className='ck-item';

  // Header row with index, status tag, actions
  const hdr=document.createElement('div');hdr.className='ck-item-hdr';
  const idx=document.createElement('div');idx.className='ck-idx';idx.textContent=`#${i+1}`;hdr.appendChild(idx);
  // Status tag
  if(c.banStatus){
    const st=document.createElement('span');st.className='ck-status-tag';
    const statusMap={active:'ok',banned:'ban',expired:'exp',facelock:'face'};
    const labelMap={active:'Active',banned:'Banned',expired:'Expired',facelock:'Locked'};
    st.classList.add(statusMap[c.banStatus]||'ok');
    st.textContent=labelMap[c.banStatus]||c.banStatus;
    hdr.appendChild(st);
  }
  const actions=document.createElement('div');actions.className='ck-item-actions';
  // Copy button
  const copyBtn=document.createElement('button');copyBtn.className='ck-copy-btn';
  function getCopyFmt(){return c.username&&c.password?'u:p:c':c.username?'u:c':'cookie';}
  function getCopyLabel(f){return{'u:p:c':'Copy u:p:c','u:c':'Copy u:c','cookie':'Copy'}[f];}
  copyBtn.textContent=getCopyLabel(getCopyFmt());
  copyBtn.addEventListener('click',e=>{
    e.stopPropagation();
    const fmt=getCopyFmt();
    const text=fmtLine(c,fmt==='u:p:c'?'user:pass:cookie':fmt==='u:c'?'user:cookie':'cookie');
    const lbl=getCopyLabel(fmt);
    copyText(text,()=>{copyBtn.textContent='Copied!';setTimeout(()=>copyBtn.textContent=lbl,1400);},
      ()=>toast('Copy failed','err'));
  });
  actions.appendChild(copyBtn);
  // Edit button
  const editBtn=document.createElement('button');editBtn.className='ck-edit-btn';editBtn.textContent='Edit';
  editBtn.addEventListener('click',e=>{
    e.stopPropagation();
    wrap.classList.toggle('editing');
    editBtn.textContent=wrap.classList.contains('editing')?'Cancel':'Edit';
    if(wrap.classList.contains('editing')){
      wrap.querySelector('.ck-edit-in[data-field="username"]').value=c.username||'';
      wrap.querySelector('.ck-edit-in[data-field="password"]').value=c.password||'';
      wrap.querySelector('.ck-edit-in[data-field="cookie"]').value=c.cookie||'';
    }
  });
  actions.appendChild(editBtn);
  // Delete button (single cookie removal)
  if(!opts.isAlt){
    const delBtn=document.createElement('button');delBtn.className='ck-del-btn';delBtn.textContent='Del';
    delBtn.addEventListener('click',e=>{
      e.stopPropagation();
      const g=vault.find(x=>x.id===gid);if(!g)return;
      const removed=g.cookies.splice(i,1)[0];
      logChange(g,`Removed cookie #${i+1}${c.username?' ('+c.username+')':''}`);
      saveVault();refreshPanel();
      const card=document.querySelector(`.gcard[data-id="${gid}"]`);
      if(card){const ce=card.querySelector('.gcard-count');if(ce)ce.textContent=flavorCount(g.cookies.length);}
      const toastEl=document.getElementById('toast');
      document.getElementById('toast-msg').textContent='Cookie removed'+(c.username?' ('+c.username+')':'');
      toastEl.className='show warn';
      const oldU=toastEl.querySelector('.toast-undo');if(oldU)oldU.remove();
      const undoB=document.createElement('button');undoB.className='toast-undo';undoB.textContent='undo';
      undoB.addEventListener('click',()=>{
        g.cookies.splice(i,0,removed);saveVault();refreshPanel();
        toastEl.className='';toastEl.innerHTML='<span id="toast-msg"></span>';
      });
      toastEl.appendChild(undoB);
      clearTimeout(window._delUndoT);
      window._delUndoT=setTimeout(()=>{toastEl.className='';toastEl.innerHTML='<span id="toast-msg"></span>';},5000);
    });
    actions.appendChild(delBtn);
  }
  if(!opts.isAlt){
    // Swap button
    const swapBtn=document.createElement('button');swapBtn.className='ck-edit-btn';swapBtn.textContent='Swap';
    swapBtn.style.cssText='border-color:rgba(255,170,0,.3);color:rgba(255,170,0,.8);';
    swapBtn.addEventListener('click',e=>{e.stopPropagation();openSwapModal(gid,i);});
    actions.appendChild(swapBtn);
    // Move button
    const moveBtn=document.createElement('button');moveBtn.className='ck-edit-btn';moveBtn.textContent='Move';
    moveBtn.addEventListener('click',e=>{e.stopPropagation();openMoveCookieModal(gid,i);});
    actions.appendChild(moveBtn);
  }
  hdr.appendChild(actions);wrap.appendChild(hdr);

  // Format copy row — tap to copy in different formats
  const fmtRow=document.createElement('div');fmtRow.className='ck-fmt-row';
  const fmtDefs=[
    {label:'u:p:c',fmt:'user:pass:cookie'},
    {label:'u:c',fmt:'user:cookie'},
    {label:'u:p',fmt:'user:pass'},
    {label:'u',fmt:'username'},
    {label:'p',fmt:'user:pass'},
    {label:'c',fmt:'cookie'},
  ];
  fmtDefs.forEach(({label,fmt})=>{
    const fb=document.createElement('button');fb.className='ck-fmt-btn';fb.textContent=label;
    fb.addEventListener('click',e=>{
      e.stopPropagation();
      const text=fmtLine(c,fmt);
      if(!text){toast('No data for this format','warn');return;}
      copyText(text,()=>{fb.textContent='✓';setTimeout(()=>fb.textContent=label,1200);},
        ()=>toast('Copy failed','err'));
    });
    fmtRow.appendChild(fb);
  });
  wrap.appendChild(fmtRow);

  // Terminal lines: username, password, cookie
  if(c.username){
    const ln=document.createElement('div');ln.className='ck-line';
    ln.innerHTML=`<span class="ck-line-key">USER</span><span class="ck-line-val">${esc(c.username)}</span>`;
    wrap.appendChild(ln);
  }
  if(c.password){
    const ln=document.createElement('div');ln.className='ck-line';
    ln.innerHTML=`<span class="ck-line-key">PASS</span><span class="ck-line-val">${esc(c.password)}</span>`;
    wrap.appendChild(ln);
  }
  const cookieLn=document.createElement('div');cookieLn.className='ck-line';
  const cookieVal=document.createElement('span');cookieVal.className='ck-line-val cookie-val';
  cookieVal.textContent=c.cookie;
  cookieLn.innerHTML=`<span class="ck-line-key">COOKIE</span>`;
  cookieLn.appendChild(cookieVal);
  wrap.appendChild(cookieLn);

  // Edit form (hidden by default)
  const form=document.createElement('div');form.className='ck-edit-form';
  form.innerHTML=`
    <div class="ck-edit-lbl">Username</div>
    <input class="ck-edit-in" data-field="username" placeholder="leave blank if none">
    <div class="ck-edit-lbl">Password</div>
    <input class="ck-edit-in" data-field="password" placeholder="leave blank if none">
    <div class="ck-edit-lbl">Cookie</div>
    <textarea class="ck-edit-in cookie-in" data-field="cookie" placeholder="paste cookie here"></textarea>
    <div class="ck-edit-act">
      <button class="ck-cancel-btn">Cancel</button>
      <button class="ck-save-btn">Save</button>
    </div>`;
  form.querySelector('.ck-cancel-btn').addEventListener('click',e=>{
    e.stopPropagation();
    wrap.classList.remove('editing');editBtn.textContent='Edit';
  });
  form.querySelector('.ck-save-btn').addEventListener('click',e=>{
    e.stopPropagation();
    const newUsername=form.querySelector('[data-field="username"]').value.trim()||null;
    const newPassword=form.querySelector('[data-field="password"]').value.trim()||null;
    const newCookie=form.querySelector('[data-field="cookie"]').value.trim();
    if(!newCookie){toast('Cookie cannot be empty','err');return;}
    const g=vault.find(x=>x.id===gid);if(!g)return;
    const targetArr=opts.isAlt&&g.alternatives&&g.alternatives[opts.altIdx]
      ?g.alternatives[opts.altIdx].cookies:g.cookies;
    if(!targetArr||!targetArr[i])return;
    const changes=[];
    const prefix=opts.isAlt?`Alt cookie #${i+1}`:`Cookie #${i+1}`;
    if((c.username||'')!==(newUsername||''))changes.push(`${prefix} username updated`);
    if((c.password||'')!==(newPassword||''))changes.push(`${prefix} password updated`);
    if(c.cookie!==newCookie)changes.push(`${prefix} cookie updated`);
    targetArr[i].username=newUsername;targetArr[i].password=newPassword;targetArr[i].cookie=newCookie;
    if(changes.length)logChange(g,changes.join(', '));
    const newFmt=newUsername&&newPassword?'u:p:c':newUsername?'u:c':'cookie';
    copyBtn.textContent=getCopyLabel(newFmt);
    saveVault();
    wrap.classList.remove('editing');editBtn.textContent='Edit';
    // update displayed values
    const uLn=wrap.querySelector('.ck-line .ck-line-val');
    if(uLn&&c.username)uLn.textContent=newUsername||'';
    cookieVal.textContent=newCookie;
    refreshChangelog(g);
    toast(`${prefix} updated`,'ok');
  });
  wrap.appendChild(form);
  return wrap;
}

function saveEdit(){
  const name=document.getElementById('p-en').value.trim();if(!name){document.getElementById('p-en').focus();return;}
  const serverName=document.getElementById('p-es').value.trim()||null;
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const changes=[];
  if(g.name!==name)changes.push(`Renamed to <span>${esc(name)}</span>`);
  if((g.serverName||'')!==(serverName||''))changes.push(`Server changed to <span>${esc(serverName||'none')}</span>`);
  const srvChanged=(g.serverName||'')!==(serverName||'');
  g.name=name;g.serverName=serverName;
  if(changes.length)logChange(g,changes.join(', '));
  saveVault();
  if(srvChanged){render();}else{
    const card=document.querySelector(`.gcard[data-id="${g.id}"]`);
    if(card){const nameEl=card.querySelector('.gcard-name');if(nameEl)nameEl.textContent=g.name;card.dataset.name=g.name.toLowerCase();}
    buildSidebar();
  }
  refreshPanel();
  document.getElementById('p-edit-form').classList.remove('open');
  toast('Group updated','ok');
}

// ═══════════════════════════════════════
// QUICK COPY
// ═══════════════════════════════════════
function openQC(groupId,anchor){
  qcGroupId=groupId;
  const popup=document.getElementById('qc-popup');
  popup.style.display='block';document.getElementById('qc-backdrop').style.display='block';
  const rect=anchor.getBoundingClientRect();
  let left=rect.left,top=rect.bottom+6;
  if(left+200>window.innerWidth-8)left=window.innerWidth-208;
  if(top+180>window.innerHeight-8)top=rect.top-186;
  popup.style.left=left+'px';popup.style.top=top+'px';
}
function closeQC(){document.getElementById('qc-popup').style.display='none';document.getElementById('qc-backdrop').style.display='none';}

// ═══════════════════════════════════════
// BULK EXPORT
// ═══════════════════════════════════════
function openBulk(label,groups){
  bulkLabel=label;bulkGroups=groups;
  const t=groups.reduce((s,g)=>s+g.cookies.length,0);
  document.getElementById('bk-title').textContent='Export · '+label;
  document.getElementById('bk-meta').textContent=groups.length+' groups · '+t+' cookies';
  openMod('bulk-modal');
}

// ═══════════════════════════════════════
// VAULT STATS
// ═══════════════════════════════════════
function showStats(){
  const totalG=vault.length;
  const totalC=vault.reduce((s,g)=>s+g.cookies.length,0);
  const srvs=new Set(vault.filter(g=>g.serverName).map(g=>g.serverName.trim().toLowerCase())).size;
  const biggest=vault.reduce((m,g)=>g.cookies.length>m.n?{n:g.cookies.length,name:g.name}:m,{n:0,name:'none'});
  const days=Math.floor((Date.now()-settings.firstCreated)/86400000);
  const streak=settings.streak||0;
  document.getElementById('stats-grid').innerHTML=`
    <div class="stat-card"><div class="sv">${totalG}</div><div class="sl">Groups</div></div>
    <div class="stat-card"><div class="sv">${totalC}</div><div class="sl">Cookies</div></div>
    <div class="stat-card"><div class="sv">${srvs}</div><div class="sl">Servers</div></div>
    <div class="stat-card"><div class="sv">${streak}</div><div class="sl">Day Streak</div></div>`;
  document.getElementById('stats-fun').innerHTML=`
    vault is <span>${days}</span> day${days!==1?'s':''} old &nbsp;·&nbsp;
    biggest group: <span>${esc(biggest.name)}</span> (${biggest.n} cookies)<br>
    you have <span>${totalC}</span> cookie${totalC!==1?'s':''} total`;
  openMod('stats-modal');
}

// ═══════════════════════════════════════
// STATS ANIMATION
// ═══════════════════════════════════════
function animStats(g,c,s){aNum('sv-g',g);aNum('sv-c',c);aNum('sv-s',s);}
function aNum(id,target){
  const el=document.getElementById(id);
  const start=parseInt(el.textContent)||0;if(start===target)return;
  const dur=500,t0=Date.now();
  (function step(){const p=Math.min(1,(Date.now()-t0)/dur),e=1-Math.pow(1-p,3);
    el.textContent=Math.round(start+(target-start)*e);if(p<1)requestAnimationFrame(step);})();
}

// ═══════════════════════════════════════
// DELETE + UNDO
// ═══════════════════════════════════════
function delGroup(id){
  const g=vault.find(x=>x.id===id);if(!g)return;
  const card=document.querySelector(`.gcard[data-id="${id}"]`);
  if(card){
    card.classList.add('deleting');
    setTimeout(()=>{lastDeleted={group:g,index:vault.findIndex(x=>x.id===id)};vault=vault.filter(x=>x.id!==id);saveVault();render();},350);
  }else{lastDeleted={group:g,index:vault.findIndex(x=>x.id===id)};vault=vault.filter(x=>x.id!==id);saveVault();render();}
  clearTimeout(undoTimer);
  const toastEl=document.getElementById('toast');
  document.getElementById('toast-msg').textContent='Group removed';
  toastEl.className='show warn';
  const old=toastEl.querySelector('.toast-undo');if(old)old.remove();
  const undoBtn=document.createElement('button');undoBtn.className='toast-undo';undoBtn.textContent='undo';
  undoBtn.addEventListener('click',()=>{
    if(lastDeleted){vault.splice(lastDeleted.index,0,lastDeleted.group);saveVault();render();lastDeleted=null;}
    clearTimeout(undoTimer);toastEl.className='';toastEl.innerHTML='<span id="toast-msg"></span>';
  });
  toastEl.appendChild(undoBtn);
  undoTimer=setTimeout(()=>{toastEl.className='';toastEl.innerHTML='<span id="toast-msg"></span>';lastDeleted=null;},5000);
}

// ═══════════════════════════════════════
// CHANGELOG
// ═══════════════════════════════════════
const APP_CHANGELOG=[
  {version:'v5.1',date:'Mar 2026',latest:true,entries:[
    {type:'change',desc:'Header toolbar — no borders, plain text + icons, dim by default, cyan underline on active, Stats/Log capitalized'},
    {type:'change',desc:'Filter bar — full tab strip with SVG icons (All/Pinned/Banned/Has Alts/Empty), no pills, no emoji'},
    {type:'change',desc:'Search — bigger, wider, clear ✕ button appears when typing'},
    {type:'add',desc:'List View — toggle button in header, compact 44px single-row per group showing dot → name → count → server → badges. Persists across reloads'},
    {type:'add',desc:'Bulk Select — hover a card to see checkbox, select multiple, bulk action bar slides up from bottom: Export / Copy All / Ban All / Delete All'},
    {type:'change',desc:'Export Popup — clicking export shows format choices: u:p:c / u:c / cookie only / username only / vault.json. Works from dock button and bulk select'},
    {type:'add',desc:'Auto Sort on Add — new groups insert into A-Z position immediately, no refresh needed'},
    {type:'add',desc:'Search Lift — matching groups float to top of their section, restore to original order on clear'},
    {type:'add',desc:'Cookie Sort in Panel — sort bar above cookies: Default / A-Z / Username / Banned first'},
    {type:'change',desc:'Stats — per-server breakdown (groups · cookies · banned count) inside stats modal'},
    {type:'change',desc:'Health Score — click the badge to see a toast breakdown (backup age, ban ratio, empty groups, streak, sync)'},
    {type:'add',desc:'Last Checked — timestamp shows on cards after ban check runs'},
  ]},
  {version:'v4.8',date:'Mar 2026',latest:false,entries:[
    {type:'change',desc:'Command dock redesigned — bigger buttons, Title Case font, 2×2 grid'},
    {type:'change',desc:'Export split into .txt (all u:p:c) and .json (full vault) via popup'},
    {type:'change',desc:'Copy now copies all cookies in u:p:c format to clipboard'},
    {type:'change',desc:'Import unified (.json or .txt) with review popup'},
    {type:'change',desc:'Purge renamed to Forget Everything with confirmation'},
    {type:'add',desc:'Sync Vault moved to header button'},
    {type:'add',desc:'Ban Checker moved to inline section below paste'},
    {type:'add',desc:'Paste section terminal-style UI'},
    {type:'add',desc:'Create Empty Group button in paste section'},
    {type:'add',desc:'Per-cookie delete button in detail panel'},
    {type:'change',desc:'Cookie items redesigned as terminal lines (no blur)'},
    {type:'add',desc:'Account ID + Private Server Link per group (with copy)'},
    {type:'add',desc:'Per-group ban check button in detail panel'},
    {type:'add',desc:'Switch Data feature — multiple named vault configs in header'},
    {type:'add',desc:'Card status line shows Banned/Expired/Locked/Active count'},
    {type:'fix',desc:'Ban check auto-updates cookie status to Active when valid'},
  ]},
  {version:'v4.7',date:'Mar 2026',latest:false,entries:[
    {type:'add',desc:'PIN lock screen — 6-digit keypad with configurable decoy PIN and glitch animation on wrong entry'},
    {type:'add',desc:'Ban checker terminal — Cloudflare Worker round-robin, active/banned/expired/facelock, export failed u:p:c'},
    {type:'add',desc:'GitHub Gist auto-sync — debounced 3s, sync dot indicator, offline queue'},
    {type:'add',desc:'Filter bar — All/Pinned/Banned/Has Alts/Empty pills + vault health score badge'},
  ]},
  {version:'v4.6',date:'Mar 2026',latest:false,entries:[
    {type:'fix',desc:'6 bugs fixed: alt cookie edit routing, alt ID collision, dead code, quota error surfacing, tilt/entrance conflict, stale copy format'},
  ]},
  {version:'v4.5',date:'Mar 2026',latest:false,entries:[
    {type:'add',desc:'Ban tag — mark groups as banned with a 🚫 badge on the card'},
    {type:'add',desc:'Alternatives system — add named alternative cookie sets per card with their own UPC data'},
    {type:'add',desc:'Alt badge on cards when alternatives exist (⟁ N alts)'},
  ]},
  {version:'v4.0',date:'Mar 2026',latest:false,entries:[
    {type:'remove',desc:'PIN lock screen removed'},
    {type:'remove',desc:'Copy user / copy cookie / tag buttons removed from cookie items'},
    {type:'add',desc:'Single smart copy button per cookie (u:p:c, u:c, or cookie only)'},
    {type:'add',desc:'Inline edit mode per cookie — edit username, password, cookie'},
    {type:'add',desc:'Sync Vault — upload new vault.json and smart-merge with replace options'},
    {type:'add',desc:'Stats and Changelog moved to header buttons'},
    {type:'change',desc:'Sidebar footer redesigned as icon command dock'},
  ]},
  {version:'v3.1',date:'Mar 2026',latest:false,entries:[
    {type:'fix',desc:'28 bugs fixed including streak, clipboard corruption, sidebar state, sort, mobile backdrop'},
    {type:'fix',desc:'Custom confirm dialogs replace browser confirm()'},
    {type:'fix',desc:'PIN stored as hash, not plaintext'},
    {type:'remove',desc:'Dead code: Matrix, Warp, Birthday, Constellation stubs removed'},
  ]},
];
function buildChangelogModal(){
  document.getElementById('cl-scroll').innerHTML=APP_CHANGELOG.map(v=>`
    <div class="cl-version">
      <div class="cl-ver-head">
        <div class="cl-ver-num">${v.version}</div><div class="cl-ver-date">${v.date}</div>
        ${v.latest?'<div class="cl-ver-latest">current</div>':''}
      </div>
      ${v.entries.map(e=>`<div class="cl-entry"><div class="cl-type ${e.type}">${e.type}</div><div class="cl-desc">${esc(e.desc)}</div></div>`).join('')}
    </div>`).join('');
}

// ═══════════════════════════════════════
// UTILS
// ═══════════════════════════════════════
function parseLine(line){
  line=line.trim();if(!line)return null;
  const i=line.indexOf(COOKIE_PFX);if(i===-1)return null;
  const cookie=line.substring(i),pre=line.substring(0,i).replace(/:$/,'');
  if(!pre)return{username:null,password:null,cookie};
  const ci=pre.indexOf(':');
  if(ci===-1)return{username:pre,password:null,cookie};
  return{username:pre.substring(0,ci),password:pre.substring(ci+1),cookie};
}
function parseInput(txt){return txt.split('\n').map(parseLine).filter(Boolean);}
function fmtLine(c,fmt){
  if(fmt==='username')return c.username||'';
  if(fmt==='cookie')return c.cookie;
  if(fmt==='user:cookie')return c.username?`${c.username}:${c.cookie}`:c.cookie;
  if(fmt==='user:pass')return(c.username&&c.password)?`${c.username}:${c.password}`:(c.username||'');
  if(fmt==='user:pass:cookie'){
    if(c.username&&c.password)return`${c.username}:${c.password}:${c.cookie}`;
    if(c.username)return`${c.username}:${c.cookie}`;
    return c.cookie;
  }
  return'';
}
function expTxt(g){
  const lines=g.cookies.map(c=>fmtLine(c,'user:pass:cookie'));
  dl(lines.join('\n'),sf(g.name)+'.txt');toast(`Exported ${g.name}.txt`,'ok');
}
function fmtTime(ts){
  const d=new Date(ts),diff=Math.floor((Date.now()-ts)/1000);
  if(diff<60)return'just now';if(diff<3600)return Math.floor(diff/60)+'m ago';
  if(diff<86400)return Math.floor(diff/3600)+'h ago';
  const days=Math.floor(diff/86400);if(days<7)return days+'d ago';
  return d.toLocaleDateString('en',{month:'short',day:'numeric'});
}
function logChange(group,msg){
  if(!group.changelog)group.changelog=[];
  group.changelog.unshift({t:Date.now(),msg});
  if(group.changelog.length>30)group.changelog.pop();
}
function copyText(text,onSuccess,onFail){
  if(navigator.clipboard&&window.isSecureContext){
    navigator.clipboard.writeText(text).then(onSuccess).catch(()=>fallbackCopy(text,onSuccess,onFail));
  }else fallbackCopy(text,onSuccess,onFail);
}
function fallbackCopy(text,onSuccess,onFail){
  const ta=document.createElement('textarea');
  ta.value=text;ta.style.cssText='position:fixed;left:-9999px;top:-9999px;opacity:0';
  document.body.appendChild(ta);ta.focus();ta.select();
  try{const ok=document.execCommand('copy');document.body.removeChild(ta);if(ok)onSuccess();else(onFail||onSuccess)();}
  catch(e){document.body.removeChild(ta);(onFail||onSuccess)();}
}
function esc(s){if(!s)return'';return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function sf(n){return(n||'group').replace(/[^a-z0-9_\-]/gi,'_').substring(0,50)||'group';}
function dl(content,filename){const a=document.createElement('a');a.href='data:text/plain;charset=utf-8,'+encodeURIComponent(content);a.download=filename;a.click();}
let toastT;
function toast(msg,type=''){
  const el=document.getElementById('toast');
  document.getElementById('toast-msg').textContent=msg;
  const old=el.querySelector('.toast-undo');if(old)old.remove();
  el.className='show '+(type||'');
  clearTimeout(toastT);toastT=setTimeout(()=>{el.className=type||'';},2800);
}

// ═══════════════════════════════════════
// PIN LOCK
// ═══════════════════════════════════════

function initPin(){
  const scr=document.getElementById('pin-screen');
  const vn=document.getElementById('pin-vault-name');
  const n=settings.vaultName||'Saturnity Vault';
  const parts=n.split(' ');
  vn.innerHTML=parts.length>=2?esc(parts[0])+' <span>'+esc(parts.slice(1).join(' '))+'</span>':'<span>'+esc(n)+'</span>';
  document.getElementById('pin-pad').addEventListener('click',e=>{
    const k=e.target.closest('.pin-key');if(!k)return;
    handlePinKey(k.dataset.v);
  });
  document.addEventListener('keydown',e=>{
    if(scr.classList.contains('hidden'))return;
    if(e.key>='0'&&e.key<='9')handlePinKey(e.key);
    else if(e.key==='Backspace')handlePinKey('del');
    else if(e.key==='Escape')handlePinKey('clear');
  });
  // Check lockout
  checkPinLock();
}

function checkPinLock(){
  const stored=parseInt(localStorage.getItem('cv_pin_lock_until')||'0');
  const fails=parseInt(localStorage.getItem('cv_pin_fails')||'0');
  pinFails=fails;
  if(stored>Date.now()){
    pinLocked=true;pinLockUntil=stored;
    showPinLockCountdown();
  }
}

function showPinLockCountdown(){
  const msgEl=document.getElementById('pin-lock-msg');
  const errEl=document.getElementById('pin-err');
  errEl.textContent='';
  function tick(){
    const rem=Math.ceil((pinLockUntil-Date.now())/1000);
    if(rem<=0){pinLocked=false;localStorage.removeItem('cv_pin_lock_until');msgEl.textContent='';return;}
    msgEl.textContent=`locked — try again in ${rem}s`;
    setTimeout(tick,500);
  }
  tick();
}

function handlePinKey(v){
  if(pinLocked)return;
  const scr=document.getElementById('pin-screen');
  if(v==='clear'){pinBuffer='';updatePinDots();return;}
  if(v==='del'){pinBuffer=pinBuffer.slice(0,-1);updatePinDots();return;}
  if(pinBuffer.length>=6)return;
  pinBuffer+=v;
  updatePinDots();
  if(pinBuffer.length===6)submitPin();
}

function updatePinDots(){
  document.querySelectorAll('.pin-dot').forEach((d,i)=>d.classList.toggle('filled',i<pinBuffer.length));
}

function submitPin(){
  const scr=document.getElementById('pin-screen');
  const errEl=document.getElementById('pin-err');
  const decoy=localStorage.getItem('cv_decoy_pin')||'';
  if(pinBuffer===REAL_PIN){
    // Correct — unlock
    decoyMode=false;
    pinFails=0;localStorage.removeItem('cv_pin_fails');localStorage.removeItem('cv_pin_lock_until');
    scr.classList.add('hidden');
    setTimeout(()=>{scr.style.display='none';},350);
    pinBuffer='';updatePinDots();
  } else if(decoy&&pinBuffer===decoy){
    // Decoy — show empty vault
    decoyMode=true;
    vault=[]; // wipe in-memory vault — saveVault() is a no-op in decoy mode
    pinFails=0;localStorage.removeItem('cv_pin_fails');
    scr.classList.add('hidden');
    setTimeout(()=>{scr.style.display='none';render();},350);
    pinBuffer='';updatePinDots();
  } else {
    // Wrong
    pinFails++;
    localStorage.setItem('cv_pin_fails',pinFails);
    pinBuffer='';updatePinDots();
    const lockoutSeconds=pinFails>=5?120:pinFails>=3?30:0;
    if(lockoutSeconds>0){
      pinLocked=true;
      pinLockUntil=Date.now()+lockoutSeconds*1000;
      localStorage.setItem('cv_pin_lock_until',pinLockUntil);
      showPinLockCountdown();
    }
    scr.classList.add('glitching','pin-shaking');
    errEl.textContent=`wrong PIN${pinFails>=3?' — '+pinFails+' attempts':''}`;
    setTimeout(()=>{scr.classList.remove('glitching','pin-shaking');},600);
  }
}

// Decoy guard — wrap saveVault
const _origSaveVault=saveVault;
// Override is handled inline: saveVault checks decoyMode at top

// ═══════════════════════════════════════
// GITHUB GIST SYNC
// ═══════════════════════════════════════

function getSyncDot(){return document.getElementById('sync-dot');}
function setSyncDot(state){const d=getSyncDot();if(d)d.dataset.state=state;}

function ghEnabled(){return localStorage.getItem(GH_EN_K)==='1'&&!!localStorage.getItem(GH_PAT_K)&&!!localStorage.getItem(GH_GIST_K);}

function scheduleGhSync(){
  if(!ghEnabled())return;
  setSyncDot('syncing');
  clearTimeout(ghDebounceTimer);
  ghDebounceTimer=setTimeout(doGhSync,3000);
}

async function doGhSync(){
  if(!ghEnabled()){setSyncDot('off');return;}
  if(!navigator.onLine){setSyncDot('queue');ghPendingSync=true;return;}
  setSyncDot('syncing');
  try{
    const pat=localStorage.getItem(GH_PAT_K);
    const gist=localStorage.getItem(GH_GIST_K);
    const body=JSON.stringify({files:{'saturnity-vault.json':{content:JSON.stringify({version:1,exported:Date.now(),vault},null,2)}}});
    const r=await fetch('https://api.github.com/gists/'+gist,{method:'PATCH',headers:{'Authorization':'token '+pat,'Content-Type':'application/json'},body});
    if(!r.ok)throw new Error('HTTP '+r.status);
    setSyncDot('ok');
    settings.lastGithubSync=Date.now();saveSettings();
    ghPendingSync=false;
  }catch(e){
    setSyncDot('err');
    ghPendingSync=true;
    toast('GitHub sync failed: '+e.message,'err');
  }
}

window.addEventListener('online',()=>{if(ghPendingSync)doGhSync();});

async function testGhConnection(){
  const pat=document.getElementById('vs-gh-pat').value.trim();
  const gist=document.getElementById('vs-gh-gist').value.trim();
  if(!pat||!gist){toast('Enter PAT and Gist ID first','warn');return;}
  try{
    const r=await fetch('https://api.github.com/gists/'+gist,{headers:{'Authorization':'token '+pat}});
    if(!r.ok)throw new Error('HTTP '+r.status);
    toast('GitHub connection OK ✓','ok');
  }catch(e){toast('Connection failed: '+e.message,'err');}
}

// ═══════════════════════════════════════
// VAULT SETTINGS
// ═══════════════════════════════════════
function openVaultSettings(){
  document.getElementById('vs-gh-pat').value=localStorage.getItem(GH_PAT_K)||'';
  document.getElementById('vs-gh-gist').value=localStorage.getItem(GH_GIST_K)||'';
  document.getElementById('vs-gh-enabled').checked=localStorage.getItem(GH_EN_K)==='1';
  document.getElementById('vs-decoy-pin').value=localStorage.getItem('cv_decoy_pin')||'';
  openMod('vault-settings-modal');
}
function saveVaultSettings(){
  const pat=document.getElementById('vs-gh-pat').value.trim();
  const gist=document.getElementById('vs-gh-gist').value.trim();
  const en=document.getElementById('vs-gh-enabled').checked;
  const decoy=document.getElementById('vs-decoy-pin').value.trim();
  if(pat)localStorage.setItem(GH_PAT_K,pat);else localStorage.removeItem(GH_PAT_K);
  if(gist)localStorage.setItem(GH_GIST_K,gist);else localStorage.removeItem(GH_GIST_K);
  localStorage.setItem(GH_EN_K,en?'1':'0');
  if(decoy&&!/^\d{4,8}$/.test(decoy)){toast('Decoy PIN must be 4–8 digits','err');return;}
  if(decoy===REAL_PIN){toast('Decoy PIN cannot match real PIN','err');return;}
  if(decoy)localStorage.setItem('cv_decoy_pin',decoy);else localStorage.removeItem('cv_decoy_pin');
  setSyncDot(ghEnabled()?'ok':'off');
  closeMod('vault-settings-modal');
  toast('Settings saved','ok');
}

document.getElementById('vs-cancel').addEventListener('click',()=>closeMod('vault-settings-modal'));
document.getElementById('vs-save').addEventListener('click',saveVaultSettings);
document.getElementById('vs-gh-test').addEventListener('click',testGhConnection);
document.getElementById('sb-vault-settings').addEventListener('click',openVaultSettings);
document.getElementById('sync-dot').addEventListener('click',openVaultSettings);
document.getElementById('pin-decoy-hint').addEventListener('click',()=>{
  document.getElementById('pin-screen').classList.add('hidden');
  setTimeout(()=>{document.getElementById('pin-screen').style.display='none';openVaultSettings();},300);
});

// ═══════════════════════════════════════
// FILTER BAR + HEALTH SCORE
// ═══════════════════════════════════════

document.querySelectorAll('.filter-pill').forEach(p=>{
  p.addEventListener('click',()=>{
    activeFilter=p.dataset.filter;
    document.querySelectorAll('.filter-pill').forEach(x=>x.classList.toggle('on',x.dataset.filter===activeFilter));
    applyFilter();
  });
});

function applyFilter(){
  const q=document.getElementById('search-in').value.trim().toLowerCase();
  document.querySelectorAll('.gcard').forEach(card=>{
    let hide=false;
    if(activeFilter==='pinned')hide=card.dataset.pinned!=='1';
    else if(activeFilter==='banned')hide=card.dataset.banned!=='1';
    else if(activeFilter==='alts')hide=card.dataset.alts!=='1';
    else if(activeFilter==='empty')hide=card.dataset.empty!=='1';
    // Also apply search
    if(!hide&&q){
      hide=!card.dataset.name.includes(q)&&!card.dataset.srv.includes(q)&&!(card.dataset.users||'').includes(q);
    }
    card.classList.toggle('dim',hide);
  });
}

function calcHealthScore(){
  if(!vault.length)return{score:0,grade:'F'};
  let score=100;
  // Backup recency (0–25 pts)
  const last=settings.lastBackup;
  const backupAge=last?Math.floor((Date.now()-last)/86400000):999;
  if(backupAge===999||backupAge>30)score-=25;
  else if(backupAge>7)score-=15;
  else if(backupAge>3)score-=8;
  else if(backupAge>1)score-=3;
  // Ban ratio (0–20 pts)
  const bannedCount=vault.filter(g=>g.banned).length;
  const banRatio=bannedCount/vault.length;
  score-=Math.round(banRatio*20);
  // Empty groups (0–20 pts)
  const emptyCount=vault.filter(g=>!g.cookies||g.cookies.length===0).length;
  score-=Math.round((emptyCount/vault.length)*20);
  // Streak bonus (0–15 pts)
  score+=Math.min(15,Math.floor((settings.streak||0)/2));
  // GitHub sync freshness (0–10 pts)
  if(ghEnabled()){
    const syncAge=settings.lastGithubSync?Math.floor((Date.now()-settings.lastGithubSync)/86400000):999;
    if(syncAge<=1)score+=10;else if(syncAge<=3)score+=5;
  }
  score=Math.max(0,Math.min(100,score));
  const grade=score>=90?'A':score>=75?'B':score>=60?'C':score>=45?'D':'F';
  return{score,grade};
}

function updateHealthScore(){
  const {score,grade}=calcHealthScore();
  const el=document.getElementById('health-score');
  const gel=document.getElementById('health-grade');
  if(el)el.textContent=score;
  if(gel){gel.textContent=grade;gel.className='health-grade '+grade;}
}

// health-badge click → toast breakdown (wired below in Feature 11)

// ═══════════════════════════════════════

// ═══════════════════════════════════════
// SORT / DISTRIBUTE PASTE
// ═══════════════════════════════════════
let sortPending=[];

function openSortModal(cookies){
  sortPending=cookies;
  document.getElementById('sort-count').textContent=cookies.length;
  document.getElementById('sort-modal-desc').innerHTML=`Split <span id="sort-count">${cookies.length}</span> cookies into groups automatically.`;
  document.getElementById('sort-server-pfx').value='';
  document.getElementById('sort-group-pfx').value='';
  document.getElementById('sort-cookies-per-grp').value='5';
  document.getElementById('sort-groups-per-srv').value='18';
  document.getElementById('sort-preview').classList.remove('show');
  document.getElementById('sort-preview').innerHTML='';
  openMod('sort-modal');
  document.getElementById('sort-server-pfx').focus();
}

function calcDistribution(){
  const srvPfx=document.getElementById('sort-server-pfx').value.trim();
  const grpPfx=document.getElementById('sort-group-pfx').value.trim();
  const cookiesPerGrp=Math.max(1,parseInt(document.getElementById('sort-cookies-per-grp').value)||5);
  const grpsPerSrv=Math.max(1,Math.min(18,parseInt(document.getElementById('sort-groups-per-srv').value)||18));
  const cookies=sortPending;

  // Find existing max group number for this prefix (to continue numbering)
  let startGrpNum=1;
  if(grpPfx){
    const pfxLow=grpPfx.toLowerCase();
    vault.forEach(g=>{
      const nLow=g.name.toLowerCase();
      if(nLow.startsWith(pfxLow)){
        const rest=g.name.slice(grpPfx.length).trim();
        const n=parseInt(rest);
        if(!isNaN(n)&&n>=startGrpNum)startGrpNum=n+1;
      }
    });
  }

  // Find existing max server number for this prefix
  let startSrvNum=1;
  if(srvPfx){
    const pfxLow=srvPfx.toLowerCase();
    vault.forEach(g=>{
      if(!g.serverName)return;
      const sLow=g.serverName.toLowerCase();
      if(sLow.startsWith(pfxLow)){
        const rest=g.serverName.slice(srvPfx.length).trim();
        const n=parseInt(rest);
        if(!isNaN(n)&&n>=startSrvNum)startSrvNum=n+1;
      }
    });
    // If exact match exists (single server, no number), keep using it
    const exactMatch=vault.find(g=>(g.serverName||'').toLowerCase()===srvPfx.toLowerCase());
    if(exactMatch)startSrvNum=1; // will reuse server name without number
  }

  // Chunk cookies into groups
  const groups=[];
  for(let i=0;i<cookies.length;i+=cookiesPerGrp){
    groups.push(cookies.slice(i,i+cookiesPerGrp));
  }

  const totalGroups=groups.length;
  const totalNum=startGrpNum+totalGroups-1;
  const padWidth=totalNum>=10?String(totalNum).length:0;
  function padNum(n){return padWidth>0?String(n).padStart(padWidth,'0'):String(n);}

  const result=[];
  let srvIdx=startSrvNum,grpInSrv=0;
  // Count existing groups in starting server to determine initial grpInSrv offset
  if(srvPfx){
    const firstSrvName=srvPfx+(startSrvNum>1?' '+startSrvNum:'');
    const existing=vault.filter(g=>(g.serverName||'').toLowerCase()===firstSrvName.toLowerCase()).length;
    grpInSrv=existing%grpsPerSrv;
    if(existing>=grpsPerSrv){srvIdx++;grpInSrv=0;}
  }

  groups.forEach((ckSlice,gi)=>{
    if(grpInSrv>=grpsPerSrv){srvIdx++;grpInSrv=0;}
    // Single server: use prefix alone (no number suffix) unless multiple servers needed
    const needsNumber=srvIdx>1;
    const srvName=srvPfx?(needsNumber?srvPfx+' '+srvIdx:srvPfx):null;
    const grpName=grpPfx?(grpPfx+' '+padNum(startGrpNum+gi)):('Group '+padNum(startGrpNum+gi));
    result.push({srvName,grpName,cookies:ckSlice});
    grpInSrv++;
  });
  return result;
}

document.getElementById('sort-preview-btn').addEventListener('click',()=>{
  const dist=calcDistribution();
  const prev=document.getElementById('sort-preview');
  prev.innerHTML='';
  // Group by server for clean preview
  const bySrv=new Map();
  dist.forEach(d=>{
    const k=d.srvName||'(no server)';
    if(!bySrv.has(k))bySrv.set(k,[]);
    bySrv.get(k).push(d);
  });
  bySrv.forEach((groups,srv)=>{
    const srvRow=document.createElement('div');srvRow.className='sort-preview-row';
    srvRow.innerHTML=`<span class="srv">${esc(srv)}</span> — ${groups.length} group${groups.length!==1?'s':''}`;
    prev.appendChild(srvRow);
    groups.forEach(g=>{
      const grpRow=document.createElement('div');grpRow.className='sort-preview-row';
      grpRow.style.paddingLeft='12px';
      grpRow.innerHTML=`<span class="grp">${esc(g.grpName)}</span> <span class="cnt">${g.cookies.length} cookie${g.cookies.length!==1?'s':''}</span>`;
      prev.appendChild(grpRow);
    });
  });
  prev.classList.add('show');
});

document.getElementById('sort-confirm').addEventListener('click',async()=>{
  const dist=calcDistribution();
  if(!dist.length){toast('Nothing to create','warn');return;}

  // Check server limits
  const srvCounts=new Map();
  dist.forEach(d=>{
    if(d.srvName){
      const k=d.srvName.trim().toLowerCase();
      const existing=vault.filter(g=>(g.serverName||'').trim().toLowerCase()===k).length;
      srvCounts.set(k,(srvCounts.get(k)||0)+1+existing);
    }
  });
  for(const [k,count] of srvCounts){
    if(count>18){
      const srvLabel=dist.find(d=>d.srvName&&d.srvName.trim().toLowerCase()===k)?.srvName||k;
      toast(`Server "${srvLabel}" would exceed 18 group limit`,'err');
      return;
    }
  }

  // Create all groups — cookies preserved top-to-bottom within each group
  dist.forEach(d=>{
    const group={
      id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),
      name:d.grpName,
      serverName:d.srvName,
      createdAt:Date.now(),
      pinned:false,banned:false,alternatives:[],
      cookies:d.cookies.map(c=>({...c})),
      changelog:[]
    };
    logChange(group,`Created via distribute (${d.cookies.length} cookies)`);
    vault.unshift(group);
  });
  saveVault();
  closeMod('sort-modal');
  document.getElementById('paste-ta').value='';
  document.getElementById('paste-info').innerHTML='Awaiting input...';
  document.getElementById('add-btn').disabled=true;
  render();
  toast(`Created ${dist.length} groups from ${sortPending.length} cookies`,'ok');
});

document.getElementById('sort-cancel').addEventListener('click',()=>closeMod('sort-modal'));

// ═══════════════════════════════════════
// BULK SELECT
// ═══════════════════════════════════════
let bulkSelected=new Set();

function toggleBulkSelect(id){
  if(bulkSelected.has(id))bulkSelected.delete(id);else bulkSelected.add(id);
  updateBulkBar();
  const card=document.querySelector(`.gcard[data-id="${id}"]`);
  if(card)card.classList.toggle('bulk-selected',bulkSelected.has(id));
}

function updateBulkBar(){
  const bar=document.getElementById('bulk-bar');
  const count=bulkSelected.size;
  document.getElementById('bulk-bar-count').textContent=count+' selected';
  bar.classList.toggle('open',count>0);
}

function clearBulkSelect(){
  bulkSelected.clear();
  document.querySelectorAll('.gcard.bulk-selected').forEach(c=>c.classList.remove('bulk-selected'));
  updateBulkBar();
}

function getBulkGroups(){
  return vault.filter(g=>bulkSelected.has(g.id));
}

document.getElementById('bulk-bar-cancel').addEventListener('click',clearBulkSelect);

document.getElementById('bulk-bar-export').addEventListener('click',e=>{
  if(!bulkSelected.size)return;
  const groups=getBulkGroups();
  openExpPopup(e.currentTarget,groups);
  e.currentTarget.classList.add('bulk-bar-export-anchor');
});

document.getElementById('bulk-bar-copy').addEventListener('click',()=>{
  if(!bulkSelected.size)return;
  // Sort by visual DOM order top-to-bottom
  const cards=[...document.querySelectorAll('.gcard')];
  const orderedIds=cards.map(c=>c.dataset.id).filter(id=>bulkSelected.has(id));
  const orderedGroups=orderedIds.map(id=>vault.find(g=>g.id===id)).filter(Boolean);
  const lines=orderedGroups.flatMap(g=>g.cookies.map(c=>fmtLine(c,'user:pass:cookie'))).filter(Boolean);
  copyText(lines.join('\n'),()=>toast(`Copied ${lines.length} cookies`,'ok'),()=>toast('Copy failed','err'));
  clearBulkSelect();
});

document.getElementById('bulk-bar-ban').addEventListener('click',async()=>{
  if(!bulkSelected.size)return;
  const n=bulkSelected.size;
  const ok=await customConfirm(`Mark ${n} group${n!==1?'s':''} as banned?`,'Ban All');
  if(!ok)return;
  getBulkGroups().forEach(g=>{g.banned=true;logChange(g,'Bulk banned');});
  saveVault();render();clearBulkSelect();toast(`${n} group${n!==1?'s':''} banned`,'ok');
});

document.getElementById('bulk-bar-delete').addEventListener('click',async()=>{
  if(!bulkSelected.size)return;
  const n=bulkSelected.size;
  const ok=await customConfirm(`Delete ${n} group${n!==1?'s':''}? This cannot be undone.`,'Delete All');
  if(!ok)return;
  vault=vault.filter(g=>!bulkSelected.has(g.id));
  saveVault();clearBulkSelect();render();toast(`${n} group${n!==1?'s':''} deleted`,'ok');
});

// ═══════════════════════════════════════
// COOKIE SORT IN PANEL (Feature 9)
// ═══════════════════════════════════════
let panelCookieSort='default';

function buildPanelSortBar(groupId){
  const existing=document.getElementById('p-cookie-sort-bar');
  if(existing)existing.remove();
  const bar=document.createElement('div');
  bar.id='p-cookie-sort-bar';
  bar.style.cssText='display:flex;gap:4px;padding:8px 0 4px;margin-bottom:6px;border-bottom:1px solid var(--bdr);';
  const opts=['default','a-z','username','banned'];
  const lbls=['Default','A–Z','Username','Banned first'];
  opts.forEach((o,i)=>{
    const btn=document.createElement('button');
    btn.textContent=lbls[i];
    btn.style.cssText=`background:none;border:1px solid ${o===panelCookieSort?'var(--a2)':'var(--bdr)'};border-radius:6px;
      padding:3px 9px;font-family:var(--mono);font-size:9px;letter-spacing:.5px;cursor:pointer;
      color:${o===panelCookieSort?'var(--a2)':'var(--dim)'};transition:all .12s;`;
    btn.addEventListener('click',()=>{
      panelCookieSort=o;
      refreshPanel();
    });
    bar.appendChild(btn);
  });
  return bar;
}

function sortedPanelCookies(cookies){
  if(!cookies)return[];
  const c=[...cookies];
  if(panelCookieSort==='a-z')return c.sort((a,b)=>(a.username||'').localeCompare(b.username||''));
  if(panelCookieSort==='username')return c.sort((a,b)=>(a.username||'zzz').localeCompare(b.username||'zzz'));
  if(panelCookieSort==='banned')return c.sort((a,b)=>(b.banStatus==='banned'?1:0)-(a.banStatus==='banned'?1:0));
  return c;
}

// Patch refreshPanel to inject sort bar + use sorted cookies
const _origRefreshPanel=refreshPanel;
refreshPanel=function(){
  _origRefreshPanel();
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const grid=document.getElementById('p-grid');
  // Insert sort bar before grid
  const existing=document.getElementById('p-cookie-sort-bar');
  if(existing)existing.remove();
  if(g.cookies&&g.cookies.length>1){
    grid.parentNode.insertBefore(buildPanelSortBar(g.id),grid);
  }
  // Re-render grid with sorted cookies
  grid.innerHTML='';
  sortedPanelCookies(g.cookies).forEach((c,i)=>grid.appendChild(mkCkItem(c,i,g.id)));
};

// ═══════════════════════════════════════
// AUTO SORT ON ADD (Feature 7)
// ═══════════════════════════════════════
// patch render to mark new card position; handled in confirmAdd via fly-in after insert
// The key: after confirmAdd calls vault.unshift(), we re-sort before saving so card appears in A-Z position
const _origConfirmAdd=confirmAdd;
// wrap via event: intercept saveVault after add by patching sortVault to always apply before render
// Actually simplest: patch vault.unshift to do a sorted insert instead
function sortedInsert(group){
  if(sort!=='az'&&sort!=='za'){vault.unshift(group);return;}
  const dir=sort==='za'?-1:1;
  let idx=vault.findIndex(g=>g.name.toLowerCase().localeCompare(group.name.toLowerCase())*dir>0);
  if(idx===-1)vault.push(group);else vault.splice(idx,0,group);
}

// ═══════════════════════════════════════
// SEARCH LIFT (Feature 8)
// ═══════════════════════════════════════
// Patch applyFilter to lift matching cards to top of their section
const _origApplyFilter=applyFilter;
applyFilter=function(){
  _origApplyFilter();
  // No DOM reordering — just dim/undim. Reordering caused visual glitches.
};

// ═══════════════════════════════════════
// STATS: Per-server breakdown (Feature 10)
// ═══════════════════════════════════════
const _origShowStats=showStats;
showStats=function(){
  _origShowStats();
  // Inject per-server breakdown below stats-fun
  const fun=document.getElementById('stats-fun');
  const existing=document.getElementById('stats-srv-breakdown');
  if(existing)existing.remove();
  const srvMap=new Map();
  vault.forEach(g=>{
    const k=(g.serverName||'(ungrouped)').trim();
    if(!srvMap.has(k))srvMap.set(k,{groups:0,cookies:0,banned:0});
    const s=srvMap.get(k);s.groups++;s.cookies+=g.cookies.length;
    if(g.banned)s.banned++;
  });
  if(!srvMap.size)return;
  const wrap=document.createElement('div');wrap.id='stats-srv-breakdown';
  wrap.style.cssText='margin-top:14px;border-top:1px solid var(--bdr);padding-top:12px;';
  wrap.innerHTML='<div style="font-family:var(--mono);font-size:9px;letter-spacing:2px;color:var(--dim);text-transform:uppercase;margin-bottom:8px;">Per-Server Breakdown</div>';
  const table=document.createElement('div');
  table.style.cssText='display:flex;flex-direction:column;gap:5px;';
  srvMap.forEach((v,k)=>{
    const row=document.createElement('div');
    row.style.cssText='display:flex;align-items:center;gap:8px;padding:6px 10px;background:rgba(255,255,255,.03);border-radius:7px;border:1px solid var(--bdr);';
    row.innerHTML=`<div style="font-family:var(--sans);font-weight:700;font-size:11px;color:var(--bright);flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${esc(k)}</div>
      <span style="font-family:var(--mono);font-size:9px;color:var(--dim);">${v.groups}g</span>
      <span style="font-family:var(--mono);font-size:9px;color:var(--a2);">${v.cookies}c</span>
      ${v.banned?`<span style="font-family:var(--mono);font-size:9px;color:var(--danger);">${v.banned} banned</span>`:''}`;
    table.appendChild(row);
  });
  wrap.appendChild(table);
  fun.parentNode.insertBefore(wrap,fun.nextSibling);
};

// ═══════════════════════════════════════
// HEALTH SCORE TOAST BREAKDOWN (Feature 11)
// ═══════════════════════════════════════
document.getElementById('health-badge').addEventListener('click',()=>{
  const {score,grade}=calcHealthScore();
  const last=settings.lastBackup;
  const backupAge=last?Math.floor((Date.now()-last)/86400000):999;
  const backupMsg=backupAge===999?'no backup':'backup '+backupAge+'d ago';
  const bannedCount=vault.filter(g=>g.banned).length;
  const emptyCount=vault.filter(g=>!g.cookies||g.cookies.length===0).length;
  const streak=settings.streak||0;
  const syncOk=ghEnabled()&&settings.lastGithubSync&&Math.floor((Date.now()-settings.lastGithubSync)/86400000)<=1;
  const lines=[
    `Health: ${score}/100 · Grade ${grade}`,
    `Backup: ${backupMsg}`,
    `Ban ratio: ${bannedCount}/${vault.length} groups`,
    `Empty groups: ${emptyCount}`,
    `Streak: ${streak} day${streak!==1?'s':''}`,
    syncOk?'Sync: up to date':'Sync: not recent',
  ];
  const el=document.getElementById('toast');
  document.getElementById('toast-msg').innerHTML=lines.map(l=>`<div style="line-height:1.7">${l}</div>`).join('');
  el.className='show ok';
  clearTimeout(window._toastT);
  window._toastT=setTimeout(()=>{el.className='';},5000);
});

// ═══════════════════════════════════════
// LAST CHECKED TIMESTAMP ON CARDS (Feature 12)
// ═══════════════════════════════════════
// After ban check completes, store checkedAt on each checked group and show on card
// Patch the ban run finalize to save checkedAt
const _origBanFinalize=()=>{};// no-op, we hook via saveVault after ban check

// Patch mkCard to show lastChecked if present
const _origMkCard=mkCard;
mkCard=function(group){
  const card=_origMkCard(group);
  if(group.lastChecked){
    const ts=document.createElement('div');
    ts.style.cssText='position:absolute;bottom:5px;left:8px;font-family:var(--mono);font-size:7px;color:var(--dim);letter-spacing:.3px;pointer-events:none;z-index:3;';
    ts.textContent='checked '+fmtTime(group.lastChecked);
    card.appendChild(ts);
  }
  return card;
};

// ═══════════════════════════════════════
// COOKIE ACTIVITY LOG
// ═══════════════════════════════════════
const CKLOG_K='sv_cookie_log';
const CKLOG_MAX=1000;
const CKLOG_SHOW=100;

function loadCkLog(){
  try{const r=localStorage.getItem(CKLOG_K);return r?JSON.parse(r):[]}catch{return[];}
}
function saveCkLog(log){
  // Cap at 1000
  if(log.length>CKLOG_MAX)log=log.slice(0,CKLOG_MAX);
  try{localStorage.setItem(CKLOG_K,JSON.stringify(log));}catch(e){/* quota */}
}
function ckLogEvent(type,msg,cookie){
  // type: added|edited|deleted|banned|active|expired|facelock|copied
  const log=loadCkLog();
  log.unshift({
    t:Date.now(),
    type,
    msg,
    user:cookie?.username||null,
    ck:cookie?.cookie?cookie.cookie.substring(0,40)+'…':null
  });
  saveCkLog(log);
}

let ckLogFilter='all';
function openCkLogModal(){
  renderCkLog();
  openMod('cklog-modal');
}
function renderCkLog(){
  const log=loadCkLog();
  const filtered=ckLogFilter==='all'?log:log.filter(e=>e.type===ckLogFilter);
  const shown=filtered.slice(0,CKLOG_SHOW);
  const scroll=document.getElementById('cklog-scroll');
  const count=document.getElementById('cklog-count');
  count.textContent=filtered.length+' entries (showing '+Math.min(filtered.length,CKLOG_SHOW)+')';
  if(!shown.length){
    scroll.innerHTML='<div class="cklog-empty">No activity yet</div>';
    return;
  }
  scroll.innerHTML='';
  shown.forEach(e=>{
    const row=document.createElement('div');row.className='cklog-entry';
    const d=new Date(e.t);
    const ts=d.toLocaleDateString('en',{month:'short',day:'numeric'})+' '+d.toTimeString().slice(0,5);
    const label=e.user?esc(e.user):(e.ck?`<span style="color:var(--dim);font-size:8px">${esc(e.ck)}</span>`:'—');
    row.innerHTML=`<span class="cklog-ts">${ts}</span><span class="cklog-type ${e.type}">${e.type}</span><span class="cklog-msg">${label} — ${esc(e.msg)}</span>`;
    scroll.appendChild(row);
  });
}

// Filter buttons
document.querySelectorAll('.cklog-filter').forEach(btn=>{
  btn.addEventListener('click',()=>{
    ckLogFilter=btn.dataset.ckfilter;
    document.querySelectorAll('.cklog-filter').forEach(b=>b.classList.toggle('on',b.dataset.ckfilter===ckLogFilter));
    renderCkLog();
  });
});

document.getElementById('hdr-cklog-btn').addEventListener('click',openCkLogModal);
document.getElementById('cklog-close').addEventListener('click',()=>closeMod('cklog-modal'));
document.getElementById('cklog-dl-txt').addEventListener('click',()=>{
  const log=loadCkLog();
  const lines=log.map(e=>{
    const d=new Date(e.t).toISOString();
    return`[${d}] [${e.type.toUpperCase()}] ${e.user||''}  ${e.msg}${e.ck?' | '+e.ck:''}`;
  });
  dl(lines.join('\n'),`saturnity-log-${Date.now()}.txt`);
  toast(`Downloaded ${log.length} log entries`,'ok');
});
document.getElementById('cklog-dl-json').addEventListener('click',()=>{
  const log=loadCkLog();
  dl(JSON.stringify(log,null,2),`saturnity-log-${Date.now()}.json`);
  toast(`Downloaded ${log.length} log entries`,'ok');
});
document.getElementById('cklog-clear').addEventListener('click',async()=>{
  const ok=await customConfirm('Clear the entire cookie activity log? This cannot be undone.','Clear Log');
  if(!ok)return;
  localStorage.removeItem(CKLOG_K);
  renderCkLog();
  toast('Activity log cleared','ok');
});

// ── Hook ckLogEvent into vault mutation points ──

// 1. Cookie added (via confirmAdd)
const _ckOrigConfirmAdd=confirmAdd;
confirmAdd=async function(){
  const before=vault.map(g=>({id:g.id,n:g.cookies.length}));
  await _ckOrigConfirmAdd.apply(this,arguments);
  vault.forEach(g=>{
    const prev=before.find(x=>x.id===g.id);
    const added=prev?g.cookies.length-prev.n:g.cookies.length;
    if(added>0){
      g.cookies.slice(-added).forEach(c=>{
        ckLogEvent('added',`Added to group "${esc(g.name)}"`,c);
      });
    }
  });
};

// 2. Cookie edited — hook mkCkItem save button
const _ckOrigMkCkItem=mkCkItem;
mkCkItem=function(c,idx,groupId,opts){
  const item=_ckOrigMkCkItem.apply(this,arguments);
  // find the save button and wrap it
  const saveBtn=item.querySelector('.ck-save-btn');
  if(saveBtn){
    const origClick=saveBtn.onclick;
    saveBtn.addEventListener('click',()=>{
      const g=vault.find(x=>x.id===groupId);
      if(g)ckLogEvent('edited',`Cookie edited in group "${esc(g.name)}"`,c);
    });
  }
  return item;
};

// 3. Cookie deleted — hook the delete button in mkCkItem
// Wrapped by watching delGroup calls + per-cookie delete
const _ckOrigDelGroup=delGroup;
delGroup=function(id){
  const g=vault.find(x=>x.id===id);
  if(g){
    g.cookies.forEach(c=>ckLogEvent('deleted',`Group "${esc(g.name)}" deleted`,c));
  }
  _ckOrigDelGroup.apply(this,arguments);
};

// Copy events — no longer logged (spam)

// ═══════════════════════════════════════
// FIX 14: REFRESH BUTTON
// ═══════════════════════════════════════
document.getElementById('hdr-refresh-btn').addEventListener('click',()=>{
  render();
  toast('Vault refreshed','ok');
});

// ═══════════════════════════════════════
// FIX 11: PASTE FROM CLIPBOARD
// ═══════════════════════════════════════
document.getElementById('paste-from-clip-btn').addEventListener('click',async()=>{
  try{
    const text=await navigator.clipboard.readText();
    if(!text.trim()){toast('Clipboard is empty','warn');return;}
    document.getElementById('paste-ta').value=text;
    document.getElementById('paste-ta').dispatchEvent(new Event('input'));
    const panel=document.getElementById('paste-panel');
    if(!panel.classList.contains('open'))panel.classList.add('open');
  }catch(e){toast('Clipboard read failed — paste manually','warn');}
});

// ═══════════════════════════════════════
// FIX 9: NOTES FIELD
// ═══════════════════════════════════════
function refreshPanelNotes(g){
  const val=document.getElementById('p-notes-val');
  const ta=document.getElementById('p-notes-ta');
  const actions=document.getElementById('p-notes-actions');
  const editBtn=document.getElementById('p-notes-edit-btn');
  if(!val)return;
  val.textContent=g.notes||'';
  val.style.color=g.notes?'var(--txt)':'var(--dim)';
  if(!g.notes)val.textContent='No notes';
  ta.style.display='none';
  actions.style.display='none';
  editBtn.style.display='';
}
document.getElementById('p-notes-edit-btn').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const val=document.getElementById('p-notes-val');
  const ta=document.getElementById('p-notes-ta');
  const actions=document.getElementById('p-notes-actions');
  val.style.display='none';
  ta.value=g.notes||'';
  ta.style.display='';
  actions.style.display='flex';
  document.getElementById('p-notes-edit-btn').style.display='none';
  ta.focus();
});
document.getElementById('p-notes-cancel').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  document.getElementById('p-notes-val').style.display='';
  document.getElementById('p-notes-ta').style.display='none';
  document.getElementById('p-notes-actions').style.display='none';
  document.getElementById('p-notes-edit-btn').style.display='';
  refreshPanelNotes(g);
});
document.getElementById('p-notes-save').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===panelId);if(!g)return;
  const newNotes=document.getElementById('p-notes-ta').value.trim();
  g.notes=newNotes||null;
  saveVault();
  document.getElementById('p-notes-val').style.display='';
  document.getElementById('p-notes-ta').style.display='none';
  document.getElementById('p-notes-actions').style.display='none';
  document.getElementById('p-notes-edit-btn').style.display='';
  refreshPanelNotes(g);
  toast('Notes saved','ok');
});
// Patch refreshPanel to also load notes
const _rp_orig=refreshPanel;
refreshPanel=function(){
  _rp_orig();
  const g=vault.find(x=>x.id===panelId);
  if(g)refreshPanelNotes(g);
};

// ═══════════════════════════════════════
// FIX 12: MOVE COOKIE TO ANOTHER GROUP
// ═══════════════════════════════════════
let _moveCookieGid=null,_moveCookieIdx=null;
function openMoveCookieModal(gid,idx){
  _moveCookieGid=gid;_moveCookieIdx=idx;
  const g=vault.find(x=>x.id===gid);if(!g)return;
  const c=g.cookies[idx];
  document.getElementById('move-cookie-desc').textContent=
    `Moving cookie${c.username?' "'+c.username+'"':' #'+(idx+1)} from "${g.name}"`;
  const list=document.getElementById('move-cookie-list');
  list.innerHTML='';
  vault.filter(x=>x.id!==gid).forEach(dest=>{
    const btn=document.createElement('button');btn.className='move-group-opt';
    btn.innerHTML=`<span style="color:var(--bright)">${esc(dest.name)}</span>${dest.serverName?`<span style="color:var(--dim);font-size:10px;margin-left:8px">${esc(dest.serverName)}</span>`:''}
      <span style="color:var(--dim);font-size:10px;float:right">${dest.cookies.length}c</span>`;
    btn.addEventListener('click',()=>{
      const src=vault.find(x=>x.id===_moveCookieGid);
      const dst=vault.find(x=>x.id===dest.id);
      if(!src||!dst)return;
      const [moved]=src.cookies.splice(_moveCookieIdx,1);
      dst.cookies.push(moved);
      logChange(src,`Cookie${moved.username?' "'+moved.username+'"':''} moved to "${esc(dst.name)}"`);
      logChange(dst,`Cookie${moved.username?' "'+moved.username+'"':''} moved from "${esc(src.name)}"`);
      saveVault();refreshPanel();render();
      closeMod('move-cookie-modal');
      toast(`Moved to "${dest.name}"`,'ok');
    });
    list.appendChild(btn);
  });
  openMod('move-cookie-modal');
}
document.getElementById('move-cookie-cancel').addEventListener('click',()=>closeMod('move-cookie-modal'));

// ═══════════════════════════════════════
// FIX 4+5: SWAP COOKIE FEATURE
// ═══════════════════════════════════════
const SWAP_REMINDERS_K='cv_swap_reminders';
let _swapGid=null,_swapIdx=null,_swapSelectedAlt=null;

function loadSwapReminders(){
  try{return JSON.parse(localStorage.getItem(SWAP_REMINDERS_K)||'[]');}catch{return[];}
}
function saveSwapReminders(r){localStorage.setItem(SWAP_REMINDERS_K,JSON.stringify(r));}

function openSwapModal(gid,idx){
  _swapGid=gid;_swapIdx=idx;_swapSelectedAlt=null;
  const g=vault.find(x=>x.id===gid);if(!g)return;
  const c=g.cookies[idx];
  document.getElementById('swap-modal-desc').textContent=
    `Replacing cookie${c.username?' "'+c.username+'"':' #'+(idx+1)} in "${g.name}"`;
  // Reset tabs
  document.getElementById('swap-tab-paste').classList.add('on');
  document.getElementById('swap-tab-alts').classList.remove('on');
  document.getElementById('swap-paste-panel').style.display='';
  document.getElementById('swap-alts-panel').style.display='none';
  document.getElementById('swap-paste-ta').value='';
  document.getElementById('swap-paste-info').textContent='';
  // Reset reason
  document.querySelectorAll('.swap-reason-btn').forEach(b=>b.classList.toggle('on',b.dataset.reason==='1d'));
  // Build alts list
  const altsList=document.getElementById('swap-alts-list');
  altsList.innerHTML='';
  if(g.alternatives&&g.alternatives.length){
    g.alternatives.forEach((alt,ai)=>{
      const opt=document.createElement('div');opt.className='swap-alt-opt';
      opt.innerHTML=`<div class="alt-label">${esc(alt.label||'Alt '+(ai+1))}</div>
        <div class="alt-cookies">${alt.cookies.map(c=>c.username||'(no user)').join(', ')}</div>`;
      opt.addEventListener('click',()=>{
        document.querySelectorAll('.swap-alt-opt').forEach(x=>x.classList.remove('selected'));
        opt.classList.add('selected');
        _swapSelectedAlt={altIdx:ai,alt};
      });
      altsList.appendChild(opt);
    });
  }else{
    altsList.innerHTML='<div style="font-family:var(--mono);font-size:10px;color:var(--dim);padding:8px 0;">No alt cookies for this group</div>';
  }
  openMod('swap-modal');
}

document.getElementById('swap-tab-paste').addEventListener('click',()=>{
  document.getElementById('swap-tab-paste').classList.add('on');
  document.getElementById('swap-tab-alts').classList.remove('on');
  document.getElementById('swap-paste-panel').style.display='';
  document.getElementById('swap-alts-panel').style.display='none';
});
document.getElementById('swap-tab-alts').addEventListener('click',()=>{
  document.getElementById('swap-tab-alts').classList.add('on');
  document.getElementById('swap-tab-paste').classList.remove('on');
  document.getElementById('swap-alts-panel').style.display='';
  document.getElementById('swap-paste-panel').style.display='none';
});
document.querySelectorAll('.swap-reason-btn').forEach(b=>{
  b.addEventListener('click',()=>{
    document.querySelectorAll('.swap-reason-btn').forEach(x=>x.classList.remove('on'));
    b.classList.add('on');
  });
});
document.getElementById('swap-paste-ta').addEventListener('input',()=>{
  const val=document.getElementById('swap-paste-ta').value;
  const p=parseInput(val);
  const info=document.getElementById('swap-paste-info');
  if(!val.trim()){info.textContent='';return;}
  info.textContent=p.length?p.length+' cookie'+(p.length!==1?'s':'')+ ' detected':'No valid cookies';
  info.style.color=p.length?'var(--ok)':'var(--danger)';
});
document.getElementById('swap-cancel').addEventListener('click',()=>closeMod('swap-modal'));
document.getElementById('swap-confirm').addEventListener('click',()=>{
  const g=vault.find(x=>x.id===_swapGid);if(!g)return;
  const reason=document.querySelector('.swap-reason-btn.on')?.dataset.reason||'1d';
  const isPasteMode=document.getElementById('swap-paste-panel').style.display!=='none';
  let newCookie=null;

  if(isPasteMode){
    const p=parseInput(document.getElementById('swap-paste-ta').value);
    if(!p.length){toast('No valid cookie pasted','err');return;}
    newCookie=p[0];
  }else{
    if(!_swapSelectedAlt){toast('Select an alt cookie first','warn');return;}
    // Use first cookie of selected alt set
    const altSet=_swapSelectedAlt.alt;
    if(!altSet.cookies.length){toast('Alt set is empty','warn');return;}
    newCookie={...altSet.cookies[0]};
    // Remove used cookie from alt set, remove alt set if empty
    altSet.cookies.splice(0,1);
    if(!altSet.cookies.length){
      g.alternatives.splice(_swapSelectedAlt.altIdx,1);
    }
  }

  // Archive old cookie into alts with reason tag
  const old=g.cookies[_swapIdx];
  const tag=reason==='expired'?'expired':reason==='1d'?'1d ban':'7d ban';
  const altLabel=`${old.username||'Cookie #'+(_swapIdx+1)} — ${tag} ${new Date().toLocaleDateString('en',{month:'short',day:'numeric'})}`;
  if(!g.alternatives)g.alternatives=[];
  g.alternatives.push({
    id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),
    label:altLabel,
    cookies:[{...old}],
    swapReason:reason,
    swappedAt:Date.now()
  });

  // Place new cookie
  g.cookies[_swapIdx]={...newCookie};
  logChange(g,`Cookie${old.username?' "'+old.username+'"':''} swapped (${tag}) → ${newCookie.username||'new cookie'}`);
  saveVault();

  // Schedule reminder for 1d / 7d bans
  if(reason==='1d'||reason==='7d'){
    const reminders=loadSwapReminders();
    const hours=reason==='1d'?24:168; // 7*24
    reminders.push({
      id:Date.now().toString(36),
      username:old.username||null,
      groupName:g.name,
      reason,
      remindAt:Date.now()+hours*3600000,
      shown:false
    });
    saveSwapReminders(reminders);
  }

  closeMod('swap-modal');
  refreshPanel();render();
  toast(`Cookie swapped — ${old.username||''} archived as "${tag}"`,'ok');
});

// Check swap reminders on PIN unlock — show on PIN screen
function checkSwapReminders(){
  const reminders=loadSwapReminders();
  const due=reminders.filter(r=>!r.shown&&r.remindAt<=Date.now());
  if(!due.length)return;
  const banner=document.getElementById('pin-reminder-banner');
  if(!banner)return;
  banner.innerHTML='';
  due.forEach(r=>{
    const msg=document.createElement('div');
    msg.style.cssText='font-family:var(--mono);font-size:10px;color:var(--ok);margin-bottom:4px;';
    msg.textContent=`${r.username||r.groupName} — ${r.reason} ban lifted, ready to swap back`;
    banner.appendChild(msg);
    r.shown=true;
  });
  banner.style.display='block';
  saveSwapReminders(reminders);
}

// ═══════════════════════════════════════
// FIX 13: SYNC NOW MODAL
// ═══════════════════════════════════════
// ═══════════════════════════════════════
// FIX: SYNC NOW — username-match + txt support
// ═══════════════════════════════════════
let _syncFileData=null; // {type:'json'|'txt', data}

function openSyncNowModal(){
  document.getElementById('sync-tab-paste').classList.add('on');
  document.getElementById('sync-tab-file').classList.remove('on');
  document.getElementById('sync-paste-panel').style.display='';
  document.getElementById('sync-file-panel').style.display='none';
  document.getElementById('sync-paste-ta').value='';
  document.getElementById('sync-paste-info').textContent='';
  document.getElementById('sync-file-info').textContent='';
  _syncFileData=null;
  openMod('sync-now-modal');
}

document.getElementById('sync-tab-paste').addEventListener('click',()=>{
  document.getElementById('sync-tab-paste').classList.add('on');
  document.getElementById('sync-tab-file').classList.remove('on');
  document.getElementById('sync-paste-panel').style.display='';
  document.getElementById('sync-file-panel').style.display='none';
});
document.getElementById('sync-tab-file').addEventListener('click',()=>{
  document.getElementById('sync-tab-file').classList.add('on');
  document.getElementById('sync-tab-paste').classList.remove('on');
  document.getElementById('sync-file-panel').style.display='';
  document.getElementById('sync-paste-panel').style.display='none';
});

document.getElementById('sync-paste-ta').addEventListener('input',()=>{
  const p=parseInput(document.getElementById('sync-paste-ta').value);
  const info=document.getElementById('sync-paste-info');
  if(!p.length){info.textContent='';return;}
  const withUser=p.filter(c=>c.username).length;
  info.textContent=`${p.length} cookies — ${withUser} with username (matched to existing), ${p.length-withUser} cookie-only`;
  info.style.color='var(--ok)';
});

document.getElementById('sync-file-pick').addEventListener('click',()=>{
  const fi=document.createElement('input');fi.type='file';fi.accept='.json,.txt';
  fi.addEventListener('change',()=>{
    const f=fi.files[0];if(!f)return;
    const r=new FileReader();r.onload=ev=>{
      const raw=ev.target.result;
      const infoEl=document.getElementById('sync-file-info');
      if(f.name.toLowerCase().endsWith('.txt')){
        const p=parseInput(raw);
        if(!p.length){infoEl.textContent='No valid cookies in file';infoEl.style.color='var(--danger)';_syncFileData=null;return;}
        _syncFileData={type:'txt',cookies:p};
        const wu=p.filter(c=>c.username).length;
        infoEl.textContent=`${p.length} cookies from "${f.name}" — ${wu} with username`;
        infoEl.style.color='var(--ok)';
      }else{
        try{
          const d=JSON.parse(raw);
          if(!d.vault||!Array.isArray(d.vault))throw new Error('bad format');
          _syncFileData={type:'json',groups:d.vault};
          const tc=d.vault.reduce((s,g)=>s+(g.cookies||[]).length,0);
          infoEl.textContent=`${d.vault.length} groups, ${tc} cookies from "${f.name}"`;
          infoEl.style.color='var(--ok)';
        }catch{infoEl.textContent='Invalid vault .json';infoEl.style.color='var(--danger)';_syncFileData=null;}
      }
    };r.readAsText(f);
  });
  fi.click();
});

// Core: match incoming cookies into vault by username, update cookie+password in-place
function applySyncCookies(incomingCookies){
  let updated=0;
  const notFound=[];
  incomingCookies.forEach(ic=>{
    if(!ic.username){notFound.push(ic);return;}
    const uLow=ic.username.toLowerCase();
    let found=false;
    vault.forEach(g=>{
      g.cookies.forEach((c,ci)=>{
        if((c.username||'').toLowerCase()===uLow){
          const changed=c.cookie!==ic.cookie||(ic.password&&c.password!==ic.password);
          if(changed){
            c.cookie=ic.cookie;
            if(ic.password)c.password=ic.password;
            c.banStatus=undefined;
            logChange(g,`Cookie updated via sync: ${esc(ic.username)}`);
            ckLogEvent('edited',`Synced — cookie updated in "${esc(g.name)}"`,ic);
            updated++;
          }
          found=true;
        }
      });
    });
    if(!found)notFound.push(ic);
  });
  return{updated,notFound};
}

document.getElementById('sync-now-cancel').addEventListener('click',()=>closeMod('sync-now-modal'));
document.getElementById('sync-now-confirm').addEventListener('click',async()=>{
  const isPaste=document.getElementById('sync-paste-panel').style.display!=='none';

  if(isPaste){
    // Paste u:p:c tab
    const p=parseInput(document.getElementById('sync-paste-ta').value);
    if(!p.length){toast('No valid cookies','err');return;}
    const {updated,notFound}=applySyncCookies(p);
    let msg=`Updated ${updated} cookie${updated!==1?'s':''}`;
    if(notFound.length){
      // Ask what to do with unmatched cookies
      const ok=await customConfirm(
        `${notFound.length} username${notFound.length!==1?'s':''} not found in vault. Add as new group?`,
        'Add unmatched'
      );
      if(ok){
        const group={
          id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),
          name:'Synced '+new Date().toLocaleDateString('en',{month:'short',day:'numeric'}),
          serverName:null,createdAt:Date.now(),pinned:false,banned:false,alternatives:[],
          cookies:notFound.map(c=>({...c})),changelog:[]
        };
        logChange(group,`Created from unmatched sync cookies (${notFound.length})`);
        sortedInsert(group);
        msg+=` · ${notFound.length} added as new group`;
      }
    }
    saveVault();closeMod('sync-now-modal');render();
    toast(msg,'ok');

  }else{
    // File tab
    if(!_syncFileData){toast('No file loaded','warn');return;}

    if(_syncFileData.type==='txt'){
      // .txt: same username-match logic
      const {updated,notFound}=applySyncCookies(_syncFileData.cookies);
      let msg=`Updated ${updated} cookie${updated!==1?'s':''}`;
      if(notFound.length){
        const ok=await customConfirm(
          `${notFound.length} unmatched cookies. Add as new group?`,
          'Add unmatched'
        );
        if(ok){
          const group={
            id:Date.now().toString(36)+Math.random().toString(36).slice(2,5),
            name:'Synced '+new Date().toLocaleDateString('en',{month:'short',day:'numeric'}),
            serverName:null,createdAt:Date.now(),pinned:false,banned:false,alternatives:[],
            cookies:notFound.map(c=>({...c})),changelog:[]
          };
          logChange(group,`Created from unmatched sync cookies (${notFound.length})`);
          sortedInsert(group);
          msg+=` · ${notFound.length} added as new group`;
        }
      }
      saveVault();closeMod('sync-now-modal');render();
      toast(msg,'ok');

    }else{
      // .json: first do username-match updates on all cookies across all incoming groups,
      // then add any new groups that don't exist by ID
      const allIncoming=_syncFileData.groups.flatMap(g=>(g.cookies||[]).map(c=>({...c,_srcGroup:g})));
      const {updated,notFound}=applySyncCookies(allIncoming);
      // Add groups by ID that don't exist yet
      let added=0;
      _syncFileData.groups.forEach(g=>{
        if(!vault.find(x=>x.id===g.id)){
          vault.push({...g,changelog:g.changelog||[]});
          added++;
        }
      });
      saveVault();closeMod('sync-now-modal');render();
      toast(`Updated ${updated} cookies · ${added} new groups added`,'ok');
    }
  }
});

// ═══════════════════════════════════════
// SWAP REMINDER: inject banner into PIN screen
// ═══════════════════════════════════════
(()=>{
  const pinBox=document.querySelector('.pin-box');
  if(pinBox){
    const banner=document.createElement('div');
    banner.id='pin-reminder-banner';
    banner.style.cssText='display:none;background:rgba(0,255,170,.07);border:1px solid rgba(0,255,170,.2);border-radius:8px;padding:8px 12px;margin-bottom:12px;max-width:280px;text-align:left;';
    pinBox.insertBefore(banner,pinBox.firstChild);
  }
})();

// Check reminders when PIN screen is shown (called after successful unlock hidden)
const _origSubmitPin=submitPin;
submitPin=function(){
  _origSubmitPin.apply(this,arguments);
  setTimeout(checkSwapReminders,300);
};

// ═══════════════════════════════════════
// COOKIE EXTRACTOR
// ═══════════════════════════════════════

// Toggle panel open/close
document.getElementById('cx-toggle').addEventListener('click',()=>{
  const body=document.getElementById('cx-body');
  const chev=document.getElementById('cx-chev');
  const open=body.style.display==='flex';
  body.style.display=open?'none':'flex';
  chev.style.transform=open?'':'rotate(180deg)';
});

// Parse input: extract username from "username:anything:anything" or plain "username"
function parseCxInput(raw){
  return raw.split('\n')
    .map(l=>l.trim())
    .filter(Boolean)
    .map(l=>l.split(':')[0].trim())
    .filter(Boolean);
}

// Get cookies from currently active server filter
function getCxScopeGroups(){
  if(activeSrv==='all')return vault;
  return vault.filter(g=>(g.serverName||'').trim().toLowerCase()===activeSrv);
}

// Live count while typing
document.getElementById('cx-ta').addEventListener('input',()=>{
  const usernames=parseCxInput(document.getElementById('cx-ta').value);
  const info=document.getElementById('cx-info');
  if(!usernames.length){info.textContent='';return;}
  const scope=getCxScopeGroups();
  const allCookies=scope.flatMap(g=>g.cookies.map(c=>({...c,_group:g})));
  const matched=usernames.filter(u=>allCookies.some(c=>(c.username||'').toLowerCase()===u.toLowerCase()));
  const srv=activeSrv==='all'?'all groups':`server "${activeSrv}"`;
  info.textContent=`${matched.length}/${usernames.length} found in ${srv}`;
  info.style.color=matched.length>0?'var(--ok)':'var(--dim)';
  document.getElementById('cx-match-count').textContent=matched.length?`${matched.length}/${usernames.length}`:'';
});

// Extract button
document.getElementById('cx-search-btn').addEventListener('click',()=>{
  const usernames=parseCxInput(document.getElementById('cx-ta').value);
  if(!usernames.length){toast('No usernames to search','warn');return;}
  const scope=getCxScopeGroups();
  const allCookies=scope.flatMap(g=>g.cookies.map(c=>({...c,_group:g})));
  const results=[];
  usernames.forEach(u=>{
    const uLow=u.toLowerCase();
    const match=allCookies.find(c=>(c.username||'').toLowerCase()===uLow);
    results.push({username:u,cookie:match||null,group:match?match._group:null});
  });
  renderCxResults(results);
  const matched=results.filter(r=>r.cookie);
  document.getElementById('cx-copy-all-btn').style.display=matched.length?'':'none';
  document.getElementById('cx-copy-all-btn').dataset.matched=JSON.stringify(
    matched.map(r=>fmtLine(r.cookie,'user:pass:cookie'))
  );
  const info=document.getElementById('cx-info');
  info.textContent=`${matched.length}/${results.length} matched`;
  info.style.color=matched.length>0?'var(--ok)':'var(--dim)';
  document.getElementById('cx-match-count').textContent=`${matched.length}/${results.length}`;
});

function renderCxResults(results){
  const container=document.getElementById('cx-results');
  container.innerHTML='';
  if(!results.length){
    container.innerHTML='<div class="cx-no-match">No results</div>';return;
  }
  const matched=results.filter(r=>r.cookie).length;
  if(!matched){
    container.innerHTML='<div class="cx-no-match">No matches found in current server</div>';
  }
  results.forEach(r=>{
    const row=document.createElement('div');
    row.className='cx-result-row '+(r.cookie?'matched':'unmatched');
    const userEl=document.createElement('div');userEl.className='cx-result-user';
    userEl.textContent=r.username;
    row.appendChild(userEl);
    if(r.cookie){
      const meta=document.createElement('div');meta.className='cx-result-meta';
      meta.textContent=r.cookie.cookie?r.cookie.cookie.substring(0,30)+'…':'no cookie';
      row.appendChild(meta);
      if(r.group){
        const grpTag=document.createElement('div');grpTag.className='cx-result-group';
        grpTag.textContent=r.group.name;
        row.appendChild(grpTag);
      }
      const copyBtn=document.createElement('button');copyBtn.className='cx-result-copy';
      copyBtn.textContent='copy u:p:c';
      copyBtn.addEventListener('click',e=>{
        e.stopPropagation();
        const text=fmtLine(r.cookie,'user:pass:cookie');
        copyText(text,()=>{copyBtn.textContent='✓ copied';setTimeout(()=>copyBtn.textContent='copy u:p:c',1400);},
          ()=>toast('Copy failed','err'));
      });
      row.appendChild(copyBtn);
    }else{
      const notFound=document.createElement('div');notFound.className='cx-result-meta';
      notFound.textContent='not in vault';
      row.appendChild(notFound);
    }
    container.appendChild(row);
  });
}

// Copy all matched
document.getElementById('cx-copy-all-btn').addEventListener('click',()=>{
  const scope=getCxScopeGroups();
  const allCookies=scope.flatMap(g=>g.cookies.map(c=>({...c,_group:g})));
  const usernames=parseCxInput(document.getElementById('cx-ta').value);
  const lines=[];
  usernames.forEach(u=>{
    const match=allCookies.find(c=>(c.username||'').toLowerCase()===u.toLowerCase());
    if(match){const t=fmtLine(match,'user:pass:cookie');if(t)lines.push(t);}
  });
  if(!lines.length){toast('No matched cookies to copy','warn');return;}
  copyText(lines.join('\n'),()=>toast(`Copied ${lines.length} cookies`,'ok'),()=>toast('Copy failed','err'));
});

// Clear
document.getElementById('cx-clear-btn').addEventListener('click',()=>{
  document.getElementById('cx-ta').value='';
  document.getElementById('cx-results').innerHTML='';
  document.getElementById('cx-info').textContent='';
  document.getElementById('cx-match-count').textContent='';
  document.getElementById('cx-copy-all-btn').style.display='none';
});

// ═══════════════════════════════════════
// BUG 8B: GLOBAL ALTS VIEW
// ═══════════════════════════════════════
document.getElementById('hdr-alts-btn').addEventListener('click',openAltsModal);
document.getElementById('alts-modal-close').addEventListener('click',()=>closeMod('alts-modal'));

function openAltsModal(){
  const list=document.getElementById('alts-modal-list');
  list.innerHTML='';
  let totalSets=0;
  vault.forEach(g=>{
    if(!g.alternatives||!g.alternatives.length)return;
    g.alternatives.forEach((alt,ai)=>{
      totalSets++;
      const row=document.createElement('div');
      row.style.cssText='background:rgba(123,47,255,.04);border:1px solid rgba(123,47,255,.18);border-radius:9px;padding:10px 12px;';
      const hd=document.createElement('div');
      hd.style.cssText='display:flex;align-items:center;gap:8px;margin-bottom:6px;';
      hd.innerHTML=`
        <span style="font-family:var(--sans);font-weight:700;font-size:12px;color:var(--a3);flex:1;">${esc(alt.label||'Alt '+(ai+1))}</span>
        <span style="font-family:var(--mono);font-size:9px;color:var(--dim);">${alt.cookies.length} cookie${alt.cookies.length!==1?'s':''}</span>
        <span style="font-family:var(--mono);font-size:9px;color:var(--dim);background:rgba(0,0,0,.3);border:1px solid var(--bdr);border-radius:4px;padding:1px 6px;">from: ${esc(g.name)}</span>`;
      // Swap button — swap first cookie of this alt into the group as main
      if(!alt.cookies.length){row.appendChild(hd);list.appendChild(row);return;}
      const swapBtn=document.createElement('button');
      swapBtn.style.cssText='background:rgba(0,212,255,.08);border:1px solid rgba(0,212,255,.25);border-radius:6px;padding:4px 10px;font-family:var(--mono);font-size:9px;color:var(--a2);cursor:pointer;';
      swapBtn.textContent='Swap to main';
      swapBtn.addEventListener('click',async()=>{
        const cookieCount=g.cookies.length;
        if(!cookieCount){toast('Group has no main cookies to swap','warn');return;}
        // Pick which main cookie to swap out
        const idx=0; // swap first main cookie by default
        const oldMain=g.cookies[idx];
        const newMain={...alt.cookies[0]};
        // Archive old main back to this alt
        alt.cookies.splice(0,1,oldMain);
        g.cookies[idx]={...newMain};
        logChange(g,`Alt "${esc(alt.label||'Alt '+(ai+1))}" swapped to main`);
        saveVault();openAltsModal();render();
        if(panelId===g.id)refreshPanel();
        toast(`Swapped "${alt.label||'Alt '+(ai+1)}" into ${g.name}`,'ok');
      });
      hd.appendChild(swapBtn);
      row.appendChild(hd);
      // Show first cookie username
      const users=alt.cookies.map(c=>c.username||'(no user)').join(', ');
      const meta=document.createElement('div');
      meta.style.cssText='font-family:var(--mono);font-size:9px;color:var(--dim);';
      meta.textContent=users;
      row.appendChild(meta);
      list.appendChild(row);
    });
  });
  if(!totalSets){
    list.innerHTML='<div style="font-family:var(--mono);font-size:11px;color:var(--dim);text-align:center;padding:30px 0;letter-spacing:1px;">No alternative cookies in vault</div>';
  }
  openMod('alts-modal');
}

// ═══════════════════════════════════════
// BUG 8A: FIX ALTS DISAPPEARING — ensure alternatives always initialized
// ═══════════════════════════════════════
// Patch loadVault to always ensure alternatives array exists
const _svOrigLoadVault=loadVault;
loadVault=function(){
  const v=_svOrigLoadVault.apply(this,arguments);
  v.forEach(g=>{if(!g.alternatives)g.alternatives=[];});
  return v;
};

// ═══════════════════════════════════════
// BUG 12: PER-COOKIE BAN METADATA + REMINDERS
// ═══════════════════════════════════════
// Store ban start time + reason on the cookie object itself when swapping
// Patch the swap confirm handler to add banMeta to the archived cookie

const _svOrigSwapConfirm=document.getElementById('swap-confirm').onclick;
// We override via addEventListener since it was set that way
// Instead patch the swap logic at the archive step — find and wrap swap-confirm handler

// Check swap reminders: look at each cookie's banMeta and fire if time elapsed
function checkCookieBanReminders(){
  const banner=document.getElementById('pin-reminder-banner');
  if(!banner)return;
  const now=Date.now();
  const msgs=[];
  vault.forEach(g=>{
    (g.alternatives||[]).forEach(alt=>{
      (alt.cookies||[]).forEach(c=>{
        if(!c.banMeta)return;
        const {reason,startedAt,remindAt,reminded}=c.banMeta;
        if(reminded)return;
        if(reason==='perm'||reason==='expired')return; // no reminder for these
        if(remindAt&&now>=remindAt){
          msgs.push(`${c.username||'Cookie'} in "${g.name}" — ${reason==='1d'?'1-day':'7-day'} ban should be lifted`);
          c.banMeta.reminded=true;
        }
      });
    });
  });
  if(msgs.length){
    banner.innerHTML='';
    msgs.forEach(m=>{
      const d=document.createElement('div');
      d.style.cssText='font-family:var(--mono);font-size:10px;color:var(--ok);margin-bottom:4px;';
      d.textContent='🔓 '+m;
      banner.appendChild(d);
    });
    banner.style.display='block';
    saveVault(); // save the reminded=true flags
  }
}

// Patch swap-confirm to store banMeta on archived cookie
// Find the existing listener by wrapping the button
const _swapConfirmBtn=document.getElementById('swap-confirm');
const _origSwapListeners=[];
// Since we can't easily remove the existing listener, we store banMeta before the existing handler fires
// by adding a listener BEFORE (capture phase) on the button
_swapConfirmBtn.addEventListener('click',()=>{
  const reason=document.querySelector('.swap-reason-btn.on')?.dataset.reason||'1d';
  const g=vault.find(x=>x.id===_swapGid);
  if(!g)return;
  const c=g.cookies[_swapIdx];
  if(!c)return;
  // Tag the cookie that's about to be archived with banMeta
  const hours=reason==='1d'?24:reason==='7d'?168:null;
  c._pendingBanMeta={
    reason,
    startedAt:Date.now(),
    remindAt:hours?Date.now()+hours*3600000:null,
    reminded:false
  };
},true); // capture phase — fires before the existing click handler

// Patch the archive step in swap: after archiving, apply banMeta
const _origSwapConfirmHandler=document.getElementById('swap-confirm');
// We already have the swap logic inline — patch via observation of vault mutations
// Simplest: after any swap, scan alts for _pendingBanMeta and apply
const _realSaveVault=saveVault;
saveVault=function(){
  // Apply any pending ban meta to newly archived cookies
  vault.forEach(g=>{
    (g.alternatives||[]).forEach(alt=>{
      (alt.cookies||[]).forEach(c=>{
        if(c._pendingBanMeta){
          c.banMeta={...c._pendingBanMeta};
          delete c._pendingBanMeta;
        }
      });
    });
  });
  _realSaveVault.apply(this,arguments);
};

// Check reminders on PIN unlock
const _origSubmitPin2=submitPin;
submitPin=function(){
  _origSubmitPin2.apply(this,arguments);
  setTimeout(()=>{checkSwapReminders();checkCookieBanReminders();},300);
};

function openMod(id){document.getElementById(id).classList.add('open');}
function closeMod(id){document.getElementById(id).classList.remove('open');}
</script>
</body>
</html>
