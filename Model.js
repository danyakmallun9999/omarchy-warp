// Pure helpers for the Cloudflare WARP plugin. Everything here is a function
// of its arguments, so Service.qml, BarWidget.qml, and Panel.qml share one set
// of parsing and presentation rules without sharing state.
//
// Contract source: `warp-cli -j status|settings list|registration show`.
// `registration show` also carries the account license and device public key;
// nothing in this file reads them — they never leave the daemon.

function parseJson(text) {
  var raw = String(text === undefined || text === null ? "" : text).trim()
  if (raw === "") return null
  try {
    return JSON.parse(raw)
  } catch (e) {
    return null
  }
}

function collapse(text) {
  return String(text === undefined || text === null ? "" : text).replace(/\s+/g, " ").trim()
}

// warp-cli reports failures either as a JSON envelope ({"code":…,"error":…})
// or as plain stderr prose; both normalise to one line of user-facing text.
function parseError(text) {
  var parsed = parseJson(text)
  if (parsed && typeof parsed === "object") {
    if (typeof parsed.error === "string" && parsed.error !== "") return collapse(parsed.error)
    if (typeof parsed.message === "string" && parsed.message !== "") return collapse(parsed.message)
  }
  return collapse(text).replace(/^error:\s*/i, "")
}

// warp-cli's status strings, lowercased: Connected, Connecting, Reconnecting,
// Disconnecting, Disconnected, RegistrationMissing. Anything new stays
// "unknown" and is shown verbatim rather than guessed at.
function kindFromStatus(status) {
  var key = collapse(status).toLowerCase()
  if (key === "connected") return "connected"
  if (key === "connecting") return "connecting"
  if (key === "reconnecting") return "reconnecting"
  if (key === "disconnecting") return "disconnecting"
  if (key === "disconnected") return "disconnected"
  if (key.indexOf("registration") !== -1) return "registration-missing"
  return "unknown"
}

function statusLabel(kind) {
  if (kind === "connected") return "Connected"
  if (kind === "connecting") return "Connecting…"
  if (kind === "reconnecting") return "Reconnecting…"
  if (kind === "disconnecting") return "Disconnecting…"
  if (kind === "disconnected") return "Disconnected"
  if (kind === "registration-missing") return "Not registered"
  return ""
}

// `warp-cli -j status` reports "Manual", where the human-readable output says
// "Manual Disconnection".
function reasonLabel(reason) {
  var key = collapse(reason).toLowerCase()
  if (key === "" || key === "none") return ""
  if (key === "manual") return "manual disconnect"
  if (key === "networkhealthy") return "network healthy"
  return key
}

// Short health line for the panel's session section. "Healthy" on a live
// tunnel, "Unavailable" when the daemon itself is down, otherwise blank.
function healthText(state, reason) {
  var key = collapse(reason).toLowerCase().replace(/[\s_-]+/g, "")
  if (state === "connected") {
    if (key === "" || key === "none" || key === "networkhealthy") return "Healthy"
    return "Degraded · " + reasonLabel(reason)
  }
  if (state === "daemon-down" || state === "unavailable") return "Unavailable"
  return ""
}

// {"status":"Disconnected","reason":"Manual"}
function parseStatus(text) {
  var parsed = parseJson(text)
  if (parsed === null || parsed === undefined) {
    return { ok: false, error: parseError(text) || "Unreadable status output" }
  }
  if (typeof parsed.status !== "string" || parsed.status === "") {
    return { ok: false, error: parseError(text) || "Status output carries no status" }
  }
  return {
    ok: true,
    status: collapse(parsed.status),
    reason: collapse(parsed.reason),
    kind: kindFromStatus(parsed.status)
  }
}

// {"settings":{"operation_mode":"warp","warp_tunnel_protocol":"masque",…}}
function parseSettings(text) {
  var parsed = parseJson(text)
  if (parsed === null || parsed === undefined || !parsed.settings || typeof parsed.settings !== "object") {
    return { ok: false, error: parseError(text) || "Unreadable settings output" }
  }
  var s = parsed.settings
  return {
    ok: true,
    mode: typeof s.operation_mode === "string" ? s.operation_mode : "",
    protocol: typeof s.warp_tunnel_protocol === "string" ? s.warp_tunnel_protocol : "",
    alwaysOn: s.always_on === true,
    switchLocked: s.switch_locked === true,
    disableForWifi: s.disable_for_wifi === true,
    disableForEthernet: s.disable_for_ethernet === true
  }
}

