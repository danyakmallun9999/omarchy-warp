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

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("danyakmallun.warp") : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color alertColor: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string state: svc ? svc.state : "probing"
  readonly property bool canAct: svc ? (svc.installed && svc.daemonUp) === true : false
  readonly property bool busy: svc ? svc.busy === true : false
  readonly property bool needsRegistration: svc ? (svc.daemonUp && !svc.registered) === true : false
  readonly property color stateColor: Model.stateIsAlert(state)
    ? alertColor
    : (svc && svc.active ? foreground : dim)
  readonly property string heroDetail: {
    if (!svc) return ""
    if (svc.registered) return svc.accountText
    if (svc.state === "disconnected" && svc.reasonText !== "") return svc.reasonText
    return ""
  }

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
    centerOnBar: true
    focusTarget: catcher
    contentWidth: popup.fittedContentWidth(Style.space(360))
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
            meta: "Cloudflare WARP"
            detail: root.heroDetail

            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: Model.stateGlyph(root.state)
                color: root.stateColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                checked: root.svc ? root.svc.active === true : false
                busy: root.busy || !root.canAct
                foreground: root.foreground
                onToggled: if (root.svc && root.canAct) root.svc.toggle()
              }
            }
          }

          NoticeRow {
            visible: root.notice !== ""
            text: root.notice
            foreground: root.foreground
            color: root.noticeAlarming ? root.alertColor : root.dim
            fontFamily: root.fontFamily
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
            visible: root.canAct
            textFormat: Text.PlainText
            width: parent.width
            text: root.svc ? Model.modeHint(root.svc.mode) : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          GridLayout {
            visible: root.canAct
            width: parent.width
            columns: 2
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)
            Layout.alignment: Qt.AlignLeft

            Repeater {
              model: Model.modeOptions()

              delegate: Button {
                required property var modelData

                Layout.fillWidth: true
                text: modelData.label
                tooltipText: modelData.hint
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                selected: root.svc ? root.svc.mode === modelData.value : false
                enabled: root.canAct && !root.busy && (!root.svc || root.svc.mode !== modelData.value)
                onClicked: if (root.svc) root.svc.setMode(modelData.value)
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

            Text {
              textFormat: Text.PlainText
              Layout.alignment: Qt.AlignVCenter
              text: root.svc ? root.svc.detailText : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
