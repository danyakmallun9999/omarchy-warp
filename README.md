# Cloudflare WARP — Omarchy shell plugin

Bar indicator + control panel for `warp-cli` on Omarchy (`quickshell`). Shows the current WARP state as a color-coded glyph in the bar and exposes connect/disconnect, operating mode, and account facts in a panel. No `sudo`/polkit — `warp-cli` talks to `warp-svc` over `/run/cloudflare-warp/warp_service` (`srwxrwxrwx`, world-writable on this machine).

Companion: `~/.omp/agent/extensions/warp.ts` gives the same control to the `omp` agent (`warp_status`, `warp_connect`, `warp_disconnect`, `warp_toggle`, `warp_mode`, plus `/warp …`).

## Layout

```
Service.qml   single poll engine (`warp-cli status` is the only mandatory probe;
              `settings list` @ 60 s, `registration show` @ 300 s, forced on
              panel open / refresh / after any write action)
BarWidget.qml color/glyph + tooltip, left-click = panel, right-click = toggle,
              middle-click = refresh
Panel.qml     KeyboardPanel + ScrollView: hero (status + ToggleSwitch), notice,
              SESSION (protocol / always-on / switch-lock / paused-on),
              OPERATING MODE (GridLayout 2-col), ACCOUNT (plan + device),
              actions (Refresh, Register device)
Model.js      pure parsers/labels shared by all three QML files
```

All JSON parsing goes through `Model.js` (`parseJson`, `parseStatus`, `parseSettings`, `parseRegistration`). `registration show` also returns `account.license` + `public_key`; this plugin never reads them — `parseRegistration` copies only `device_id`, `account.type`, `managed`.

## Requirements

* `warp-cli` in `PATH` (`cloudflare-warp-bin` on Arch, provides `warp-cli` `2026.7.1377+`). Falls back to `unavailable` if `which warp-cli` fails. `warp-svc` must be reachable; otherwise `daemon-down`.
* JetBrainsMono Nerd Font (the bar's `monospace` alias on this install). Glyphs were verified present in that build (check with `fc-match monospace`):
  * `󰅟` `U+F015F` `nf-md-cloud_check` — connected
  * `󰅣` `U+F0163` `nf-md-cloud_off_outline` — disconnected
  * `󰑐` `U+F0450` `nf-md-cloud_sync` — connecting / reconnecting / disconnecting
  * `󰅤` `U+F0164` — registration-missing
  * `󰧠` `U+F09E0` `nf-md-cloud_alert` — daemon-down / notice glyph

Glyph source: [Nerd Fonts](https://www.nerdfonts.com/cheat-sheet) / Material Design Icons.

## IPC

Service mounts `IpcHandler { target: "danyakmallun.warp" }`:

```
omarchy-shell danyakmallun.warp status      # JSON (publicState() + probed/installed/daemonUp)
omarchy-shell danyakmallun.warp refresh     # force re-read (returns JSON, also refreshes details)
omarchy-shell danyakmallun.warp connect
omarchy-shell danyakmallun.warp disconnect
omarchy-shell danyakmallun.warp toggle
omarchy-shell danyakmallun.warp mode <warp|warp+doh|warp+dot|tunnel_only|doh|dot|proxy>
```

`status` is also the shape returned by the other verbs after they settle. `mode` sanitises through `Model.sanitizeMode`, so arbitrary strings never reach `warp-cli mode`.

## Settings

`~/.config/omarchy/shell.json` → `bar.layout.right[]` entry for this widget:

```json
{"id":"danyakmallun.warp","refreshIntervalSec":10}
```

* `refreshIntervalSec` integer `2`–`3600`, default `10`. Poll period for `warp-cli -j status` (transitional states poll at 1 s regardless, via a short-circuit timer; the watchdog is 20 s). `shell.json` is authoritative once customized — no deep-merge — so edit it without dropping sibling keys.

Third-party enablement is `plugin id in bar.layout.<section>` for bar-widgets and `plugins[]` for other kinds; `keepLoaded: true` keeps the `service` alive even when no bar instance is mounted.

Enable/placement:

```sh
omarchy plugin enable danyakmallun.warp --after omarchy.network
# bar position is transparent/hot-reload; no omarchy refresh needed
```

Variant QMLs that strip weightless code are preferred over keeping needless abstractions; `Panel.qml` uses `RowLayout` + `Layout.fillWidth` for its notice/action rows rather than `parent.children[i]` arithmetic.

## Troubleshooting

* Tooltip looks one line only: the bar's `PopupWindow` + `Text` has no `wrapMode` — keep tooltips short, one logical line. The bar widget already builds a multi-line tooltip; the panel is the readable surface.
* Click does nothing / panel never opens: QML load failed — check `journalctl --user -b --no-pager | grep omarchy-shell` for `QML` errors. Third-party panels fail silently otherwise.
* `warp-cli -j settings list` lag: by design (60 s cache). `Refresh` or panel open force it.
* License/public key in logs? Should never happen — file a bug if you see `license` or `public_key` in any tool result or `journalctl` line from this plugin.

## License

MIT — see `LICENSE`.
