import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// WARP control panel, loaded from BarWidget.qml and wired with the host
// objects the bar injects there (bar, settings, anchorItem, hostWidget).
Panel {
  id: root

  moduleName: "danyakmallun.warp"

  property var anchorItem: null
  property var hostWidget: null

  // Injected by BarWidget: a BarState reading the service through its IPC.
  property var svc: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color alertColor: bar ? bar.urgent : Color.urgent
  // Cloudflare orange, shared with the bar widget so "on" reads the same.
  readonly property color connectedColor: "#f38020"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string state: svc ? svc.state : "probing"
  readonly property bool canAct: svc ? (svc.installed && svc.daemonUp) === true : false
  readonly property bool busy: svc ? svc.busy === true : false
  readonly property bool needsRegistration: svc ? (svc.daemonUp && !svc.registered) === true : false
  readonly property color stateColor: Model.stateIsAlert(state)
    ? alertColor
    : (svc && svc.active ? foreground : dim)
  readonly property string healthText: svc ? Model.healthText(svc.state, svc.reasonText) : ""
  readonly property string modeHint: svc ? Model.modeHint(svc.mode) : ""

  // One line explaining why WARP is not doing what the toggle says.
  readonly property string notice: {
    if (!svc) return ""
    if (state === "unavailable") return "warp-cli is not installed — install cloudflare-warp-bin"
    if (state === "daemon-down") {
      var why = svc.errorText !== "" ? " — " + svc.errorText : ""
      return "warp-svc is not reachable" + why
    }
    if (needsRegistration) return "This device is not registered with Cloudflare"
    if (svc.errorText !== "") return svc.errorText
    return ""
  }
  readonly property bool noticeAlarming: state === "unavailable" || state === "daemon-down"
    || (svc && svc.errorText !== "") || needsRegistration

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  onOpenedChanged: if (opened && svc) svc.refresh(true)

  component InfoRow: Item {
    id: row
    property string label: ""
    property string value: ""
    property color foreground: Color.foreground
    property color valueColor: Color.foreground
    property string fontFamily: Style.font.family

    width: parent ? parent.width : 0
    implicitHeight: Math.max(labelText.implicitHeight, valueText.implicitHeight)

    Text {
      id: labelText
      textFormat: Text.PlainText
      text: row.label
      color: Qt.darker(row.foreground, 1.5)
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: valueText
      textFormat: Text.PlainText
      text: row.value
      color: row.valueColor
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      anchors.left: labelText.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
    }
  }

  // Banner row: glyph + wrapped explanation.
  component NoticeRow: RowLayout {
    id: notice
    property string text: ""
    property color foreground: Color.foreground
    property color color: Color.foreground
    property string fontFamily: Style.font.family

    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: "󰧠"
      color: notice.color
      font.family: notice.fontFamily
      font.pixelSize: Style.font.body
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      textFormat: Text.PlainText
      text: notice.text
      color: notice.color
      font.family: notice.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: catcher
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(body.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: if (root.svc && root.canAct && !root.busy) root.svc.toggle()
      onTextKey: function(key) { if (key === "r" && root.svc) root.svc.refresh(true) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          when: scrollArea.contentItem !== null
          target: scrollArea.contentItem
          property: "interactive"
          value: body.implicitHeight > scrollArea.height
        }

        Column {
          id: body
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ── Hero: state + primary switch ─────────────────────────────
          PanelHero {
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            title: root.svc ? root.svc.statusText : "Checking…"
            meta: root.svc && root.svc.detailText !== "" ? root.svc.detailText : "Cloudflare WARP"
            iconOpacity: root.svc && root.svc.active ? 1.0 : 0.6

            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: Model.stateGlyph(root.state)
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display

                Behavior on color { ColorAnimation { duration: Style.duration(160) } }

                SequentialAnimation on opacity {
                  running: Model.stateIsTransitional(root.state) && !Style.reduceMotion
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.5; duration: Style.duration(260); easing.type: Easing.OutCubic }
                  NumberAnimation { to: 1.0; duration: Style.duration(260); easing.type: Easing.OutCubic }
                }
              }
            }

            trailingControl: Component {
              RowLayout {
                spacing: Style.space(10)

                // Plan pill lives beside the switch so both share one
                // vertical center instead of following the hero's two-line
                // label stack.
                BorderSurface {
                  id: planPill
                  visible: planText.text !== ""
                  implicitWidth: planText.implicitWidth + Style.space(10)
                  implicitHeight: planText.implicitHeight + Style.space(4)
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", root.foreground, root.foreground)
                  radius: Style.cornerRadius
                  Layout.alignment: Qt.AlignVCenter

                  Text {
                    id: planText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.svc ? root.svc.accountText : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }

                ToggleSwitch {
                  id: powerSwitch
                  checked: root.svc ? root.svc.active === true : false
                  busy: root.busy || !root.canAct
                  foreground: root.foreground
                  Layout.alignment: Qt.AlignVCenter
                  onToggled: if (root.svc && root.canAct) root.svc.toggle()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.svc && root.svc.active ? "Disconnect WARP" : "Connect WARP"
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          NoticeRow {
            opacity: root.notice !== "" ? 1 : 0
            visible: opacity > 0
            text: root.notice
            foreground: root.foreground
            color: root.noticeAlarming ? root.alertColor : root.dim
            fontFamily: root.fontFamily

            Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
          }

          // ── Session facts ────────────────────────────────────────────
          PanelSeparator {
            visible: root.canAct
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: root.canAct
            text: "SESSION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct
            label: "Protocol"
            value: root.svc ? Model.protocolLabel(root.svc.protocol) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct && root.healthText !== ""
            label: "Network"
            value: root.healthText
            valueColor: root.healthText === "Healthy" ? root.foreground : root.dim
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct
            label: "Always on"
            value: root.svc && root.svc.alwaysOn ? "On" : "Off"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct
            label: "Switch lock"
            value: root.svc && root.svc.switchLocked ? "On" : "Off"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct && (root.svc.disableForWifi || root.svc.disableForEthernet)
            label: "Paused on"
            value: {
              var parts = []
              if (root.svc && root.svc.disableForWifi) parts.push("Wi-Fi")
              if (root.svc && root.svc.disableForEthernet) parts.push("Ethernet")
              return parts.join(", ")
            }
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // ── Operating mode ───────────────────────────────────────────
          PanelSeparator {
            visible: root.canAct
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: root.canAct
            text: "OPERATING MODE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.canAct && root.modeHint !== ""
            textFormat: Text.PlainText
            width: parent.width
            text: root.modeHint
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Repeater {
            visible: root.canAct
            model: Model.modeGroups()

            delegate: Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(5)

              Text {
                textFormat: Text.PlainText
                text: modelData.title
                color: Qt.darker(root.foreground, 1.5)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }

              ButtonGroup {
                width: parent.width
                options: modelData.options
                value: root.svc ? root.svc.mode : ""
                foreground: root.foreground
                accent: root.connectedColor
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                focusable: false
                enabled: root.canAct && !root.busy
                onChanged: function(v) { if (root.svc) root.svc.setMode(v) }
              }
            }
          }

          // ── Account ──────────────────────────────────────────────────
          PanelSeparator {
            visible: root.canAct && root.svc.registered
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: root.canAct && root.svc.registered
            text: "ACCOUNT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct && root.svc.registered
            label: "Plan"
            value: root.svc ? root.svc.accountText : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          InfoRow {
            visible: root.canAct && root.svc.registered
            label: "Device"
            value: root.svc ? root.svc.deviceText : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: "Refresh"
              iconText: "󰑐"
              iconSpinning: root.svc ? root.svc.refreshing === true : false
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.canAct
              onClicked: if (root.svc) root.svc.refresh(true)
            }

            Button {
              visible: root.needsRegistration
              text: "Register device"
              iconText: "󰅤"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.canAct && !root.busy
              onClicked: if (root.svc) root.svc.registerDevice()
            }

            Item {
              Layout.fillWidth: true
              height: 1
            }
          }
        }
      }
    }
  }
}
