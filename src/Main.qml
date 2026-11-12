import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Decomon

ApplicationWindow {
    id: win
    width: 1040
    height: 700
    minimumWidth: 720
    minimumHeight: 500
    visible: true
    title: "Deco Monitor"
    color: bg

    Material.theme: Material.Dark
    Material.accent: theme.accent
    Material.roundedScale: theme.radius

    readonly property color bg: "#0e0e10"
    readonly property color surface: "#17171a"
    readonly property color line: "#26262b"
    readonly property color fg: "#e8e8ea"
    readonly property color muted: "#8b8b93"
    readonly property color danger: "#ff6b6b"
    readonly property int radius: theme.radius
    readonly property int smallRadius: Math.min(4, theme.radius)
    // In a narrow tile the IP and connection columns give way to names.
    readonly property bool wide: width >= 1000

    property bool helpVisible: false
    property bool showIdle: true
    // "connection" keeps the list steady: grouped Wired, 6 GHz, 5 GHz,
    // 2.4 GHz, then anything else, and alphabetical inside each group, so rows
    // don't jump around as speeds change. S cycles to name and speed.
    property string sortMode: "connection"
    readonly property var connectionOrder: ["Wired", "6 GHz", "5 GHz", "2.4 GHz"]
    function connectionRank(c) {
        const i = win.connectionOrder.indexOf(c)
        return i < 0 ? win.connectionOrder.length : i
    }
    function byName(a, b) { return a.name.localeCompare(b.name) || a.mac.localeCompare(b.mac) }
    property var pendingReboot: null      // {macs: [...], label: "..."}
    property var pendingBlock: null       // {mac, name, unblock: bool}

    function isOwn(mac) { return backend.ownMacs.indexOf(mac) >= 0 }
    function isBlocked(mac) { return backend.blocked.some(b => b.mac === mac) }
    function askBlock(c) {
        if (!c || win.isOwn(c.mac) || win.isBlocked(c.mac) || backend.blocking) return
        win.pendingBlock = { mac: c.mac, name: c.name, unblock: false }
    }
    function askUnblock(c) {
        if (!c || !win.isBlocked(c.mac) || backend.blocking) return
        win.pendingBlock = { mac: c.mac, name: c.name, unblock: true }
    }
    // Opens the right-click menu for a device; with no position it pops up at
    // the pointer, which is where the user just clicked.
    function openMenu(c, item) {
        deviceMenu.target = c
        if (item) deviceMenu.popup(item, item.width / 2, item.height / 2)
        else deviceMenu.popup()
    }

    // ------------------------------------------------------------ formatting
    function speed(kbps) {
        const l = Qt.locale()
        if (kbps >= 1e6) return qsTr("%1 Gbps").arg((kbps / 1e6).toLocaleString(l, 'f', 2))
        if (kbps >= 1000) return qsTr("%1 Mbps").arg((kbps / 1000).toLocaleString(l, 'f', kbps >= 1e5 ? 0 : 1))
        return qsTr("%1 Kbps").arg(Math.round(kbps).toLocaleString(l, 'f', 0))
    }
    function ago(seconds) {
        const s = Math.max(0, Math.round(Date.now() / 1000 - seconds))
        if (s < 60) return qsTr("%1 s ago").arg(s)
        return qsTr("%1 min ago").arg(Math.round(s / 60))
    }

    readonly property var visibleClients: {
        translator.language
        const q = search.text.trim().toLowerCase()
        let list = backend.clients.filter(c => {
            if (!win.showIdle && c.down + c.up < 1) return false
            if (!q) return true
            return (c.name + " " + c.ip + " " + c.mac + " " + c.connection + " " + c.type).toLowerCase().indexOf(q) >= 0
        })
        if (win.sortMode === "connection")
            list = list.slice().sort((a, b) => win.connectionRank(a.connection) - win.connectionRank(b.connection) || win.byName(a, b))
        else if (win.sortMode === "name")
            list = list.slice().sort(win.byName)
        // "speed" keeps the service's order, busiest first.
        return list
    }

    function askReboot(macs, label) { win.pendingReboot = { macs: macs, label: label } }

    // ------------------------------------------------------------- shortcuts
    Shortcut { sequence: "?"; context: Qt.ApplicationShortcut; onActivated: win.helpVisible = !win.helpVisible }
    Shortcut { sequence: "Q"; context: Qt.ApplicationShortcut; enabled: !search.activeFocus; onActivated: Qt.quit() }
    Shortcut { sequence: "Space"; context: Qt.ApplicationShortcut; enabled: !search.activeFocus; onActivated: win.showIdle = !win.showIdle }
    Shortcut { sequence: "S"; context: Qt.ApplicationShortcut; enabled: !search.activeFocus; onActivated: win.sortMode = win.sortMode === "connection" ? "name" : win.sortMode === "name" ? "speed" : "connection" }
    Shortcut { sequence: "/"; context: Qt.ApplicationShortcut; onActivated: search.forceActiveFocus() }
    Shortcut {
        sequences: ["Menu", "Shift+F10"]; context: Qt.ApplicationShortcut
        enabled: !search.activeFocus && list.currentIndex >= 0 && list.currentItem !== null
        onActivated: win.openMenu(win.visibleClients[list.currentIndex], list.currentItem)
    }
    Shortcut {
        sequence: "B"; context: Qt.ApplicationShortcut
        enabled: !search.activeFocus && list.currentIndex >= 0 && !backend.blocking
        onActivated: win.askBlock(win.visibleClients[list.currentIndex])
    }
    Shortcut { sequences: ["Ctrl+F"]; context: Qt.ApplicationShortcut; onActivated: search.forceActiveFocus() }
    Shortcut {
        sequence: "R"; context: Qt.ApplicationShortcut
        enabled: !search.activeFocus && backend.nodes.length > 0 && !backend.rebooting
        onActivated: win.askReboot([], qsTr("all Deco units"))
    }
    Shortcut {
        sequence: "Esc"; context: Qt.ApplicationShortcut
        onActivated: {
            if (win.pendingBlock) win.pendingBlock = null
            else if (win.pendingReboot) win.pendingReboot = null
            else if (win.helpVisible) win.helpVisible = false
            else if (search.text !== "" || search.activeFocus) { search.text = ""; list.forceActiveFocus() }
        }
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // ---------------------------------------------------------- banner
            Rectangle {
                Layout.fillWidth: true
                visible: backend.state !== Backend.Ok
                implicitHeight: bannerRow.implicitHeight + 24
                radius: win.radius
                color: Qt.rgba(win.danger.r, win.danger.g, win.danger.b, 0.12)
                border.color: Qt.rgba(win.danger.r, win.danger.g, win.danger.b, 0.5)

                RowLayout {
                    id: bannerRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Label {
                            textFormat: Text.PlainText
                            font.bold: true
                            color: win.danger
                            text: backend.state === Backend.NoService ? qsTr("The deco-monitor service isn't running")
                                : backend.state === Backend.Stale ? qsTr("The deco-monitor service stopped updating")
                                : qsTr("Can't reach the Deco")
                        }
                        Label {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: win.muted
                            text: backend.state === Backend.Failing ? backend.error
                                : qsTr("It polls the Deco in the background for this app and the bar widget.")
                        }
                    }
                    Button {
                        visible: backend.state !== Backend.Failing
                        text: qsTr("Start service")
                        highlighted: true
                        onClicked: backend.startService()
                    }
                }
            }

            // ---------------------------------------------------------- header
            RowLayout {
                Layout.fillWidth: true
                spacing: 32

                ColumnLayout {
                    spacing: 0
                    Label { text: qsTr("DOWNLOAD"); color: win.muted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                    Label {
                        textFormat: Text.PlainText
                        text: win.speed(backend.downKbps)
                        color: theme.accent
                        font.pixelSize: 34; font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Label { text: qsTr("UPLOAD"); color: win.muted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                    Label {
                        textFormat: Text.PlainText
                        text: win.speed(backend.upKbps)
                        color: win.fg
                        font.pixelSize: 34; font.bold: true
                        font.features: { "tnum": 1 }
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Label { text: qsTr("DEVICES"); color: win.muted; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                    Label {
                        text: backend.clients.length
                        color: win.fg
                        font.pixelSize: 34; font.bold: true
                    }
                }
                Item { Layout.fillWidth: true }
                ColumnLayout {
                    spacing: 4
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    Label {
                        Layout.alignment: Qt.AlignRight
                        textFormat: Text.PlainText
                        visible: backend.wan.ip !== undefined && backend.wan.ip !== ""
                        text: qsTr("Internet %1 · %2").arg(backend.wan.ip || "").arg(backend.wan.type || "")
                        color: win.muted
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        visible: backend.decoCpu >= 0
                        text: qsTr("Deco CPU %1% · RAM %2%").arg(backend.decoCpu).arg(backend.decoMem)
                        color: win.muted
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        visible: backend.updated > 0
                        text: { clock.tick; return qsTr("Updated %1").arg(win.ago(backend.updated)) }
                        color: Qt.darker(win.muted, 1.3)
                        font.pixelSize: 12
                    }
                }
            }

            // ----------------------------------------------------------- graph
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(90, Math.min(170, win.height * 0.2))
                radius: win.radius
                color: win.surface
                border.color: win.line
                clip: true

                SpeedGraph {
                    id: graph
                    anchors.fill: parent
                    anchors.margins: 1
                    points: backend.history
                    accent: theme.accent
                    foreground: win.fg
                }
                Label {
                    anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 10
                    text: qsTr("peak %1 · last %2 min").arg(win.speed(graph.peak / 1.15))
                                                         .arg(Math.max(1, Math.round(120 * backend.interval / 60)))
                    color: win.muted
                    font.pixelSize: 11
                }
                Row {
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 10
                    spacing: 14
                    Row {
                        spacing: 6
                        Rectangle { width: 14; height: 3; radius: 1; color: theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: qsTr("Download"); color: win.muted; font.pixelSize: 11 }
                    }
                    Row {
                        spacing: 6
                        Rectangle { width: 14; height: 1; color: win.muted; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: qsTr("Upload"); color: win.muted; font.pixelSize: 11 }
                    }
                }
            }

            // ------------------------------------------------------------ body
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 16

                // Devices
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: win.radius
                    color: win.surface
                    border.color: win.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: qsTr("Devices")
                                color: win.fg; font.bold: true; font.pixelSize: 16
                            }
                            Label {
                                text: (win.showIdle ? "" : qsTr("active only") + " · ") + (win.sortMode === "connection" ? qsTr("by connection") : win.sortMode === "name" ? qsTr("by name") : qsTr("by speed"))
                                color: win.muted; font.pixelSize: 12
                                Layout.leftMargin: 8
                            }
                            Item { Layout.fillWidth: true }
                            // A compact search box: Material's TextField is taller than this header.
                            Rectangle {
                                Layout.preferredWidth: 220
                                Layout.preferredHeight: 34
                                radius: win.smallRadius
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.color: search.activeFocus ? theme.accent : win.line
                                TextInput {
                                    id: search
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 10
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: win.fg
                                    selectionColor: theme.accent
                                    selectedTextColor: theme.accentForeground
                                    font.pixelSize: 14
                                    clip: true
                                    Keys.onReturnPressed: list.forceActiveFocus()
                                    Keys.onDownPressed: list.forceActiveFocus()
                                }
                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    visible: search.text === "" && !search.activeFocus
                                    text: qsTr("Search  /")
                                    color: win.muted
                                }
                            }
                        }

                        // column headings
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 10; Layout.rightMargin: 10
                            spacing: 12
                            Label { text: qsTr("Name"); color: win.muted; font.pixelSize: 11; Layout.fillWidth: true }
                            Label { text: qsTr("IP address"); color: win.muted; font.pixelSize: 11; Layout.preferredWidth: 120; visible: win.wide }
                            Label { text: qsTr("Connection"); color: win.muted; font.pixelSize: 11; Layout.preferredWidth: 80; visible: win.wide }
                            Label { text: qsTr("Down"); color: win.muted; font.pixelSize: 11; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                            Label { text: qsTr("Up"); color: win.muted; font.pixelSize: 11; Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight }
                            Item { Layout.preferredWidth: 30 }
                        }

                        ListView {
                            id: list
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: win.visibleClients
                            focus: true
                            keyNavigationEnabled: true
                            highlightMoveDuration: 0
                            ScrollBar.vertical: ScrollBar {}

                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                height: 46
                                radius: win.smallRadius
                                color: ListView.isCurrentItem && list.activeFocus ? Qt.rgba(1, 1, 1, 0.06)
                                     : hover.hovered ? Qt.rgba(1, 1, 1, 0.035) : "transparent"
                                readonly property bool busy: modelData.down + modelData.up >= 1000
                                HoverHandler { id: hover }
                                TapHandler { onTapped: list.currentIndex = row.index }
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: { list.currentIndex = row.index; win.openMenu(row.modelData) }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10; anchors.rightMargin: 10
                                    spacing: 12

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Rectangle {
                                            width: 7; height: 7; radius: 3.5
                                            color: row.busy ? theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Label {
                                                Layout.fillWidth: true
                                                textFormat: Text.PlainText
                                                text: row.modelData.name
                                                color: win.fg
                                                elide: Text.ElideRight
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                textFormat: Text.PlainText
                                                visible: text !== ""
                                                text: [row.modelData.type, win.wide ? "" : row.modelData.ip, win.wide ? "" : row.modelData.connection,
                                                       row.modelData.network === "guest" ? qsTr("Guest network") : ""].filter(s => s).join(" · ")
                                                color: win.muted
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Rectangle {
                                            visible: row.modelData.isNew
                                            implicitWidth: newLabel.implicitWidth + 10
                                            implicitHeight: newLabel.implicitHeight + 4
                                            radius: win.smallRadius
                                            color: theme.accent
                                            Label {
                                                id: newLabel
                                                anchors.centerIn: parent
                                                text: qsTr("NEW")
                                                color: theme.accentForeground
                                                font.pixelSize: 10; font.bold: true
                                            }
                                        }
                                    }
                                    Label {
                                        Layout.preferredWidth: 120
                                        visible: win.wide
                                        textFormat: Text.PlainText
                                        text: row.modelData.ip
                                        color: win.muted
                                        font.features: { "tnum": 1 }
                                    }
                                    Label {
                                        Layout.preferredWidth: 80
                                        visible: win.wide
                                        textFormat: Text.PlainText
                                        text: row.modelData.connection
                                        color: win.muted
                                    }
                                    Label {
                                        Layout.preferredWidth: 90
                                        horizontalAlignment: Text.AlignRight
                                        text: win.speed(row.modelData.down)
                                        color: row.busy ? win.fg : win.muted
                                        font.bold: row.modelData.down >= 1000
                                        font.features: { "tnum": 1 }
                                    }
                                    Label {
                                        Layout.preferredWidth: 90
                                        horizontalAlignment: Text.AlignRight
                                        text: win.speed(row.modelData.up)
                                        color: row.busy ? win.fg : win.muted
                                        font.features: { "tnum": 1 }
                                    }
                                    ToolButton {
                                        Layout.preferredWidth: 30
                                        implicitHeight: 30
                                        topInset: 0; bottomInset: 0
                                        text: "⊘"
                                        font.pixelSize: 16
                                        // Shown on hover or selection; never for this computer.
                                        opacity: (hover.hovered || (row.ListView.isCurrentItem && list.activeFocus)) && !win.isOwn(row.modelData.mac) ? 1 : 0
                                        enabled: opacity > 0 && !backend.blocking
                                        Material.foreground: win.danger
                                        ToolTip.visible: hovered && enabled
                                        ToolTip.text: qsTr("Block %1  (B)").arg(row.modelData.name)
                                        onClicked: win.askBlock(row.modelData)
                                    }
                                }
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: list.count === 0
                                text: backend.clients.length === 0 ? qsTr("No devices yet") : qsTr("No devices match")
                                color: win.muted
                            }
                        }
                    }
                }

                // Deco units
                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.fillHeight: true
                    radius: win.radius
                    color: win.surface
                    border.color: win.line

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        Label { text: qsTr("Deco units"); color: win.fg; font.bold: true; font.pixelSize: 16 }

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            contentWidth: availableWidth
                            clip: true

                        ColumnLayout {
                            width: parent.width
                            spacing: 10

                        Repeater {
                            model: backend.nodes
                            delegate: Rectangle {
                                id: unit
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: unitCol.implicitHeight + 20
                                radius: win.smallRadius
                                color: Qt.rgba(1, 1, 1, 0.03)
                                border.color: win.line
                                readonly property bool bad: !modelData.online || !modelData.internet

                                ColumnLayout {
                                    id: unitCol
                                    anchors.left: parent.left; anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 12; anchors.rightMargin: 6
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            color: unit.bad ? win.danger : theme.accent
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            text: unit.modelData.name
                                            color: win.fg; font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        ToolButton {
                                            text: "↻"
                                            font.pixelSize: 16
                                            implicitHeight: 30
                                            implicitWidth: 30
                                            topInset: 0; bottomInset: 0
                                            enabled: !backend.rebooting
                                            ToolTip.visible: hovered
                                            ToolTip.text: qsTr("Reboot %1").arg(unit.modelData.name)
                                            onClicked: win.askReboot([unit.modelData.mac], unit.modelData.name)
                                        }
                                    }
                                    Label {
                                        textFormat: Text.PlainText
                                        text: (unit.modelData.main ? qsTr("Main · ") : "") +
                                              (!unit.modelData.online ? qsTr("Offline")
                                               : !unit.modelData.internet ? qsTr("No internet") : qsTr("Online"))
                                        color: unit.bad ? win.danger : win.muted
                                        font.pixelSize: 12
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: unit.modelData.model + " · " + unit.modelData.ip
                                        color: Qt.darker(win.muted, 1.2)
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Label {
                            Layout.topMargin: 8
                            text: qsTr("Blocked devices")
                            color: win.fg; font.bold: true; font.pixelSize: 16
                        }
                        Label {
                            Layout.fillWidth: true
                            visible: backend.blocked.length === 0
                            wrapMode: Text.Wrap
                            text: backend.blockedError !== "" ? backend.blockedError
                                : backend.blockedKnown ? qsTr("No blocked devices")
                                : qsTr("Reading the blocked list…")
                            color: win.muted; font.pixelSize: 12
                        }
                        Repeater {
                            model: backend.blocked
                            delegate: Rectangle {
                                id: blockedRow
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: win.smallRadius
                                color: Qt.rgba(win.danger.r, win.danger.g, win.danger.b, 0.06)
                                border.color: Qt.rgba(win.danger.r, win.danger.g, win.danger.b, 0.25)
                                TapHandler {
                                    acceptedButtons: Qt.RightButton
                                    onTapped: win.openMenu(blockedRow.modelData)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12; anchors.rightMargin: 6
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Label {
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            text: blockedRow.modelData.name
                                            color: win.fg
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            textFormat: Text.PlainText
                                            text: blockedRow.modelData.mac
                                            color: win.muted; font.pixelSize: 11
                                        }
                                    }
                                    Button {
                                        flat: true
                                        text: qsTr("Unblock")
                                        enabled: !backend.blocking
                                        onClicked: win.pendingBlock = { mac: blockedRow.modelData.mac, name: blockedRow.modelData.name, unblock: true }
                                    }
                                }
                            }
                        }
                        }
                        }

                        Label {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            visible: backend.blockMessage !== "" || backend.blocking
                            text: backend.blocking ? qsTr("Talking to the Deco…") : backend.blockMessage
                            wrapMode: Text.Wrap
                            color: win.muted
                            font.pixelSize: 12
                        }
                        Label {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            visible: backend.rebootMessage !== ""
                            text: backend.rebootMessage
                            wrapMode: Text.Wrap
                            color: win.muted
                            font.pixelSize: 12
                        }
                        Button {
                            Layout.fillWidth: true
                            text: backend.rebooting ? qsTr("Rebooting…") : qsTr("Reboot all  (R)")
                            enabled: backend.nodes.length > 0 && !backend.rebooting
                            onClicked: win.askReboot([], qsTr("all Deco units"))
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: qsTr("Parental controls and QoS are only in the Deco phone app.")
                            color: Qt.darker(win.muted, 1.3)
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------- reboot confirm
        Rectangle {
            anchors.fill: parent
            visible: win.pendingReboot !== null
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: win.pendingReboot = null }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 420)
                implicitHeight: confirmCol.implicitHeight + 40
                radius: win.radius
                color: win.surface
                border.color: theme.accent

                ColumnLayout {
                    id: confirmCol
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12
                    Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: qsTr("Reboot %1?").arg(win.pendingReboot ? win.pendingReboot.label : "")
                        color: win.fg; font.bold: true; font.pixelSize: 17
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: qsTr("Devices connected through it lose internet for about two minutes.")
                        color: win.muted
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        Button { text: qsTr("Cancel  (Esc)"); flat: true; onClicked: win.pendingReboot = null }
                        Button {
                            id: confirmButton
                            text: qsTr("Reboot  (Enter)")
                            highlighted: true
                            onClicked: { backend.reboot(win.pendingReboot.macs); win.pendingReboot = null }
                        }
                    }
                }
            }
            Shortcut {
                sequences: ["Return", "Enter"]
                enabled: win.pendingReboot !== null
                context: Qt.ApplicationShortcut
                onActivated: confirmButton.clicked()
            }
        }

        // -------------------------------------------------------- block confirm
        Rectangle {
            anchors.fill: parent
            visible: win.pendingBlock !== null
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: win.pendingBlock = null }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 420)
                implicitHeight: blockCol.implicitHeight + 40
                radius: win.radius
                color: win.surface
                border.color: win.pendingBlock && !win.pendingBlock.unblock ? win.danger : theme.accent

                ColumnLayout {
                    id: blockCol
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12
                    Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        text: !win.pendingBlock ? ""
                              : win.pendingBlock.unblock ? qsTr("Unblock %1?").arg(win.pendingBlock.name)
                              : qsTr("Block %1?").arg(win.pendingBlock.name)
                        color: win.fg; font.bold: true; font.pixelSize: 17
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: win.pendingBlock && win.pendingBlock.unblock
                              ? qsTr("It can join the network again.")
                              : qsTr("It's disconnected and can't rejoin until you unblock it here or in the Deco app.")
                        color: win.muted
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        Button { text: qsTr("Cancel  (Esc)"); flat: true; onClicked: win.pendingBlock = null }
                        Button {
                            id: blockConfirm
                            text: win.pendingBlock && win.pendingBlock.unblock ? qsTr("Unblock  (Enter)") : qsTr("Block  (Enter)")
                            highlighted: true
                            Material.accent: win.pendingBlock && !win.pendingBlock.unblock ? win.danger : theme.accent
                            onClicked: {
                                const b = win.pendingBlock
                                win.pendingBlock = null
                                if (b.unblock) backend.unblock(b.mac, b.name)
                                else backend.block(b.mac, b.name)
                            }
                        }
                    }
                }
            }
            Shortcut {
                sequences: ["Return", "Enter"]
                enabled: win.pendingBlock !== null
                context: Qt.ApplicationShortcut
                onActivated: blockConfirm.clicked()
            }
        }

        // ---------------------------------------------------- right-click menu
        Menu {
            id: deviceMenu
            property var target: null
            readonly property bool own: target ? win.isOwn(target.mac) : false
            readonly property bool blockedNow: target ? win.isBlocked(target.mac) : false

            MenuItem {
                text: qsTr("Block")
                enabled: deviceMenu.target !== null && !deviceMenu.own && !deviceMenu.blockedNow && !backend.blocking
                onTriggered: win.askBlock(deviceMenu.target)
            }
            MenuItem {
                text: qsTr("Unblock")
                enabled: deviceMenu.blockedNow && !backend.blocking
                onTriggered: win.askUnblock(deviceMenu.target)
            }
            MenuSeparator {}
            MenuItem {
                text: qsTr("Copy IP address")
                enabled: deviceMenu.target !== null && (deviceMenu.target.ip || "") !== ""
                onTriggered: backend.copy(deviceMenu.target.ip)
            }
            MenuItem {
                text: qsTr("Copy MAC address")
                enabled: deviceMenu.target !== null
                onTriggered: backend.copy(deviceMenu.target.mac)
            }
        }

        // --------------------------------------------------------------- help
        Rectangle {
            anchors.fill: parent
            visible: win.helpVisible
            color: Qt.rgba(0, 0, 0, 0.6)
            MouseArea { anchors.fill: parent; onClicked: win.helpVisible = false }

            Rectangle {
                anchors.centerIn: parent
                width: 380
                implicitHeight: helpCol.implicitHeight + 40
                radius: win.radius
                color: win.surface
                border.color: theme.accent

                ColumnLayout {
                    id: helpCol
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 10
                    Label { text: qsTr("Keyboard shortcuts"); color: win.fg; font.bold: true; font.pixelSize: 17 }
                    Repeater {
                        model: [
                            ["/", qsTr("Search devices")],
                            ["Space", qsTr("Show or hide idle devices")],
                            ["S", qsTr("Sort by connection, name or speed")],
                            ["↑ ↓", qsTr("Move through devices")],
                            ["B", qsTr("Block the selected device")],
                            ["Menu", qsTr("Device menu (also right-click)")],
                            ["R", qsTr("Reboot all Deco units")],
                            ["Esc", qsTr("Clear search, close dialogs")],
                            ["?", qsTr("Show this help")],
                            ["Q", qsTr("Quit")]
                        ]
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Rectangle {
                                implicitWidth: Math.max(46, keyLabel.implicitWidth + 14)
                                implicitHeight: keyLabel.implicitHeight + 6
                                radius: win.smallRadius
                                color: Qt.rgba(1, 1, 1, 0.07)
                                Label { id: keyLabel; anchors.centerIn: parent; text: modelData[0]; color: theme.accent; font.bold: true }
                            }
                            Label { text: modelData[1]; color: win.fg; Layout.leftMargin: 8 }
                        }
                    }
                }
            }
        }
    }

    // Keeps "Updated n s ago" moving between status updates.
    Timer { id: clock; property int tick: 0; interval: 1000; repeat: true; running: true; onTriggered: tick++ }
}
