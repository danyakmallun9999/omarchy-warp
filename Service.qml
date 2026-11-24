import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Single WARP engine behind both surfaces: the bar widget and the panel reach
// it through `bar.shell.serviceFor("danyakmallun.warp")`, so no consumer ever
// spawns its own `warp-cli`.
//
// Everything here is a thin normalisation of three read-only probes —
// `status`, `settings list`, `registration show` — plus the write actions
// (connect, disconnect, mode, registration new). warp-cli talks to warp-svc
// over a local socket, so no elevation path is involved anywhere.
Item {
  id: root

  // Host injection (see plugins/README.md: entry points may declare these).
  property var shell: null
  property string omarchyPath: ""
  property var manifest: null
  // Pushed by the bar widget so the poll interval follows the layout entry.
  property var settings: ({})

  // ── exposed state ──────────────────────────────────────────────────────
  property bool probed: false            // `which warp-cli` answered
  property bool installed: false
  property bool daemonUp: false          // warp-svc reachable
  property bool registered: false
  property string status: ""             // raw status string from warp-cli
  property string kind: "unknown"        // Model.kindFromStatus(status)
  property string reason: ""             // raw reason string from warp-cli
  property string mode: ""               // warp | warp+doh | doh | proxy | …
  property string protocol: ""           // masque | wireguard
  property bool alwaysOn: false
  property bool switchLocked: false
  property bool disableForWifi: false
  property bool disableForEthernet: false
  property string accountType: ""
  property bool managed: false
  property string deviceId: ""
  property string lastError: ""          // transport/daemon failure
  property string actionError: ""        // last write action failure
  property string lastAction: ""
  property double syncedAtMs: 0

  property string _statusOutput: ""
  property string _statusError: ""
  property string _settingsOutput: ""
  property string _registrationOutput: ""
  property string _actionOutput: ""
  property string _actionErrorOutput: ""
  property double _settingsAtMs: 0
  property double _registrationAtMs: 0
  property bool _detailsForced: false

  // Optimistic connected flag: -1 follows warp-cli, 0/1 while a toggle is
  // still landing so the bar reacts to the click instead of one poll later.
  // Cleared as soon as the reported status matches.
  property int _desired: -1

  // A toggle must decide from a fresh read, never from a snapshot that can be
  // up to refreshIntervalSec old. The action is deferred until that read lands.
  property bool _togglePending: false

  readonly property bool connected: kind === "connected"
  readonly property bool transitional: kind === "connecting" || kind === "reconnecting" || kind === "disconnecting"
  readonly property bool active: _desired === -1 ? connected : _desired === 1
  readonly property bool actionBusy: actionProcess.running
  readonly property bool busy: actionBusy || transitional
  readonly property bool refreshing: statusProcess.running || settingsProcess.running || registrationProcess.running
  readonly property string errorText: actionError !== "" ? actionError : lastError

  // Single vocabulary shared with the bar color/glyph rules and the panel.
  readonly property string state: {
    if (!probed) return "probing"
    if (!installed) return "unavailable"
    if (!daemonUp) return "daemon-down"
    if (kind === "registration-missing") return "registration-missing"
    return kind
  }

  readonly property string statusText: {
    if (state === "probing") return "Checking…"
    if (state === "unavailable") return "warp-cli not found"
    if (state === "daemon-down") return "warp-svc unavailable"
    if (state === "registration-missing") return "Not registered"
    var label = Model.statusLabel(kind)
    if (label !== "") return label
    return status !== "" ? status : "Unknown"
  }

  readonly property string reasonText: Model.reasonLabel(reason)

  // "WARP · MASQUE"-style line for tooltips and the panel subtitle.
  readonly property string detailText: {
    var parts = []
    if (mode !== "") parts.push(Model.modeLabel(mode))
    if (protocol !== "") parts.push(Model.protocolLabel(protocol))
    return parts.join(" · ")
  }

  readonly property string accountText: Model.accountLabel(accountType, managed)
  readonly property string deviceText: Model.deviceLabel(deviceId)
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 10, 2, 3600)

  // ── helpers ────────────────────────────────────────────────────────────
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function probe() {
    if (whichProcess.running) return
    whichProcess.running = true
  }

  // Status is the only mandatory probe; the detail probes piggyback on its
  // result so a dead daemon never produces three failing subprocesses per tick.
  function refresh(force) {
    if (force === true) _detailsForced = true
    if (!probed) {
      probe()
      return
    }
    if (!installed) return
    if (statusProcess.running) return
    _statusOutput = ""
    _statusError = ""
    statusProcess.running = true
    readWatchdog.restart()
  }

  function refreshDetails() {
    if (!installed || !daemonUp) return
    var forced = _detailsForced
    var now = Date.now()
    // Settings carry the operating mode, which the panel lets you change;
    // registration is effectively static, so it lags far behind.
    if (!settingsProcess.running && (forced || now - _settingsAtMs > 60000)) {
      _settingsOutput = ""
      _settingsAtMs = now
      settingsProcess.running = true
      readWatchdog.restart()
    }
    var wantRegistration = forced || now - _registrationAtMs > 300000
    if (wantRegistration && !registrationProcess.running) {
      _registrationOutput = ""
      _registrationAtMs = now
      registrationProcess.running = true
      readWatchdog.restart()
    }
    _detailsForced = false
  }

  function runAction(action, args) {
    if (!installed || actionProcess.running) return false
    lastAction = action
    _actionOutput = ""
    _actionErrorOutput = ""
    actionProcess.command = args
    actionProcess.running = true
    return true
  }

  function connect() {
    actionError = ""
    if (actionProcess.running || _desired === 1) return false
    if (!runAction("connect", ["warp-cli", "--no-ansi", "connect"])) return false
    _desired = 1
    return true
  }

  function disconnect() {
    actionError = ""
    if (actionProcess.running || _desired === 0) return false
    if (!runAction("disconnect", ["warp-cli", "--no-ansi", "disconnect"])) return false
    _desired = 0
    return true
  }

  function toggle() {
    if (actionProcess.running || _togglePending || !installed || !daemonUp) return false
    // `active` may lag behind another control (IPC, keybinding, or a direct
    // warp-cli call). Refresh first, then act on the reported state so a
    // toggle never disconnects a tunnel the caller believed was down.
    _togglePending = true
    refresh(true)
    return true
  }

  function resolvePendingToggle() {
    if (!_togglePending) return
    _togglePending = false
    if (connected) disconnect()
    else connect()
  }

  function setMode(value) {
    actionError = ""
    var next = Model.sanitizeMode(value)
    if (next === "" || actionProcess.running) return false
    if (!runAction("mode", ["warp-cli", "--no-ansi", "mode", next])) return false
    mode = next  // optimistic: the next settings poll confirms it
    return true
  }

  // Consumer accounts register against Cloudflare's free tier; this is the
  // only action that accepts the ToS non-interactively.
  function registerDevice() {
    actionError = ""
    return runAction("register", ["warp-cli", "--no-ansi", "--accept-tos", "registration", "new"])
  }

  function publicState() {
    return {
      probed: probed,
      installed: installed,
      daemonUp: daemonUp,
      state: state,
      status: status,
      statusText: statusText,
      reason: reason,
      reasonText: reasonText,
      connected: connected,
      active: active,
      busy: busy,
      registered: registered,
      accountType: accountType,
      managed: managed,
      deviceId: deviceId,
      mode: mode,
      modeLabel: Model.modeLabel(mode),
      protocol: protocol,
      alwaysOn: alwaysOn,
      switchLocked: switchLocked,
      error: errorText,
      accountText: accountText,
      deviceText: deviceText,
      detailText: detailText,
      disableForWifi: disableForWifi,
      disableForEthernet: disableForEthernet,
      refreshing: refreshing
    }
  }

  // ── read probes ────────────────────────────────────────────────────────
  Process {
    id: whichProcess
    command: ["which", "warp-cli"]
    stdout: StdioCollector {
      id: whichStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.probed = true
      root.installed = exitCode === 0 && String(whichStdout.text || "").trim() !== ""
      if (root.installed) root.refresh(true)
      else root.lastError = "warp-cli is not in PATH"
    }
  }

  Process {
    id: statusProcess
    command: ["warp-cli", "-j", "--no-ansi", "status"]
    stdout: StdioCollector {
      id: statusStdout
      waitForEnd: true
      onStreamFinished: root._statusOutput = text
    }
    stderr: StdioCollector {
      id: statusStderr
      waitForEnd: true
      onStreamFinished: root._statusError = text
    }
    onExited: function(exitCode) {
      var out = String(statusStdout.text || root._statusOutput || "")
      var err = String(statusStderr.text || root._statusError || "")
      if (exitCode !== 0) {
        root.daemonUp = false
        root._desired = -1
        root._togglePending = false
        root.lastError = Model.parseError(err !== "" ? err : out) || "warp-cli status failed"
        return
      }
      var parsed = Model.parseStatus(out)
      if (!parsed.ok) {
        root.daemonUp = false
        root._togglePending = false
        root.lastError = parsed.error || "Unreadable status output"
        return
      }
      root.daemonUp = true
      root.lastError = ""
      root.status = parsed.status
      root.kind = parsed.kind
      root.reason = parsed.reason
      root.syncedAtMs = Date.now()
      if (root._desired !== -1 && (parsed.kind === "connected") === (root._desired === 1)) root._desired = -1
      root.resolvePendingToggle()
      root.refreshDetails()
    }
  }

  Process {
    id: settingsProcess
    command: ["warp-cli", "-j", "--no-ansi", "settings", "list"]
    stdout: StdioCollector {
      id: settingsStdout
      waitForEnd: true
      onStreamFinished: root._settingsOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var parsed = Model.parseSettings(String(settingsStdout.text || root._settingsOutput || ""))
      if (!parsed.ok) return
      root.mode = parsed.mode
      root.protocol = parsed.protocol
      root.alwaysOn = parsed.alwaysOn
      root.switchLocked = parsed.switchLocked
      root.disableForWifi = parsed.disableForWifi
      root.disableForEthernet = parsed.disableForEthernet
    }
  }

  Process {
    id: registrationProcess
    command: ["warp-cli", "-j", "--no-ansi", "registration", "show"]
    stdout: StdioCollector {
      id: registrationStdout
      waitForEnd: true
      onStreamFinished: root._registrationOutput = text
    }
    onExited: function(exitCode) {
      // Only reached while the daemon answers, so a non-zero exit here means
      // this device really has no registration.
      if (exitCode !== 0) {
        root.registered = false
        root.deviceId = ""
        root.accountType = ""
        root.managed = false
        return
      }
      var parsed = Model.parseRegistration(String(registrationStdout.text || root._registrationOutput || ""))
      if (!parsed.ok) {
        root.registered = false
        return
      }
      root.registered = true
      root.deviceId = parsed.deviceId
      root.accountType = parsed.accountType
      root.managed = parsed.managed
    }
  }

  // ── write actions ──────────────────────────────────────────────────────
  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector {
      id: actionStdout
      waitForEnd: true
      onStreamFinished: root._actionOutput = text
    }
    stderr: StdioCollector {
      id: actionStderr
      waitForEnd: true
      onStreamFinished: root._actionErrorOutput = text
    }
    onExited: function(exitCode) {
      var out = String(actionStdout.text || root._actionOutput || "")
      var err = String(actionStderr.text || root._actionErrorOutput || "")
      if (exitCode !== 0) {
        root.actionError = Model.parseError(err !== "" ? err : out) || ("warp-cli " + root.lastAction + " failed")
        root._desired = -1
      } else {
        root.actionError = ""
      }
      root.lastAction = ""
      // Pull the new truth immediately; while a tunnel is coming up the
      // transitional state makes the poll timer run at 1s.
      root.refresh(true)
    }
  }

  Timer {
    id: pollTimer
    interval: root.transitional ? 1000 : root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: {
      if (!root.probed || !root.installed) root.probe()
      else root.refresh(false)
    }
  }

  // A wedged warp-cli (daemon mid-restart) must not stall the poll loop.
  Timer {
    id: readWatchdog
    interval: 20000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (settingsProcess.running) settingsProcess.running = false
      if (registrationProcess.running) registrationProcess.running = false
    }
  }

  Component.onCompleted: probe()

  // Scriptable surface for keybindings and for the omp extension:
  //   quickshell ipc -p "$OMARCHY_PATH/shell" call danyakmallun.warp toggle
  IpcHandler {
    target: "danyakmallun.warp"

    function status(): string {
      return JSON.stringify(root.publicState())
    }
    function refresh(): string {
      root.refresh(true)
      return "ok"
    }
    function connect(): string {
      return root.connect() ? "ok" : "ignored"
    }
    function disconnect(): string {
      return root.disconnect() ? "ok" : "ignored"
    }
    function toggle(): string {
      return root.toggle() ? "ok" : "ignored"
    }
    function setMode(value: string): string {
      root.setMode(value)
      return "ok"
    }
    function registerDevice(): string {
      root.registerDevice()
      return "ok"
    }
    function mode(): string {
      return root.mode
    }
  }
}
