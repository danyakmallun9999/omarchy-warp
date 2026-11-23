import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar indicator for Cloudflare WARP. Left click opens the panel, right click
// toggles the tunnel, middle click forces a re-read — same gesture set as the
// built-in Tailscale widget, since both are VPN toggles.
//
// All state comes from the plugin service, so this widget and the panel share
// one `warp-cli` poll loop.
BarWidget {
  id: root

  moduleName: "danyakmallun.warp"

  // A replacement bar hands its widgets a service-less facade, so
  // bar.shell.serviceFor() is null there. Read the plugin's own service
  // through its IPC surface instead.
  readonly property var svc: warpState
  readonly property string state: svc ? svc.state : "probing"

  BarState {
    id: warpState
    settings: root.settings
  }
  readonly property bool connected: svc ? svc.active === true : false
  readonly property bool spinning: svc ? svc.busy === true : false
  readonly property color barForeground: bar ? bar.foreground : Color.foreground
  // Cloudflare orange, kept fixed so "on" reads the same on every theme.
  readonly property color connectedColor: "#f38020"

  readonly property color stateColor: {
    if (Model.stateIsAlert(root.state)) return bar ? bar.urgent : Color.urgent
    return root.connected ? root.connectedColor : Qt.darker(root.barForeground, 1.55)
  }

  readonly property string tooltip: {
    if (!svc) return "Cloudflare WARP"
    var lines = ["Cloudflare WARP · " + svc.statusText]
    if (svc.state === "daemon-down" || svc.state === "unavailable") {
      lines.push(svc.errorText)
    } else {
      if (svc.state === "disconnected" && svc.reasonText !== "") lines[0] = "Cloudflare WARP · Disconnected (" + svc.reasonText + ")"
      var detail = svc.detailText
      if (detail !== "") lines.push(detail)
      if (svc.registered) {
        var account = svc.accountText
        if (svc.deviceText !== "") account += " · device " + svc.deviceText
        lines.push(account)
      }
      if (svc.errorText !== "") lines.push(svc.errorText)
    }
    return lines.join("\n")
  }

  // ── panel lifecycle (contract with the bar host) ───────────────────────
  readonly property bool opened: loader.item ? loader.item.opened === true : false
  readonly property bool popoutSwitchClosing: loader.item ? loader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (loader.item) loader.item.closeForPopoutSwitch()
  }

  function open() {
    if (loader.item) loader.item.open()
  }

  function close() {
    if (loader.item) loader.item.close()
  }

  function togglePanel() {
    if (loader.item) loader.item.toggle()
  }

  // The panel is a child of this widget: hand it the host objects the bar
  // injects here, plus the service lookup it needs for its own bindings.
  function inject() {
    if (!loader.item) return
    loader.item.bar = root.bar
    loader.item.settings = root.settings
    loader.item.svc = root.svc
    loader.item.anchorItem = button
    loader.item.hostWidget = root
    if (root.svc && root.svc.settings !== root.settings) root.svc.settings = root.settings
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: inject()
  onSettingsChanged: inject()
  onSvcChanged: inject()

  Loader {
    id: loader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.inject()
      Qt.callLater(root.inject)
    }
  }

  // Scriptable panel control, so a keybinding can open the same panel:
  //   omarchy-shell danyakmallun.warp.ui open
  IpcHandler {
    target: "danyakmallun.warp.ui"
    function open(): string { root.open(); return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string { root.togglePanel(); return "ok" }
  }
  // Cloud glyph + wordmark: the icon reads the tunnel state at a glance, the
  // label keeps it unmistakably WARP beside the other bar icons. Cloudflare
  // orange is a fixed accent when on; every other state follows the theme.
  BarIconButton {
    id: button
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    bar: root.bar
    slotSize: Style.bar.iconSlot * 2.4
    text: Model.stateGlyph(root.state)
    labelText: "warp"
    tooltipText: root.tooltip
    foreground: root.stateColor
    active: root.connected
    activeColor: root.connectedColor
    dimmed: root.spinning
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.svc) root.svc.toggle()
      } else if (mouseButton === Qt.MiddleButton) {
        if (root.svc) root.svc.refresh(true)
      } else {
        root.togglePanel()
      }
    }
  }
}
