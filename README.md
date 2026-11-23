# Cloudflare WARP — Omarchy Shell Plugin

A bar indicator and control panel for `warp-cli` on Omarchy. The bar shows a
state glyph plus the `warp` wordmark: orange while the tunnel is up, dimmed while
off, urgent on errors, and breathing during a transition. The panel offers
connect/disconnect, grouped operating modes, tunnel health, and account details.

No `sudo` or polkit is involved: `warp-cli` talks to `warp-svc` over its local
socket. Polling is read-only; only explicit actions write state.

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`).
- `warp-cli` in `PATH` (`cloudflare-warp-bin` on Arch). The widget reports
  `warp-cli not found` when missing, and `warp-svc unavailable` when the daemon
  is down.
- A Nerd Font in the bar font for the status glyphs, for example
  JetBrainsMono Nerd Font. The glyphs used are:
  - `󰅟` `U+F015F` `nf-md-cloud_check` — connected
  - `󰅣` `U+F0163` `nf-md-cloud_off_outline` — disconnected
  - `󰑐` `U+F0450` `nf-md-cloud_sync` — connecting / reconnecting / disconnecting
  - `󰅤` `U+F0164` — registration missing
  - `󰧠` `U+F09E0` `nf-md-cloud_alert` — daemon down / notice

  Glyph source: [Nerd Fonts cheat sheet](https://www.nerdfonts.com/cheat-sheet).

## Install

```bash
omarchy plugin add https://github.com/danyakmallun9999/omarchy-warp.git --enable --yes
```

To place it next to the network widget:

```bash
omarchy plugin enable danyakmallun.warp --after omarchy.network
```

To remove it:

```bash
omarchy plugin remove danyakmallun.warp --yes
```

The shell hot-reloads plugin files on save; no `omarchy refresh` is needed.

## Controls

- **Left click**: open / close the panel.
- **Right click**: toggle the tunnel.
- **Middle click**: force a re-read.
- **Inside the panel**: `Enter` toggles the tunnel, `R` refreshes, `Tab` switches
  to a neighbouring bar panel, `Esc` closes.

To get a keyboard shortcut, add a Hyprland binding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + W", "WARP panel", "omarchy-shell danyakmallun.warp.ui toggle")
```

## IPC

```bash
omarchy-shell danyakmallun.warp status
omarchy-shell danyakmallun.warp refresh
omarchy-shell danyakmallun.warp connect
omarchy-shell danyakmallun.warp disconnect
omarchy-shell danyakmallun.warp toggle
omarchy-shell danyakmallun.warp mode <warp|warp+doh|warp+dot|tunnel_only|doh|dot|proxy>
omarchy-shell danyakmallun.warp registerDevice
```

`status` prints JSON with the tunnel state, operating mode, protocol, and
settings. `mode` is validated against a fixed list, so arbitrary strings never
reach `warp-cli mode`.

A second target drives the panel UI:

```bash
omarchy-shell danyakmallun.warp.ui open
omarchy-shell danyakmallun.warp.ui close
omarchy-shell danyakmallun.warp.ui toggle
```

## Settings

The widget entry in `~/.config/omarchy/shell.json` accepts one setting:

```json
{"id":"danyakmallun.warp","refreshIntervalSec":10}
```

`refreshIntervalSec` is an integer from `2` to `3600` (default `10`). Transitional
states are polled once a second regardless. `shell.json` is authoritative once
customized — no deep merge — so edit it without dropping sibling keys.

`keepLoaded: true` in the manifest keeps the service alive even when no bar
instance is mounted.

## Layout

```
Service.qml   Single poll/action engine around warp-cli; read probes for status,
              settings, and registration, plus write actions
BarState.qml  Service facade over the plugin's own IPC, so the widget also works
              on a replacement bar where bar.shell.serviceFor() is unavailable
BarWidget.qml Glyph, wordmark, tooltip, click routing, and panel IPC target
Panel.qml     KeyboardPanel: hero with toggle, notices, session facts, grouped
              operating modes, account details, and actions
Model.js      Pure parsers, sanitizers, and labels shared by all QML files
```

All dynamic text is plain text. JSON parsing happens only in `Model.js`;
`registration show` also returns the account license and device public key, but
the plugin never reads them.

## Troubleshooting

- **Panel does not open:** check `journalctl --user -b --no-pager | grep omarchy-shell`
  for QML load errors.
- **Tooltip looks short:** the bar's tooltip has no wrapping; use the panel for
  the full detail.
- **Settings lag:** `warp-cli -j settings list` is cached for 60 s; opening the
  panel or pressing Refresh forces an update.
- **Not registered:** press `Register device` in the panel (accepts the Cloudflare
  ToS non-interactively).

## License

MIT — see `LICENSE`.
