import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    // Unfreeze here, not on close: resetting cardTop while the 200ms fade-out
    // still plays re-centers the card mid-fade (visible teleport). Between
    // close and the next open the frozen geometry is harmless — nothing
    // renders. Guarded so a re-route while open keeps its frozen top.
    if (!root.opened) {
      panel.cardTop = -1
      panel.maxRowsHeight = -1
    }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // ---- File/folder search tier (KRunner parity) ----
  // fd runs asynchronously per search keystroke (debounced); results land in
  // two phases (dirs, then files) and are appended below the menu matches.
  property var fileDirRows: []
  property var fileFileRows: []
  property string fileSearchPending: ""
  property int fileSearchSerial: 0
  property string fileSearchPhase: ""
  property string fileSearchQuery: ""
  // ---- Open-windows tier (KRunner parity) ----
  property var winRows: []
  property string winSearchPending: ""
  property var focusPending: null
  // ---- Baloo content tier (KRunner parity) ----
  property var fileContentRows: []
  property string contentSearchPending: ""
  property bool contentLivenessPending: false
  // ---- Recent documents + Dolphin places (KRunner parity) ----
  // Parsed from the two xbel files at open; a liveness pass (44% of recents
  // are dead paths) filters before any row is ever shown.
  property var recentsEntries: []
  property var placesEntries: []
  property var recentsLive: ({})
  property var liveDirs: ({})
  property bool recentsLanded: false
  property bool livenessPending: false
  // ---- Frecency (file + window tiers) ----
  property var frecency: ({})
  property bool frecencyLoaded: false
  readonly property string frecencyPath: Quickshell.env("HOME") + "/.local/state/omarchy/launcher-frecency.json"

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    var summon = MenuModel.summonAction(command)
    if (summon && root.shell && root.shell.summon(summon.id, summon.payload)) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (i > 0 && (row.section === "drilldown" || row.section === "files" || row.section === "windows") && previousSection !== row.section) total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        disabled: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  // ---- File/folder search (KRunner parity) ----
  // One reused Process runs fd in two chained phases (dirs, then files). The
  // serial bumped at every launch invalidates results of an older query; a
  // query queued while a run is in flight preempts the chain from its top.
  function requestFileSearch() {
    var query = root.filterText.trim()
    if (root.dmenuActive || query.length < 2 || root.answerQuery(query) === "forced") { root.clearFileSearch(); return }
    // Rows on screen belong to the last launched query. Keep them while it
    // stays compatible — one a prefix of the other, so both forward typing
    // and backspace ride the debounce smoothly — and drop them the moment
    // the edit can only have made them wrong (replacement, mid-word fix).
    var stored = root.fileSearchQuery
    if ((root.fileDirRows.length > 0 || root.fileFileRows.length > 0) && stored
        && query.indexOf(stored) !== 0 && stored.indexOf(query) !== 0) {
      root.clearFileSearch()
    }
    fileSearchTimer.restart()
  }

  function clearFileSearch() {
    fileSearchTimer.stop()
    root.fileSearchPending = ""
    root.fileSearchSerial += 1
    root.fileSearchPhase = ""
    root.fileSearchQuery = ""
    root.fileDirRows = []
    root.fileFileRows = []
    root.winRows = []
    root.winSearchPending = ""
    root.fileContentRows = []
    root.contentSearchPending = ""
  }

  function startFileSearch() {
    var query = root.filterText.trim()
    if (!root.opened || root.dmenuActive || query.length < 2) { root.clearFileSearch(); return }
    if (fileSearchProc.running) { root.fileSearchPending = query; return }
    root.launchFileSearch("dirs", query)
  }

  function launchFileSearch(phase, query) {
    root.fileSearchSerial += 1
    fileSearchProc.serial = root.fileSearchSerial
    fileSearchProc.collected = ""
    root.fileSearchPhase = phase
    root.fileSearchQuery = query
    // Absolute fd path: quickshell's Process ignores PATH. --fixed-strings +
    // --ignore-case keep the query literal and matches case-insensitive; fd
    // matches on the basename and skips hidden/gitignored paths by default.
    fileSearchProc.command = [
      "/usr/bin/fd", "--absolute-path", "--fixed-strings", "--ignore-case",
      "--max-results", phase === "dirs" ? "6" : "12",
      "--type", phase === "dirs" ? "directory" : "file",
      "--", query, Quickshell.env("HOME")
    ]
    fileSearchProc.running = true
  }

  readonly property var fileGlyphs: ({
    ".mp3": "󰈌", ".flac": "󰈌", ".ogg": "󰈌", ".m4a": "󰈌", ".wav": "󰈌",
    ".png": "󰋩", ".jpg": "󰋩", ".jpeg": "󰋩", ".gif": "󰋩", ".svg": "󰋩",
    ".mp4": "󰎔", ".mkv": "󰎔", ".webm": "󰎔", ".mov": "󰎔",
    ".pdf": "󰈔", ".txt": "󰈢", ".md": "󰈢", ".zip": "󰀪"
  })

  function fileGlyphFor(name, isDir) {
    if (isDir) return "󰉋"
    var dot = name.lastIndexOf(".")
    if (dot < 0) return "󰈟"
    return root.fileGlyphs[name.substring(dot).toLowerCase()] || "󰈟"
  }

  // Emits the FULL delegate role set — the delegate's required properties all
  // bind; one missing role = a broken row. Glyphs are precomputed by the
  // caller (isDir is not a row role).
  function actionRow(kind, icon, label, detail, target, score, section, appId) {
    return {
      itemId: kind + "." + target, disabled: false, kind: kind, icon: icon,
      iconFont: "", appIcon: "", appId: appId || "", label: label,
      target: target, detail: detail, path: "", childCount: 0, action: "",
      provider: "", score: score, section: section
    }
  }

  function fileRowFor(line, isDir, query) {
    var path = String(line || "")
    if (!path) return null
    // fd marks directories with a trailing slash. Strip it, or the basename
    // (text after the LAST slash) parses as empty and every folder row is
    // silently dropped.
    if (path.length > 1 && path.charAt(path.length - 1) === "/") path = path.slice(0, -1)
    var slash = path.lastIndexOf("/")
    var name = slash >= 0 ? path.substring(slash + 1) : path
    if (!name) return null
    var dirPart = slash > 0 ? path.substring(0, slash) : "/"
    var home = Quickshell.env("HOME")
    if (dirPart.indexOf(home) === 0) dirPart = "~" + dirPart.substring(home.length)
    var lowerName = name.toLowerCase()
    var needle = query.toLowerCase()
    var score = lowerName === needle ? 0 : (lowerName.indexOf(needle) === 0 ? 10 : 30)
    var depth = 0
    for (var c = 0; c < path.length; c++) if (path.charAt(c) === "/") depth += 1
    // Clamp the depth term: unclamped, a 40-slash path would reach the Baloo
    // content band (31000) and rank below content rows.
    return {
      itemId: "file." + path, parent: "root", kind: "file",
      icon: root.fileGlyphFor(name, isDir), label: name, target: path,
      detail: dirPart, score: score * 1000 + Math.min(depth, 20) * 25, isDir: isDir
    }
  }

  // ---- Calculator tier (KRunner parity) ----
  // "=<expression>" turns the launcher into a calculator: the result is the
  // top row and Enter copies it to the clipboard (wl-copy). Pure JS
  // recursive descent — no shell, no subprocess, instant on every keystroke.

  function calcTokenize(src) {
    var tokens = []
    var i = 0
    while (i < src.length) {
      var ch = src.charAt(i)
      if (ch === " " || ch === "\t") { i += 1; continue }
      if ((ch >= "0" && ch <= "9") || ch === ".") {
        var num = ""
        while (i < src.length && ((src.charAt(i) >= "0" && src.charAt(i) <= "9") || src.charAt(i) === ".")) {
          num += src.charAt(i)
          i += 1
        }
        if (num === "." || num.split(".").length > 2) return null
        tokens.push({ type: "num", value: Number(num) })
        continue
      }
      if ((ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z")) {
        var id = ""
        while (i < src.length && ((src.charAt(i) >= "a" && src.charAt(i) <= "z")
            || (src.charAt(i) >= "A" && src.charAt(i) <= "Z")
            || (src.charAt(i) >= "0" && src.charAt(i) <= "9") || src.charAt(i) === "_")) {
          id += src.charAt(i)
          i += 1
        }
        tokens.push({ type: "id", value: id })
        continue
      }
      if ("+-*/%^(),".indexOf(ch) >= 0) { tokens.push({ type: ch }); i += 1; continue }
      return null
    }
    return tokens
  }

  function calcEvaluate(src) {
    var tokens = calcTokenize(src)
    if (!tokens || tokens.length === 0) return null
    var pos = 0

    function peek() { return pos < tokens.length ? tokens[pos] : null }
    function take() { return pos < tokens.length ? tokens[pos++] : null }
    function isOp(t, op) { return t && t.type === op }

    var functions = ({
      sqrt: Math.sqrt, abs: Math.abs, sin: Math.sin, cos: Math.cos,
      tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
      ln: Math.log, log: Math.log10, exp: Math.exp, floor: Math.floor,
      ceil: Math.ceil, round: Math.round, min: Math.min, max: Math.max
    })
    var constants = ({ pi: Math.PI, e: Math.E, tau: 2 * Math.PI })

    function parseAdd() {
      var v = parseMul()
      if (v === null) return null
      while (isOp(peek(), "+") || isOp(peek(), "-")) {
        var op = take().type
        var r = parseMul()
        if (r === null) return null
        v = op === "+" ? v + r : v - r
      }
      return v
    }
    function parseMul() {
      var v = parseUnary()
      if (v === null) return null
      while (isOp(peek(), "*") || isOp(peek(), "/") || isOp(peek(), "%")) {
        var op = take().type
        var r = parseUnary()
        if (r === null) return null
        v = op === "*" ? v * r : (op === "/" ? v / r : v % r)
      }
      return v
    }
    function parseUnary() {
      if (isOp(peek(), "-")) { take(); var v = parseUnary(); return v === null ? null : -v }
      if (isOp(peek(), "+")) { take(); return parseUnary() }
      return parsePow()
    }
    function parsePow() {
      var base = parseAtom()
      if (base === null) return null
      if (isOp(peek(), "^")) {
        take()
        var exponent = parseUnary()
        if (exponent === null) return null
        return Math.pow(base, exponent)
      }
      return base
    }
    function parseAtom() {
      var t = take()
      if (!t) return null
      if (t.type === "num") return t.value
      if (t.type === "(") {
        var v = parseAdd()
        if (v === null || !isOp(take(), ")")) return null
        return v
      }
      if (t.type === "id") {
        var name = String(t.value).toLowerCase()
        if (isOp(peek(), "(")) {
          take()
          var args = []
          if (!isOp(peek(), ")")) {
            var first = parseAdd()
            if (first === null) return null
            args.push(first)
            while (isOp(peek(), ",")) {
              take()
              var nextArg = parseAdd()
              if (nextArg === null) return null
              args.push(nextArg)
            }
          }
          if (!isOp(take(), ")")) return null
          var fn = functions[name]
          if (!fn) return null
          var result = fn.apply(null, args)
          return isFinite(result) ? result : null
        }
        var constant = constants[name]
        return constant !== undefined ? constant : null
      }
      return null
    }

    var out = parseAdd()
    if (out === null || pos !== tokens.length) return null
    return isFinite(out) ? out : null
  }

  function calcFormat(value) {
    if (value === null || !isFinite(value)) return ""
    if (Math.abs(value) < 1e21 && Math.round(value) === value) return String(value)
    return String(Number(value.toPrecision(12)))
  }

  // ---- Shared answer classification (KRunner parity) ----
  // ONE policy, stated once: an explicit leading "=" is calc-EXCLUSIVE
  // (suppresses fd/web/windows/content); every auto-detected class coexists
  // with ALL tiers — including windows. The classes are mutually exclusive
  // by construction, so exactly one answer row can ever show.
  // NOTE: / inside a character class is legal ECMAScript (live-verified).
  function calcCandidate(query) {
    var q = String(query || "").trim()
    if (!q) return ""
    if (q.charAt(0) === "=") return q.substring(1).trim()
    if (/[0-9]/.test(q) && /[+\-*/%^(]/.test(q)) return q
    return ""
  }

  // "" = normal. "forced" = leading "=" (calc-exclusive, EVEN IF IT FAILS TO
  // PARSE — "=hello" must not run fd on the literal or grow a web row).
  // "calc" = auto-detected math that parses (coexists with all tiers).
  // Extended by the converter ("conv") and date/time ("date") answers below.
  function answerQuery(query) {
    var q = String(query || "").trim()
    if (!q) return ""
    if (q.charAt(0) === "=") return "forced"
    if (/[0-9]/.test(q) && /[+\-*/%^(]/.test(q) && root.calcEvaluate(q) !== null) return "calc"
    if (root.convertCandidate(q) !== "") return "conv"
    var lower = q.toLowerCase()
    if (lower === "date" || lower === "today" || lower === "time" || lower === "now" || lower === "heure") return "date"
    return ""
  }

  // ---- Unit converter (KRunner parity, pure JS) ----
  // ONE merged byte table (SI and IEC keys together — "1 gb in mib" is
  // well-defined and must convert). Every category checks that BOTH units
  // belong to it; a cross-category pair converts nothing. "b" is BYTES only
  // (no bits). Speed has no "ms" — milliseconds already own it in time.
  readonly property var unitTables: ({
    bytes: { b: 1, kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12,
             kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 },
    length: { mm: 0.001, cm: 0.01, m: 1, km: 1000, in: 0.0254, ft: 0.3048,
              yd: 0.9144, mi: 1609.344, nmi: 1852 },
    mass: { mg: 1e-6, g: 0.001, kg: 1, t: 1000,
            oz: 0.028349523125, lb: 0.45359237, st: 6.35029318 },
    time: { ms: 0.001, s: 1, min: 60, h: 3600, d: 86400, wk: 604800 },
    speed: { kmh: 1, mph: 1.609344, mps: 3.6, kn: 1.852 },
    temp: { c: 1, f: 1, k: 1 }
  })
  readonly property var unitAliases: ({
    pounds: "lb", lbs: "lb", ounce: "oz", ounces: "oz",
    gram: "g", grams: "g", kilogram: "kg", kilograms: "kg",
    kilometer: "km", kilometers: "km", kilometre: "km", kilometres: "km",
    meter: "m", meters: "m", metre: "m", metres: "m",
    centimeter: "cm", centimeters: "cm", centimetre: "cm", centimetres: "cm",
    millimeter: "mm", millimeters: "mm", millimetre: "mm", millimetres: "mm",
    mile: "mi", miles: "mi", foot: "ft", feet: "ft", inch: "in", inches: "in",
    yard: "yd", yards: "yd", hour: "h", hours: "h", minute: "min", minutes: "min",
    second: "s", seconds: "s", day: "d", days: "d", week: "wk", weeks: "wk",
    byte: "b", bytes: "b", kilobyte: "kb", kilobytes: "kb",
    megabyte: "mb", megabytes: "mb", gigabyte: "gb", gigabytes: "gb",
    terabyte: "tb", terabytes: "tb",
    millisecond: "ms", milliseconds: "ms", milligram: "mg", milligrams: "mg",
    knot: "kn", knots: "kn", nauticalmile: "nmi", nauticalmiles: "nmi",
    stone: "st", stones: "st", tonne: "t", tonnes: "t", ton: "t", tons: "t",
    celsius: "c", fahrenheit: "f", kelvin: "k", "°c": "c", "°f": "f", "°k": "k"
  })

  function normalizeUnit(token) {
    var u = String(token || "")
    if (u === "km/h") u = "kmh"
    else if (u === "m/s") u = "mps"
    var alias = root.unitAliases[u]
    return alias || u
  }

  function unitCategory(unit) {
    for (var category in root.unitTables) {
      if (root.unitTables[category].hasOwnProperty(unit)) return category
    }
    return ""
  }

  // "" = not a conversion. Returns the query's own unit spellings so the row
  // detail reads back what was typed.
  function convertCandidate(query) {
    var q = String(query || "").trim().toLowerCase()
    if (!q) return ""
    var m = /^([0-9]*\.?[0-9]+)\s*([a-z°µ/]+)\s+(?:in|to|en|as)\s+([a-z°µ/]+)$/.exec(q)
    if (!m) return ""
    var value = Number(m[1])
    if (!isFinite(value)) return ""
    var from = root.normalizeUnit(m[2])
    var to = root.normalizeUnit(m[3])
    var catFrom = root.unitCategory(from)
    var catTo = root.unitCategory(to)
    if (!catFrom || !catTo || catFrom !== catTo) return ""
    var result
    if (catFrom === "temp") {
      var celsius = from === "c" ? value : (from === "f" ? (value - 32) * 5 / 9 : value - 273.15)
      result = to === "c" ? celsius : (to === "f" ? celsius * 9 / 5 + 32 : celsius + 273.15)
    } else {
      var table = root.unitTables[catFrom]
      result = value * table[from] / table[to]
    }
    if (!isFinite(result)) return ""
    return { value: result, fromValue: m[1], fromText: m[2], toText: m[3] }
  }

  // Date/time answers ("date", "today", "time", "now", "heure") share the
  // calculator's answer slot — Enter copies what is shown.
  function isDateTimeQuery(query) {
    var lower = String(query || "").trim().toLowerCase()
    return lower === "date" || lower === "today" || lower === "time"
      || lower === "now" || lower === "heure"
  }

  // Frecency hit count for a key (files: absolute path; windows:
  // "class:" + class), capped — a frequently opened item can only ever
  // outrank, never dominate. 0 until the state file has been adopted.
  // ---- Baloo content tier (KRunner parity) ----
  // baloosearch6 answers in ~20 ms against the live index; a no-match is
  // empty stdout + exit 0. Same pending pattern as the fd and window runs.
  function startContentSearch() {
    var query = root.filterText.trim()
    if (!root.opened || root.dmenuActive || query.length < 2
        || root.answerQuery(query) === "forced") return
    if (contentProc.running) { root.contentSearchPending = query; return }
    root.launchContentSearch(query)
  }

  function launchContentSearch(query) {
    contentProc.collected = ""
    contentProc.query = query
    // -l 24, not 8: -l 8 starves after dedupe (live-measured: 8 → 2 unique
    // paths, 24 → 6); final rows cap at 8 in contentRowsFor.
    contentProc.command = ["/usr/sbin/baloosearch6", "-l", "24", query]
    contentProc.running = true
    contentWatchdog.restart()
  }

  // Baloo's index lags moves and deletes — a stale hit used to rank a dead
  // path. Rows are capped at 8, so one tiny existence check settles them
  // before anything is shown (same protocol as the recents liveness pass).
  function launchContentLiveness(rows) {
    var paths = []
    for (var i = 0; i < rows.length; i++) paths.push(rows[i].target)
    contentLivenessProc.collected = ""
    contentLivenessProc.pendingRows = rows
    contentLivenessProc.command = ["/usr/bin/bash", "-c",
      'for p in "$@"; do [[ -e "$p" ]] && printf "f%s\\n" "$p"; done',
      "bash"].concat(paths)
    contentLivenessProc.running = true
    contentLivenessWatchdog.restart()
  }

  function contentRowsFor(raw) {
    var lines = String(raw || "").split("\n")
    var rows = []
    var seen = ({})
    for (var i = 0; i < lines.length && rows.length < 8; i++) {
      var path = lines[i].trim()
      if (!path || path.charAt(0) !== "/") continue
      // baloosearch6 can list a directory with a trailing slash; strip it or
      // the basename parses empty and the row is silently dropped.
      if (path.length > 1 && path.charAt(path.length - 1) === "/") path = path.slice(0, -1)
      if (seen[path]) continue
      seen[path] = true
      var slash = path.lastIndexOf("/")
      var name = slash >= 0 ? path.substring(slash + 1) : path
      if (!name) continue
      var dirPart = slash > 0 ? path.substring(0, slash) : "/"
      var home = Quickshell.env("HOME")
      if (dirPart.indexOf(home) === 0) dirPart = "~" + dirPart.substring(home.length)
      rows.push(root.actionRow("file", root.fileGlyphFor(name, false), name,
        dirPart + "  ·  content", path, 31000, "", ""))
    }
    return rows
  }

  // ---- Recent documents + Dolphin places (KRunner parity) ----
  // Both sources are trusted local files but parsed by pure regex attribute
  // extraction only — no XML engine, no DOCTYPE/ENTITY processing anywhere.
  // XML-unescape the href BEFORE percent-decoding (17 of ~300 hrefs carry
  // entities; decoding first would corrupt them into dead paths).
  function unescapeXml(value) {
    return String(value)
      .replace(/&lt;/g, "<").replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"").replace(/&apos;/g, "'")
      .replace(/&amp;/g, "&")
  }

  function dirPartFor(path) {
    var slash = path.lastIndexOf("/")
    var dirPart = slash > 0 ? path.substring(0, slash) : "/"
    var home = Quickshell.env("HOME")
    if (dirPart.indexOf(home) === 0) dirPart = "~" + dirPart.substring(home.length)
    return dirPart
  }

  function parseRecents(raw) {
    var entries = []
    var re = /<bookmark\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/bookmark>/g
    var match
    while ((match = re.exec(String(raw || ""))) !== null) {
      try {
        var href = root.unescapeXml(match[1])
        if (href.indexOf("file://") !== 0) continue
        var path = decodeURIComponent(href.substring(7))
        if (!path || path.indexOf("/Trash/") >= 0) continue
        // The liveness report is a line protocol — a newline inside a path
        // would corrupt it into junk keys, so such entries are dropped.
        if (path.indexOf("\n") >= 0) continue
        var slash = path.lastIndexOf("/")
        var name = slash >= 0 ? path.substring(slash + 1) : path
        if (!name) continue
        var titleMatch = /<title>([\s\S]*?)<\/title>/.exec(match[2])
        // `modified` lives in the opening tag — the full match can contain
        // other timestamps in the metadata children.
        var openingTag = match[0].substring(0, match[0].indexOf(">") + 1)
        var modifiedMatch = /modified="([^"]*)"/.exec(openingTag)
        entries.push({
          path: path, name: name,
          title: titleMatch ? titleMatch[1].trim() : "",
          dirPart: root.dirPartFor(path),
          modified: modifiedMatch ? modifiedMatch[1] : ""
        })
      } catch (e) { }
    }
    // File order is NOT chronological — this sort is load-bearing (newest
    // first wins the top slots).
    entries.sort(function(a, b) {
      if (a.modified === b.modified) return 0
      return a.modified < b.modified ? 1 : -1
    })
    return entries
  }

  function parsePlaces(raw) {
    var entries = []
    var re = /<bookmark\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/bookmark>/g
    var match
    while ((match = re.exec(String(raw || ""))) !== null) {
      try {
        var href = root.unescapeXml(match[1])
        if (href.indexOf("file://") !== 0) continue
        var path = decodeURIComponent(href.substring(7))
        if (!path || path.indexOf("/Trash/") >= 0) continue
        if (path.indexOf("\n") >= 0) continue
        var slash = path.lastIndexOf("/")
        var name = slash >= 0 ? path.substring(slash + 1) : path
        if (!name) continue
        // Places titles live in the <title> child — a basename fallback
        // would show "ravi" for Home.
        var titleMatch = /<title>([\s\S]*?)<\/title>/.exec(match[2])
        entries.push({
          path: path, name: name,
          title: titleMatch ? titleMatch[1].trim() : "",
          dirPart: root.dirPartFor(path)
        })
      } catch (e) { }
    }
    return entries
  }

  // Recents (≤5, newest first) then places (≤3), matched on title or
  // basename, only paths the liveness pass proved exist. Until that pass
  // lands, NO recent rows are shown — never a dead one.
  // Two bands per group: a match that PREFIXES the label or the basename
  // leads the whole file tier (negative score), while a substring-only match
  // falls between fd's prefix band (≤10 500) and fd's substring band
  // (≥30 000) — so a mere substring hit can never outrank a real basename
  // match ("log" leads with log.md, not service-logout.oga). Prefix matches
  // claim the limited slots first; substring matches only fill what is left.
  function recentBandRows(entries, limit, leadBase, subBase, lower, seen) {
    var leads = []
    var subs = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!root.recentsLive[entry.path]) continue
      if (seen[entry.path]) continue
      var label = entry.title || entry.name
      var lowerLabel = label.toLowerCase()
      var lowerName = entry.name.toLowerCase()
      if (lower && lowerLabel.indexOf(lower) < 0 && lowerName.indexOf(lower) < 0) continue
      seen[entry.path] = true
      var row = root.actionRow("file",
        root.fileGlyphFor(entry.name, root.liveDirs[entry.path] === true),
        label, entry.dirPart, entry.path, 0, "", "")
      if (!lower || lowerLabel.indexOf(lower) === 0 || lowerName.indexOf(lower) === 0) {
        if (leads.length < limit) { row.score = leadBase + leads.length; leads.push(row) }
      } else if (subs.length < limit) {
        row.score = subBase + subs.length
        subs.push(row)
      }
    }
    for (var s = 0; s < subs.length && leads.length < limit; s++) leads.push(subs[s])
    return leads
  }

  function recentPlaceRows(query) {
    if (!root.recentsLanded) return []
    var lower = String(query || "").toLowerCase()
    var seen = ({})
    return root.recentBandRows(root.recentsEntries, 5, -500, 20000, lower, seen)
      .concat(root.recentBandRows(root.placesEntries, 3, -400, 20100, lower, seen))
  }

  function refreshRecentSources() {
    recentsFile.reload()
    placesFile.reload()
    // Both reloads land within milliseconds; one liveness pass covers them.
    recentsSyncTimer.restart()
  }

  function startLivenessCheck() {
    if (livenessProc.running) { root.livenessPending = true; return }
    var paths = []
    var seen = ({})
    // recentsEntries is modified-DESC sorted — the cap keeps the newest.
    var recents = root.recentsEntries.length > 400 ? root.recentsEntries.slice(0, 400) : root.recentsEntries
    for (var i = 0; i < recents.length; i++) {
      if (!seen[recents[i].path]) { seen[recents[i].path] = true; paths.push(recents[i].path) }
    }
    for (var p = 0; p < root.placesEntries.length; p++) {
      if (!seen[root.placesEntries[p].path]) {
        seen[root.placesEntries[p].path] = true
        paths.push(root.placesEntries[p].path)
      }
    }
    if (paths.length === 0) {
      root.recentsLive = ({})
      root.liveDirs = ({})
      root.recentsLanded = true
      if (root.opened && !root.dmenuActive) root.rebuildDisplay()
      return
    }
    // ≤400 paths ≈ 24 KB argv, safe. The d/f prefix doubles as the dir flag
    // for row glyphs.
    livenessProc.collected = ""
    livenessProc.command = ["/usr/bin/bash", "-c",
      'for p in "$@"; do if [[ -d "$p" ]]; then printf "d%s\\n" "$p"; elif [[ -e "$p" ]]; then printf "f%s\\n" "$p"; fi; done',
      "bash"].concat(paths)
    livenessProc.running = true
    livenessWatchdog.restart()
  }

  function frecencyCount(key) {
    if (!root.frecencyLoaded) return 0
    var rec = root.frecency[key]
    return rec && rec.c ? Math.min(rec.c, 10) : 0
  }

  // FileView semantics (live-verified): a MISSING path fires ONLY
  // onLoadFailed — the gate must open on BOTH signals or frecency never
  // records on a fresh machine.
  function adoptFrecency(raw) {
    var next = ({})
    try { next = JSON.parse(raw || "{}") || ({}) } catch (e) { next = ({}) }
    root.frecency = next
    root.frecencyLoaded = true
  }

  // No-op until frecencyLoaded — a pre-load activation would otherwise write
  // {} over history. setText creates the file AND parent dirs; no shell, no
  // quoting.
  function recordFrecency(key) {
    if (!root.frecencyLoaded || !key) return
    var next = ({})
    for (var existing in root.frecency) next[existing] = root.frecency[existing]
    var rec = next[key] || { c: 0, t: 0 }
    next[key] = { c: (rec.c || 0) + 1, t: Date.now() }
    var keys = Object.keys(next)
    if (keys.length > 300) {
      keys.sort(function(x, y) { return (next[x].t || 0) - (next[y].t || 0) })
      while (keys.length > 300) delete next[keys.shift()]
    }
    root.frecency = next
    frecencyFile.setText(JSON.stringify(next))
  }

  // ---- Open-windows tier (KRunner parity) ----
  // hyprctl clients -j runs per search keystroke (same debounce as fd).
  // Focus happens through the ravi-window-focus wrapper: Wave-7 lua
  // dispatch only — legacy focuswindow text parse-errors, and a missing
  // window returns rc=0 with a warning, so the script matches the "ok"
  // string instead of exit codes.
  function startWindowSearch() {
    var query = root.filterText.trim()
    if (!root.opened || root.dmenuActive || query.length < 2
        || root.answerQuery(query) === "forced") return
    if (winSearchProc.running) { root.winSearchPending = query; return }
    root.launchWindowSearch(query)
  }

  function launchWindowSearch(query) {
    winSearchProc.collected = ""
    winSearchProc.query = query
    winSearchProc.command = ["/usr/bin/hyprctl", "clients", "-j"]
    winSearchProc.running = true
    winSearchWatchdog.restart()
  }

  function windowRowsFor(raw, query) {
    var clients = []
    try { clients = JSON.parse(raw || "[]") || [] } catch (e) { clients = [] }
    var needle = String(query || "").toLowerCase()
    var candidates = []
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      var title = String(c.title || "")
      var cls = String(c.class || "")
      var initial = String(c.initialClass || "")
      if (title.toLowerCase().indexOf(needle) < 0
          && cls.toLowerCase().indexOf(needle) < 0
          && initial.toLowerCase().indexOf(needle) < 0) continue
      var ws = c.workspace || {}
      var wsName = String(ws.name || "")
      // Special workspaces (scratchpads) are not part of the normal flow.
      if (wsName.indexOf("special") >= 0) continue
      // The mapped field exists on this compositor (probed): an unmapped
      // client is not a window the user can go to.
      if (c.mapped === false) continue
      var address = String(c.address || "")
      if (!address) continue
      var wsId = Number(ws.id)
      if (!isFinite(wsId)) wsId = 0
      candidates.push({
        title: title, cls: cls, wsId: wsId,
        wsLabel: wsName || String(wsId), address: address
      })
    }
    // Base order: frecency-boosted classes first (Wave C hook, capped),
    // then workspace ascending, then title alpha.
    candidates.sort(function(a, b) {
      var boostA = root.frecencyCount("class:" + a.cls) * 25
      var boostB = root.frecencyCount("class:" + b.cls) * 25
      if (boostA !== boostB) return boostB - boostA
      if (a.wsId !== b.wsId) return a.wsId - b.wsId
      var titleA = a.title.toLowerCase()
      var titleB = b.title.toLowerCase()
      if (titleA !== titleB) return titleA.localeCompare(titleB)
      return a.address.localeCompare(b.address)
    })
    var rows = []
    var cap = Math.min(candidates.length, 8)
    for (var j = 0; j < cap; j++) {
      var win = candidates[j]
      rows.push(root.actionRow("window", "󰓞", win.title || win.cls,
        win.cls + "  ·  workspace " + win.wsLabel, win.address, 9000 + j, "", win.cls))
    }
    return rows
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` or `disabled:` evaluated
  // truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults, root.disabledResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  // Rows whose `disabled:` evaluated truthy stay listed but dimmed, and the
  // cursor steps over them.
  function isDisabled(entry) {
    return MenuModel.isDisabled(root.disabledResults, entry)
  }

  // A disabled row earns its place in the submenu it belongs to, where the
  // list around it is the point. Search is a list of what you can do, so it
  // leaves them out.
  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry) && !root.isDisabled(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, root.disabledResults, entry, detail, score, section)
  }

  function rowSelectable(index) {
    if (index < 0 || index >= displayModel.count) return false
    return !displayModel.get(index).disabled
  }

  // First selectable row at or past `from`, continuing in the direction of
  // travel and wrapping. -1 when every row is disabled, which leaves the menu
  // with no cursor at all rather than one parked on a row Enter won't run.
  function nextSelectable(from, direction) {
    var count = displayModel.count
    if (count === 0) return -1

    var step = direction < 0 ? -1 : 1
    var index = ((from % count) + count) % count
    for (var i = 0; i < count; i++) {
      if (root.rowSelectable(index)) return index
      index = (index + step + count) % count
    }

    return -1
  }

  // Park the cursor on a selectable row after the rows underneath it changed.
  // A menu with nothing selectable in it -- every app in it already installed
  // -- shows no cursor at all, and grows one the moment a row can take it.
  function settleCursor() {
    var target = root.nextSelectable(root.selectedIndex, 1)
    root.selectedIndex = target >= 0 ? target : 0
    root.cursorActive = target >= 0
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        disabled: false,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    // Async tiers append below the cursor row, but recents can insert above
    // it — remember what the cursor is on by identity so the rebuild can
    // re-find it instead of sliding the selection onto a different row.
    var anchorId = root.cursorActive && root.selectedIndex >= 0
      && root.selectedIndex < displayModel.count ? displayModel.get(root.selectedIndex).itemId : ""

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)

      // Windows tier (KRunner parity): open windows matching the query sit
      // between the menu matches and the file tier. Qt sections require
      // contiguity — one contiguous block, no divider above a first row.
      if (root.winRows.length > 0) {
        var winSection = rows.length > 0 ? "windows" : ""
        for (var wi = 0; wi < root.winRows.length; wi++) {
          var winRow = root.winRows[wi]
          rows.push(root.actionRow(winRow.kind, winRow.icon, winRow.label,
            winRow.detail, winRow.target, winRow.score, winSection, winRow.appId))
        }
      }

      // File/folder tier (KRunner parity): recents/places lead (distinct
      // score bands below zero), then fd results, then Baloo content hits —
      // every tier deduped by target, recents winning. The row shape mirrors
      // displayRow's output with target kept as the real path — displayRow
      // would overwrite it with itemId.
      var fileHits = root.answerQuery(query) === "forced" ? [] : root.recentPlaceRows(query)
      var seenTargets = ({})
      for (var rp = 0; rp < fileHits.length; rp++) seenTargets[fileHits[rp].target] = true
      var fdHits = root.fileDirRows.concat(root.fileFileRows)
      for (var fi = 0; fi < fdHits.length; fi++) {
        if (seenTargets[fdHits[fi].target]) continue
        seenTargets[fdHits[fi].target] = true
        fileHits.push(fdHits[fi])
      }
      for (var ci = 0; ci < root.fileContentRows.length; ci++) {
        if (seenTargets[root.fileContentRows[ci].target]) continue
        seenTargets[root.fileContentRows[ci].target] = true
        fileHits.push(root.fileContentRows[ci])
      }
      if (fileHits.length > 0) {
        // Effective score = stored score minus the capped frecency hit count
        // ×25: score bands are ≥1000 apart, so 10 hits (max −250) can jump
        // ~10 same-band ranks yet never cross a band; raw counts could only
        // reorder exact ties. Stored scores are never mutated.
        fileHits.sort(function(a, b) {
          var effA = a.score - root.frecencyCount(a.target) * 25
          var effB = b.score - root.frecencyCount(b.target) * 25
          if (effA !== effB) return effA - effB
          if (a.isDir !== b.isDir) return a.isDir ? -1 : 1
          var aLabel = a.label.toLowerCase()
          var bLabel = b.label.toLowerCase()
          if (aLabel !== bLabel) return aLabel.localeCompare(bLabel)
          return a.target.localeCompare(b.target)
        })
        var fileSection = rows.length > 0 ? "files" : ""
        for (var fh = 0; fh < fileHits.length; fh++) {
          var hit = fileHits[fh]
          rows.push({
            itemId: hit.itemId,
            disabled: false,
            kind: "file",
            icon: hit.icon,
            iconFont: "",
            appIcon: "",
            appId: "",
            label: hit.label,
            target: hit.target,
            detail: hit.detail,
            path: "",
            childCount: 0,
            action: "",
            provider: "",
            score: hit.score,
            section: fileSection
          })
        }
      }

      // Answer row (calculator, converter, date/time): "=expression"
      // answers forcibly and suppresses every other tier; auto-detected
      // answers coexist with files/windows below. Enter copies the result.
      var calcExpr = root.calcCandidate(query)
      var calcValue = calcExpr ? root.calcEvaluate(calcExpr) : null
      if (calcValue !== null) {
        rows.unshift({
          itemId: "calc.result",
          disabled: false,
          kind: "calc",
          icon: "",
          iconFont: "",
          appIcon: "",
          appId: "",
          label: root.calcFormat(calcValue),
          target: root.calcFormat(calcValue),
          detail: (query.charAt(0) === "=" ? "= " : "") + calcExpr + "  ·  Enter copies",
          path: "",
          childCount: 0,
          action: "",
          provider: "",
          score: 0,
          section: ""
        })
      } else {
        var conv = root.convertCandidate(query)
        if (conv !== "") {
          rows.unshift({
            itemId: "calc.result",
            disabled: false,
            kind: "calc",
            icon: "",
            iconFont: "",
            appIcon: "",
            appId: "",
            label: root.calcFormat(conv.value) + " " + conv.toText,
            target: root.calcFormat(conv.value),
            detail: conv.fromValue + " " + conv.fromText + "  ·  Enter copies",
            path: "",
            childCount: 0,
            action: "",
            provider: "",
            score: 0,
            section: ""
          })
        } else if (root.isDateTimeQuery(query)) {
          var timeLike = ["time", "now", "heure"].indexOf(query.trim().toLowerCase()) >= 0
          var stamped = Qt.formatDateTime(new Date(), timeLike ? "hh:mm:ss" : "dddd, d MMMM yyyy")
          rows.unshift({
            itemId: "calc.result",
            disabled: false,
            kind: "calc",
            icon: "",
            iconFont: "",
            appIcon: "",
            appId: "",
            label: stamped,
            target: stamped,
            detail: "Enter copies",
            path: "",
            childCount: 0,
            action: "",
            provider: "",
            score: 0,
            section: ""
          })
        }
      }

      // Web-search fallback (KRunner's web runner): always the last row, so a
      // query the machine can't answer is one Enter away from the browser.
      if (root.answerQuery(query) !== "forced" && query.length >= 2) {
        rows.push({
          itemId: "web.search",
          disabled: false,
          kind: "web",
          icon: "",
          iconFont: "",
          appIcon: "",
          appId: "",
          label: "Search the web for \u201C" + query + "\u201D",
          target: "https://duckduckgo.com/?q=" + encodeURIComponent(query),
          detail: "DuckDuckGo",
          path: "",
          childCount: 0,
          action: "",
          provider: "",
          score: 0,
          section: ""
        })
      }
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    root.settleCursor()

    // The row the cursor sat on keeps it even when the rebuild moved it.
    if (anchorId) {
      for (var an = 0; an < displayModel.count; an++) {
        if (displayModel.get(an).itemId === anchorId) { root.selectedIndex = an; break }
      }
    }

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    var from = cursorActive ? selectedIndex + delta : (delta < 0 ? displayModel.count - 1 : 0)
    var target = root.nextSelectable(from, delta)
    if (target < 0) return

    cursorActive = true
    selectedIndex = target
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    root.requestFileSearch()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.clearFileSearch()
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (!root.rowSelectable(index)) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.clearFileSearch()
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else if (row.kind === "file") {
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.clearFileSearch()
      root.recordFrecency(row.target)
      Util.execArgv(["xdg-open", row.target])
    } else if (row.kind === "window") {
      // Focus runs through a Process so the outcome is observable: the
      // wrapper exits non-zero when the window is gone, and frecency only
      // records a focus that actually happened.
      var winKey = "class:" + row.appId
      if (focusProc.running) root.focusPending = { address: row.target, key: winKey }
      else root.launchWindowFocus(row.target, winKey)
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.clearFileSearch()
    } else if (row.kind === "calc") {
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.clearFileSearch()
      Util.execDetached("printf %s " + Util.shellQuote(row.target) + " | /usr/sbin/wl-copy")
    } else if (row.kind === "web") {
      applySerial = requestSerial
      opened = false
      filterText = ""
      root.clearFileSearch()
      Util.execArgv(["xdg-open", row.target])
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.clearFileSearch()
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.clearFileSearch()
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
    root.clearFileSearch()
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    root.clearFileSearch()
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    // Recents/places: re-parse + re-check liveness on every open; until the
    // check lands, no recent rows are shown.
    root.recentsLanded = false
    root.refreshRecentSources()
    opened = true
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    root.clearFileSearch()
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  // Right-click on a file/folder row copies its absolute path and confirms
  // with a toast. Fires directly on the click — no context menu, and only
  // file rows: apps, windows, answers and web rows do nothing.
  function copyRowPath(path) {
    Util.execDetached("printf %s " + Util.shellQuote(path) + " | /usr/sbin/wl-copy")
    root.showToast()
  }

  // The confirmation popup carries no payload — the clipboard already has the
  // full path, and a second line of path text only made the pill harder to read.
  function showToast() {
    pathCopiedToast.opacity = 1
    pathCopiedHide.restart()
  }

  // Enter on a window row focuses through the wrapper Process; frecency is
  // recorded only on success, and a dead window says so via notification —
  // the menu is already closed, so an in-panel toast would never be seen.
  function launchWindowFocus(address, frecencyKey) {
    focusProc.frecencyKey = frecencyKey
    focusProc.command = [Quickshell.env("HOME") + "/.local/bin/ravi-window-focus", address]
    focusProc.running = true
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    if (!root.rowSelectable(index)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Timer {
    id: fileSearchTimer
    interval: 180
    onTriggered: {
      root.startFileSearch()
      root.startWindowSearch()
      root.startContentSearch()
    }
  }

  Process {
    id: fileSearchProc
    property int serial: 0
    // String accumulation, not an array: in-place writes into a QML var
    // property are occasionally dropped by the engine (see MenuModel.js),
    // and a dropped search line is a silently missing result.
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { fileSearchProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A newer query queued mid-run preempts the chain from the top: its
      // predecessor's results are never stored and the dirs phase restarts.
      if (root.fileSearchPending) {
        var nextQuery = root.fileSearchPending
        root.fileSearchPending = ""
        root.launchFileSearch("dirs", nextQuery)
        return
      }
      if (fileSearchProc.serial !== root.fileSearchSerial) return

      var phase = root.fileSearchPhase
      var query = root.fileSearchQuery
      var hits = []
      var lines = fileSearchProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var row = root.fileRowFor(lines[i], phase === "dirs", query)
        if (row) hits.push(row)
      }
      if (phase === "dirs") root.fileDirRows = hits
      else root.fileFileRows = hits
      if (root.opened && !root.dmenuActive) root.rebuildDisplay()
      if (phase === "dirs") root.launchFileSearch("files", query)
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  Process {
    id: focusProc
    property string frecencyKey: ""
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) {
        root.recordFrecency(focusProc.frecencyKey)
      } else {
        Util.execDetached("notify-send -u normal " + Util.shellQuote("Window not found")
          + " " + Util.shellQuote("It closed before Enter landed — search for it again."))
      }
      if (root.focusPending) {
        var next = root.focusPending
        root.focusPending = null
        root.launchWindowFocus(next.address, next.key)
      }
    }
  }

  Process {
    id: winSearchProc
    property string collected: ""
    property string query: ""
    stdout: SplitParser {
      onRead: function(data) { winSearchProc.collected += data + "\n" }
    }
    onExited: {
      winSearchWatchdog.stop()
      // A newer query queued mid-run relaunches from the top; the older
      // run's output is never stored.
      if (root.winSearchPending) {
        var nextQuery = root.winSearchPending
        root.winSearchPending = ""
        root.launchWindowSearch(nextQuery)
        return
      }
      if (winSearchProc.query !== root.filterText.trim()) return
      root.winRows = root.windowRowsFor(winSearchProc.collected, winSearchProc.query)
      if (root.opened && !root.dmenuActive) root.rebuildDisplay()
    }
  }

  Timer {
    id: winSearchWatchdog
    interval: 4000
    // hyprctl clients answers in milliseconds; 4 s means something is wedged.
    onTriggered: if (winSearchProc.running) {
      console.warn("[krunner2] window-search watchdog fired — hyprctl clients wedged over 4s")
      winSearchProc.running = false
    }
  }

  Process {
    id: contentProc
    property string collected: ""
    property string query: ""
    stdout: SplitParser {
      onRead: function(data) { contentProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      contentWatchdog.stop()
      if (root.contentSearchPending) {
        var nextQuery = root.contentSearchPending
        root.contentSearchPending = ""
        root.launchContentSearch(nextQuery)
        return
      }
      if (contentProc.query !== root.filterText.trim()) return
      // baloosearch6 exits 0 on a clean no-match; a killed run's partial
      // output must not pose as the index's answer — keep the last set.
      if (exitCode !== 0 || exitStatus !== 0) return
      var rows = root.contentRowsFor(contentProc.collected)
      if (rows.length === 0) {
        root.fileContentRows = []
        if (root.opened && !root.dmenuActive) root.rebuildDisplay()
        return
      }
      if (contentLivenessProc.running) {
        contentLivenessProc.stashedRows = rows
        root.contentLivenessPending = true
        return
      }
      root.launchContentLiveness(rows)
    }
  }

  Timer {
    id: contentWatchdog
    interval: 4000
    onTriggered: if (contentProc.running) {
      console.warn("[krunner2] content watchdog fired — baloosearch6 wedged over 4s")
      contentProc.running = false
    }
  }

  Process {
    id: contentLivenessProc
    property string collected: ""
    property var pendingRows: []
    property var stashedRows: []
    stdout: SplitParser {
      onRead: function(data) { contentLivenessProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      contentLivenessWatchdog.stop()
      var live = ({})
      if (exitCode === 0 && exitStatus === 0) {
        var lines = contentLivenessProc.collected.split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].charAt(0) === "f") live[lines[i].substring(1)] = true
        }
      }
      // A killed check verifies nothing: show only rows the check confirmed,
      // never Baloo's possibly-stale word alone.
      var rows = []
      for (var r = 0; r < contentLivenessProc.pendingRows.length; r++) {
        if (live[contentLivenessProc.pendingRows[r].target]) rows.push(contentLivenessProc.pendingRows[r])
      }
      root.fileContentRows = rows
      if (root.opened && !root.dmenuActive) root.rebuildDisplay()
      if (root.contentLivenessPending) {
        root.contentLivenessPending = false
        root.launchContentLiveness(contentLivenessProc.stashedRows)
      }
    }
  }

  Timer {
    id: contentLivenessWatchdog
    interval: 4000
    onTriggered: if (contentLivenessProc.running) {
      console.warn("[krunner2] content-liveness watchdog fired — existence check wedged over 4s")
      contentLivenessProc.running = false
    }
  }

  Process {
    id: livenessProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { livenessProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      livenessWatchdog.stop()
      // Killed rather than finished (watchdog): a partial live set would
      // mark every unreached path dead — keep the last complete set and
      // land without rows instead. A signal leaves the exit code at 0, so
      // the status is what tells us (same rule as guardProc).
      if (exitCode !== 0 || exitStatus !== 0) {
        root.recentsLanded = true
        if (root.livenessPending) {
          root.livenessPending = false
          root.startLivenessCheck()
        }
        return
      }
      var nextLive = ({})
      var nextDirs = ({})
      var lines = livenessProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (!line) continue
        if (line.charAt(0) === "d") {
          nextLive[line.substring(1)] = true
          nextDirs[line.substring(1)] = true
        } else if (line.charAt(0) === "f") {
          nextLive[line.substring(1)] = true
        }
      }
      root.recentsLive = nextLive
      root.liveDirs = nextDirs
      root.recentsLanded = true
      if (root.opened && !root.dmenuActive) root.rebuildDisplay()
      // The menu reopened while the check was running — run it again so the
      // rows match what is on screen now (a command change mid-run is
      // silently ignored by Process).
      if (root.livenessPending) {
        root.livenessPending = false
        root.startLivenessCheck()
      }
    }
  }

  Timer {
    id: livenessWatchdog
    interval: 4000
    onTriggered: if (livenessProc.running) {
      console.warn("[krunner2] liveness watchdog fired — existence check wedged over 4s")
      livenessProc.running = false
    }
  }

  Timer {
    id: recentsSyncTimer
    interval: 250
    onTriggered: root.startLivenessCheck()
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // Recents/places sources: re-read at every open (watchChanges false — the
  // reload is explicit), parsed on load. The liveness pass that follows is
  // driven by refreshRecentSources()'s sync timer.
  FileView {
    id: recentsFile
    path: Quickshell.env("HOME") + "/.local/share/recently-used.xbel"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.recentsEntries = root.parseRecents(text())
      // Re-arm the sync debounce when a parse actually lands, so a slow
      // reload never misses the liveness pass (the 250 ms kick from
      // refreshRecentSources alone could fire before the parse).
      if (root.opened) recentsSyncTimer.restart()
    }
    onLoadFailed: root.recentsEntries = []
  }

  FileView {
    id: placesFile
    path: Quickshell.env("HOME") + "/.local/share/user-places.xbel"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.placesEntries = root.parsePlaces(text())
      if (root.opened) recentsSyncTimer.restart()
    }
    onLoadFailed: root.placesEntries = []
  }

  // Frecency state: read once at startup (a missing file opens the gate via
  // onLoadFailed), written atomically by recordFrecency. Single-writer by
  // assumption — the file belongs to the one live shell instance; two
  // quickshell instances would last-writer-wins over each other.
  FileView {
    id: frecencyFile
    path: root.frecencyPath
    printErrors: false
    atomicWrites: true
    onLoaded: root.adoptFrecency(text())
    onLoadFailed: root.adoptFrecency("")
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property var disabledResults: ({})   // id → true|false (dim, skip cursor)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      root.disabledResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var nextDisabled = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
        else if (tag === "d") nextDisabled[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      root.disabledResults = nextDisabled
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
      if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }
  OverlayWindow {
    id: panel
    shown: root.opened && root.rowsLoaded
    WlrLayershell.namespace: "omarchy-menu"

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Opening unfreezes both (resetting on close
    // would re-center the card mid-fade — see open()).
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (shown && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    // The surface stays mapped between opens, so closing is shown going false.
    // Geometry deliberately NOT reset here: the fade-out still plays, and an
    // instant unfreeze would re-center the card mid-fade. open() resets.

    // Fedora port (2026-10-03): the scrim fades in/out here in QML. The
    // compositor's `layers` animation is geometry-only (slide from this
    // surface's top-left anchor) and its fade style changed nothing on
    // 0.56.2, so the transition lives here with the layers animation
    // disabled in hyprland.conf.
    Rectangle {
      anchors.fill: parent
      color: root.scrim
      opacity: panel.shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      // Fedora port (2026-10-03): the card fades with the scrim (see the
      // Rectangle above).
      opacity: panel.shown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      // "Path copied!" confirmation for right-click on a file/folder row.
      // A plain Rectangle takes no input, so it never blocks the rows under
      // it while visible.
      Rectangle {
        id: pathCopiedToast
        opacity: 0
        visible: opacity > 0
        z: 30
        width: pathCopiedLabel.implicitWidth + Style.space(28)
        height: Math.max(Style.space(32), pathCopiedLabel.implicitHeight + Style.space(12))
        radius: root.cornerRadius
        color: root.selectedBackground
        border.color: root.selectedBorder
        border.width: 1
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.headerHeight + Style.space(10)
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Timer {
          id: pathCopiedHide
          interval: 1400
          onTriggered: pathCopiedToast.opacity = 0
        }

        Text {
          id: pathCopiedLabel
          text: "Path copied!"
          textFormat: Text.PlainText
          anchors.centerIn: parent
          color: root.selectedText
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                     && (event.modifiers & Qt.ControlModifier) && !root.dmenuActive
                     && root.cursorActive && displayModel.count > 0) {
            // Reveal the picked file row's containing folder (KRunner's
            // secondary action); any other row activates like plain Return.
            var revealRow = displayModel.get(root.selectedIndex)
            if (revealRow && revealRow.kind === "file" && revealRow.target) {
              var slashAt = revealRow.target.lastIndexOf("/")
              applySerial = requestSerial
              opened = false
              filterText = ""
              root.clearFileSearch()
              Util.execArgv(["xdg-open", slashAt > 0 ? revealRow.target.substring(0, slashAt) : "/"])
            } else {
              root.activateIndex(root.selectedIndex)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else root.settleCursor()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…"))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: (section === "drilldown" || section === "files" || section === "windows") ? root.dividerHeight : 0
              visible: section === "drilldown" || section === "files" || section === "windows"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount
              required property bool disabled

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              // Faded: the row is here to say the software is already
              // installed, not to be picked.
              opacity: row.disabled ? 0.4 : 1
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                textFormat: Text.PlainText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  textFormat: Text.PlainText
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: row.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    if (row.kind === "file" && row.target) root.copyRowPath(row.target)
                    return
                  }
                  if (row.disabled) return
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              textFormat: Text.PlainText
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
