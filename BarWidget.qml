import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TodoModel.js" as TodoModel

BarWidget {
  id: root
  moduleName: TodoModel.PLUGIN_ID
  fixedEdge: "start"

  property int doneCount: 0
  property int totalCount: 0
  property string todayDate: ""
  property bool opened: false

  readonly property string todoScript: localPath(Qt.resolvedUrl("scripts/todo.py"))
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/daily-todos.json"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (error) { return value }
  }

  function cfg(name, fallback) {
    return TodoModel.configValue(name, root.settings, null, fallback)
  }

  function baseArgs() {
    return [
      "--vault-path", String(cfg("vaultPath", "")),
      "--daily-folder", String(cfg("dailyFolder", "Daily Notes")),
      "--backlog-days", String(cfg("backlogDays", 14)),
      "--max-backlog-tasks", String(cfg("maxBacklogTasks", 20))
    ]
  }

  function shellCmd(args) {
    if (root.bar) root.bar.run("omarchy-shell shell " + args + " " + TodoModel.PLUGIN_ID)
  }

  function refresh() {
    statusProcess.command = ["python3", root.todoScript].concat(root.baseArgs()).concat(["status"])
    if (!statusProcess.running) statusProcess.running = true
  }

  function applyStatus(payload) {
    if (payload.error) return
    root.doneCount = Number(payload.done || 0)
    root.totalCount = Number(payload.total || 0)
    root.todayDate = String(payload.date || "")
    stateFile.setText(TodoModel.writeStatePayload(root.todayDate, root.doneCount, root.totalCount))
  }

  function open() {
    shellCmd("summon")
    root.opened = true
  }

  function close() {
    shellCmd("hide")
    root.opened = false
  }

  function togglePanel() {
    shellCmd("toggle")
    root.opened = !root.opened
  }

  function openObsidian() {
    openProcess.command = ["python3", root.todoScript].concat(root.baseArgs()).concat(["open-path"])
    if (!openProcess.running) openProcess.running = true
  }

  function launchObsidianPayload(payload) {
    if (!payload || payload.error) return
    if (payload.uri) Util.execArgv(["obsidian", String(payload.uri)])
    else if (payload.path) Util.execArgv(["obsidian", String(payload.path)])
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var payload = TodoModel.parseJson(text())
      root.doneCount = Number(payload.done || 0)
      root.totalCount = Number(payload.total || 0)
      root.todayDate = String(payload.date || "")
    }
    onFileChanged: reload()
  }

  Process {
    id: statusProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(TodoModel.parseJson(text))
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

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u2713"
    tooltipText: strings.t("bar.tooltip")

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.MiddleButton) root.openObsidian()
      else root.togglePanel()
    }
  }
}
