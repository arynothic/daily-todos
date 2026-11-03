import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "TodoModel.js" as TodoModel

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property string errorText: ""
  property var todayTasks: []
  property var backlogItems: []
  property int doneCount: 0
  property int totalCount: 0
  property string todayPath: ""
  property real noteMtime: -1
  property string todayDate: ""
  property var layoutSettings: ({})

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property color muted: Commons.Color.muted
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int lineInsetX: Style.spacing.sm
  readonly property int headerInsetX: Style.spacing.md
  property int cardWidth: Math.min(Style.space(420), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(520), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(40), Style.font.body + Style.spacing.rowPaddingX * 2)

  readonly property string todoScript: localPath(Qt.resolvedUrl("scripts/todo.py"))
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/daily-todos.json"
  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function reloadLayoutSettings() {
    layoutSettings = TodoModel.settingsFromShellJson(shellConfigFile.text(), TodoModel.PLUGIN_ID) || ({})
  }

  function cfg(name, fallback) {
    return TodoModel.configValue(name, layoutSettings, manifest, fallback)
  }

  function baseArgs() {
    return [
      "--vault-path", String(cfg("vaultPath", "")),
      "--daily-folder", String(cfg("dailyFolder", "Daily Notes")),
      "--backlog-days", String(cfg("backlogDays", 14)),
      "--max-backlog-tasks", String(cfg("maxBacklogTasks", 20))
    ]
  }

  function cliCommand(subcommand, extra) {
    var cmd = ["python3", root.todoScript].concat(root.baseArgs()).concat([subcommand])
    if (extra) cmd = cmd.concat(extra)
    return cmd
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    quickAddInput.text = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.errorText = ""
    reloadLayoutSettings()
    refreshAll()
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      quickAddInput.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(TodoModel.PLUGIN_ID)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function writeState() {
    stateFile.setText(TodoModel.writeStatePayload(root.todayDate, root.doneCount, root.totalCount))
  }

  function applyTodayPayload(payload) {
    if (payload.error) {
      root.errorText = payload.error === "external_change"
        ? strings.t("panel.error.externalChange")
        : strings.t("panel.error.io")
      return
    }
    root.todayTasks = TodoModel.tasksFromListToday(payload)
    root.todayPath = String(payload.todayPath || "")
    root.noteMtime = payload.mtime === null || payload.mtime === undefined ? -1 : Number(payload.mtime)
    root.todayDate = String(payload.date || "")
    var done = 0
    for (var i = 0; i < root.todayTasks.length; i++)
      if (root.todayTasks[i].done) done++
    root.doneCount = done
    root.totalCount = root.todayTasks.length
    root.errorText = ""
    rebuildTodayModel()
    writeState()
  }

  function applyBacklogPayload(payload) {
    root.backlogItems = TodoModel.backlogFromPayload(payload)
    rebuildBacklogModel()
  }

  function rebuildTodayModel() {
    todayModel.clear()
    for (var i = 0; i < root.todayTasks.length; i++) {
      var task = root.todayTasks[i]
      todayModel.append({ line: task.line, done: task.done, text: task.text, index: i })
    }
    if (todayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= todayModel.count) root.selectedIndex = todayModel.count - 1
  }

  function rebuildBacklogModel() {
    backlogModel.clear()
    for (var j = 0; j < root.backlogItems.length; j++) {
      var item = root.backlogItems[j]
      backlogModel.append({ date: item.date, key: item.key, text: item.text, index: j })
    }
  }

  function refreshAll() {
    listTodayProcess.command = root.cliCommand("list-today")
    listBacklogProcess.command = root.cliCommand("list-backlog")
    if (!listTodayProcess.running) listTodayProcess.running = true
    if (!listBacklogProcess.running) listBacklogProcess.running = true
  }

  function select(delta) {
    if (todayModel.count === 0) return
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? todayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + todayModel.count) % todayModel.count
    }
    taskList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function toggleSelected() {
    if (selectedIndex < 0 || selectedIndex >= todayModel.count) return
    var row = todayModel.get(selectedIndex)
    toggleProcess.command = root.cliCommand("toggle", ["--line", String(row.line), "--mtime", String(root.noteMtime)])
    if (!toggleProcess.running) toggleProcess.running = true
  }

  function submitQuickAdd() {
    var text = root.filterText.trim()
    if (!text) return
    addProcess.command = root.cliCommand("add", ["--text", text, "--mtime", String(root.noteMtime)])
    root.filterText = ""
    quickAddInput.text = ""
    if (!addProcess.running) addProcess.running = true
    Qt.callLater(function() { quickAddInput.forceActiveFocus() })
  }

  function setFilter(next) {
    root.filterText = next
    if (quickAddInput.text !== next) quickAddInput.text = next
  }

  function carryAllBacklog() {
    if (backlogModel.count === 0) return
    var keys = []
    for (var i = 0; i < backlogModel.count; i++)
      keys.push(String(backlogModel.get(i).key))
    carryProcess.command = root.cliCommand("carry", ["--keys"].concat(keys).concat(["--mtime", String(root.noteMtime)]))
    if (!carryProcess.running) carryProcess.running = true
  }

  function openObsidian() {
    openProcess.command = root.cliCommand("open-path")
    if (!openProcess.running) openProcess.running = true
  }

  function launchObsidianPayload(payload) {
    if (!payload || payload.error) return
    if (payload.uri) Util.execArgv(["obsidian", String(payload.uri)])
    else if (payload.path) Util.execArgv(["obsidian", String(payload.path)])
  }

  ListModel { id: todayModel }
  ListModel { id: backlogModel }

  FileView {
    id: shellConfigFile
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.reloadLayoutSettings()
    onFileChanged: reload()
  }

  FileView {
    id: noteFile
    path: root.todayPath
    watchChanges: root.todayPath !== ""
    printErrors: false
    onFileChanged: reloadDebounce.restart()
    onLoaded: reloadDebounce.restart()
  }

  Timer {
    id: reloadDebounce
    interval: 150
    onTriggered: root.refreshAll()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: listTodayProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyTodayPayload(TodoModel.parseJson(text))
    }
  }

  Process {
    id: listBacklogProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyBacklogPayload(TodoModel.parseJson(text))
    }
  }

  Process {
    id: toggleProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(raw) {
        var payload = TodoModel.parseJson(raw)
        if (payload.error === "external_change") {
          root.errorText = strings.t("panel.error.externalChange")
          root.refreshAll()
          return
        }
        root.applyTodayPayload(payload)
      }
    }
  }

  Process {
    id: addProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(raw) {
        var payload = TodoModel.parseJson(raw)
        if (payload.error === "external_change") {
          root.errorText = strings.t("panel.error.externalChange")
          root.refreshAll()
          return
        }
        root.applyTodayPayload(payload)
        root.refreshAll()
      }
    }
  }

  Process {
    id: carryProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(raw) {
        root.applyTodayPayload(TodoModel.parseJson(raw))
        if (!listBacklogProcess.running) listBacklogProcess.running = true
      }
    }
  }

  Process {
    id: openProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: function(raw) {
        root.launchObsidianPayload(TodoModel.parseJson(raw))
      }
    }
  }

  Component.onCompleted: {
    reloadLayoutSettings()
    refreshAll()
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    WlrLayershell.namespace: "omarchy-daily-todos"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.filterText.trim()) root.submitQuickAdd()
            else root.toggleSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Space && !root.filterText.trim()) {
            root.toggleSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            if (!root.filterText) root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            if (!root.filterText) root.select(-1)
            event.accepted = true
          } else if (event.text && event.text.length === 1
              && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
              && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
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
          color: "transparent"

          Row {
            anchors.fill: parent
            anchors.leftMargin: root.headerInsetX
            anchors.rightMargin: root.headerInsetX
            spacing: Style.spacing.sm

            Text {
              id: headerTitle
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              text: strings.t("panel.title")
            }

            Item { width: Math.max(0, parent.width - headerTitle.width - progressHeader.width - parent.spacing * 2); height: 1 }

            Text {
              id: progressHeader
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: strings.t("panel.progress")
                .arg(Commons.I18n.formatNumber(root.doneCount))
                .arg(Commons.I18n.formatNumber(root.totalCount))
            }
          }
        }

        Rectangle {
          width: parent.width - root.lineInsetX * 2
          anchors.horizontalCenter: parent.horizontalCenter
          height: Style.space(4)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            height: parent.height
            width: parent.width * (root.totalCount > 0 ? root.doneCount / root.totalCount : 0)
            radius: height / 2
            color: Commons.Color.accent
            Behavior on width {
              NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
            }
          }
        }

        Text {
          visible: root.errorText !== ""
          width: parent.width - root.lineInsetX * 2
          anchors.left: parent.left
          anchors.leftMargin: root.lineInsetX
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          text: root.errorText
        }

        ListView {
          id: taskList
          width: parent.width - root.lineInsetX * 2
          anchors.horizontalCenter: parent.horizontalCenter
          height: Math.max(Style.space(140), card.height * 0.42)
          clip: true
          model: todayModel
          spacing: Style.spacing.xs

          delegate: Rectangle {
            width: taskList.width
            height: root.rowHeight
            radius: Style.space(6)
            color: index === root.selectedIndex ? root.selectedBackground : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm
              anchors.rightMargin: Style.spacing.sm
              spacing: Style.spacing.sm

              Text {
                width: Style.space(18)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: model.done ? root.muted : root.foreground
                text: model.done ? "✓" : "○"
              }

              Text {
                width: parent.width - Style.space(18) - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                color: model.done ? root.muted : root.foreground
                text: model.text
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: {
                root.selectedIndex = index
                root.cursorActive = true
                root.toggleSelected()
              }
            }
          }
        }

        Text {
          visible: todayModel.count === 0
          width: parent.width - root.lineInsetX * 2
          anchors.left: parent.left
          anchors.leftMargin: root.lineInsetX
          textFormat: Text.PlainText
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          text: strings.t("panel.emptyToday")
        }

        Rectangle {
          width: parent.width - root.lineInsetX * 2
          anchors.horizontalCenter: parent.horizontalCenter
          height: Style.space(36)
          radius: Style.space(8)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          FilterInput {
            id: quickAddInput
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            keyHandler: keyCatcher
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            onTextChanged: if (text !== root.filterText) root.filterText = text
            onAccepted: root.submitQuickAdd()
          }

          Text {
            anchors.fill: quickAddInput
            verticalAlignment: Text.AlignVCenter
            visible: !root.filterText && !quickAddInput.preeditText
            textFormat: Text.PlainText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            color: root.muted
            text: strings.t("panel.quickAdd.placeholder")
            elide: Text.ElideRight
            enabled: false
          }
        }

        Column {
          visible: backlogModel.count > 0
          width: parent.width - root.lineInsetX * 2
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xs

          Row {
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: strings.t("panel.backlog.title")
            }

            Button {
              text: strings.t("panel.backlog.carry")
              fontFamily: root.fontFamily
              foreground: root.foreground
              onClicked: root.carryAllBacklog()
            }
          }

          Repeater {
            model: backlogModel
            delegate: Text {
              width: parent.width
              elide: Text.ElideRight
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              text: model.date + " · " + model.text
            }
          }
        }

        Button {
          anchors.left: parent.left
          anchors.leftMargin: root.lineInsetX
          text: strings.t("panel.openObsidian")
          fontFamily: root.fontFamily
          foreground: root.foreground
          onClicked: root.openObsidian()
        }
      }
    }
  }
}
