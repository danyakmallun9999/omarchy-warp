import QtQuick
import Quickshell
import Quickshell.Io

// The WARP service, read through its own IPC surface.
//
// A replacement bar hands its widgets a service-less facade, so
// bar.shell.serviceFor() returns null there. This keeps the same surface the
// widget and panel expect, backed by `omarchy-shell danyakmallun.warp ...`.
Item {
  id: root

  property var settings: ({})
  property var stateData: ({})
  property bool refreshing: false

  readonly property bool probed: stateData.probed === true
  readonly property bool installed: stateData.installed === true
  readonly property bool daemonUp: stateData.daemonUp === true
  readonly property string state: String(stateData.state || "probing")
  readonly property string statusText: String(stateData.statusText || "Checking…")
  readonly property string reasonText: String(stateData.reasonText || "")
  readonly property bool active: stateData.active === true
  readonly property bool busy: stateData.busy === true
  readonly property bool registered: stateData.registered === true
  readonly property string accountText: String(stateData.accountText || "")
  readonly property string deviceText: String(stateData.deviceText || "")
  readonly property string detailText: String(stateData.detailText || "")
  readonly property string protocol: String(stateData.protocol || "")
  readonly property bool alwaysOn: stateData.alwaysOn === true
  readonly property bool switchLocked: stateData.switchLocked === true
  readonly property bool disableForWifi: stateData.disableForWifi === true
  readonly property bool disableForEthernet: stateData.disableForEthernet === true
  readonly property string errorText: String(stateData.error || "")
  readonly property string mode: String(stateData.mode || "")

  function refresh(force) { refreshing = true; if (!poll.running) poll.running = true }
  // Explicit intents: a UI click must say *what* it wants, not ask the service
  // to flip a state that may have changed since this snapshot was taken.
  function connect() { act("connect") }
  function disconnect() { act("disconnect") }
  function toggle() { act("toggle") }
  function setMode(value) { act("setMode", String(value || "")) }
  function registerDevice() { act("registerDevice") }

  function act(verb, arg) {
    var args = ["omarchy-shell", "danyakmallun.warp", verb]
    if (arg !== undefined) args.push(arg)
    Quickshell.execDetached(args)
    settle.restart()
  }

  // Give the service a moment to finish the action before the next read.
  Timer { id: settle; interval: 700; onTriggered: root.refresh() }

  Timer {
    interval: Math.max(2, Number(root.settings && root.settings.refreshIntervalSec) || 10) * 1000
    running: true
    repeat: true
    onTriggered: if (!poll.running) poll.running = true
  }

  Process {
    id: poll
    command: ["omarchy-shell", "danyakmallun.warp", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.stateData = JSON.parse(text) } catch (e) {}
        root.refreshing = false
      }
    }
    onExited: root.refreshing = false
  }

  Component.onCompleted: poll.running = true
}