// {"device_id":"…","managed":false,"account":{"type":"free","license":"…"}}
function parseRegistration(text) {
  var parsed = parseJson(text)
  if (parsed === null || parsed === undefined || typeof parsed.device_id !== "string" || parsed.device_id === "") {
    return { ok: false, error: parseError(text) || "Unreadable registration output" }
  }
  var account = parsed.account && typeof parsed.account === "object" ? parsed.account : {}
  return {
    ok: true,
    deviceId: parsed.device_id,
    accountType: typeof account.type === "string" ? account.type : "",
    managed: parsed.managed === true
  }
}

// `warp-cli mode <MODE>` — order follows "tunnel first, DNS-only fallbacks
// last" rather than the CLI's alphabetical list, so the common choices sit at
// the top of the panel grid.
function modeOptions() {
  return [
    { value: "warp", label: "WARP", hint: "Tunnel with proxied DNS" },
    { value: "warp+doh", label: "WARP + DoH", hint: "Tunnel with DNS over HTTPS" },
    { value: "warp+dot", label: "WARP + DoT", hint: "Tunnel with DNS over TLS" },
    { value: "tunnel_only", label: "Tunnel only", hint: "Tunnel without DNS proxying" },
    { value: "doh", label: "DoH only", hint: "No tunnel, DNS over HTTPS" },
    { value: "dot", label: "DoT only", hint: "No tunnel, DNS over TLS" },
    { value: "proxy", label: "SOCKS5", hint: "Tunnel for use through a local proxy" }
  ]
}

// Two groups keep the long CLI list scannable: real tunnels first, DNS-only
// fallbacks behind a second header. Values stay exactly as warp-cli expects.
function modeGroups() {
  var all = modeOptions()
  function pick(values) {
    var out = []
    for (var i = 0; i < all.length; i++) {
      if (values.indexOf(all[i].value) !== -1) {
        out.push({ value: all[i].value, label: all[i].label, tooltip: all[i].hint })
      }
    }
    return out
  }
  return [
    { title: "TUNNEL MODES", options: pick(["warp", "warp+doh", "warp+dot", "tunnel_only"]) },
    { title: "DNS ONLY", options: pick(["doh", "dot", "proxy"]) }
  ]
}

function modeEntry(mode) {
  var value = collapse(mode)
  var options = modeOptions()
  for (var i = 0; i < options.length; i++) {
    if (options[i].value === value) return options[i]
  }
  return null
}

function modeLabel(mode) {
  var entry = modeEntry(mode)
  if (entry) return entry.label
  var value = collapse(mode)
  return value !== "" ? value : "unknown"
}

function modeHint(mode) {
  var entry = modeEntry(mode)
  return entry ? entry.hint : ""
}

// Reject anything the CLI would not accept, so a typo in a config file or an
// IPC call can never reach `warp-cli mode`.
function sanitizeMode(mode) {
  var entry = modeEntry(mode)
  return entry ? entry.value : ""
}

function protocolLabel(protocol) {
  var key = collapse(protocol).toLowerCase()
  if (key === "masque") return "MASQUE"
  if (key === "wireguard") return "WireGuard"
  return collapse(protocol)
}

function accountLabel(accountType, managed) {
  var key = collapse(accountType).toLowerCase()
  var name = "Unknown"
  if (key === "free") name = "Free"
  else if (key === "team") name = "Zero Trust"
  else if (key !== "") name = collapse(accountType)
  return managed ? name + " · managed" : name
}

// Device/registration ids are UUIDs; the panel shows a short prefix so the row
// stays one line wide.
function deviceLabel(deviceId) {
  var value = collapse(deviceId)
  return value.length > 8 ? value.substring(0, 8) : value
}

// Glyphs are Nerd Font (nf-md-*, Material Design Icons); a Nerd Font must be
// installed for them to render.
function stateGlyph(state) {
  if (state === "connected") return "󰅟"            // nf-md-cloud
  if (state === "disconnected") return "󰅣"         // nf-md-cloud_outline
  if (state === "connecting" || state === "reconnecting" || state === "disconnecting") return "󰑐" // nf-md-refresh
  if (state === "registration-missing") return "󰅤" // nf-md-cloud_off_outline
  if (state === "daemon-down" || state === "unavailable") return "󰧠" // nf-md-cloud_alert
  return "󰅣"                                       // probing / unknown
}

// States that mean "WARP cannot do what you asked", as opposed to "off on
// purpose". The bar paints these with the theme's urgent color.
function stateIsAlert(state) {
  return state === "daemon-down" || state === "unavailable" || state === "registration-missing"
}

// Short-lived states where a breathing glyph tells the user a click landed.
function stateIsTransitional(state) {
  return state === "connecting" || state === "reconnecting" || state === "disconnecting"
}
