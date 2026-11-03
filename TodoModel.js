.pragma library

function parseJson(raw) {
  try {
    return JSON.parse(String(raw || "{}"))
  } catch (e) {
    return { error: "parse" }
  }
}

function progressFrom(payload) {
  var done = Number(payload.done || 0)
  var total = Number(payload.total || 0)
  if (!isFinite(done)) done = 0
  if (!isFinite(total)) total = 0
  return { done: done, total: total, fraction: total > 0 ? done / total : 0 }
}

function tasksFromListToday(payload) {
  if (!payload || !Array.isArray(payload.tasks)) return []
  return payload.tasks.map(function(t) {
    return {
      line: Number(t.line),
      done: t.done === true,
      text: String(t.text || "")
    }
  })
}

function backlogFromPayload(payload) {
  if (!payload || !Array.isArray(payload.items)) return []
  return payload.items.map(function(item) {
    return {
      date: String(item.date || ""),
      line: Number(item.line),
      text: String(item.text || ""),
      key: String(item.key || "")
    }
  })
}

function writeStatePayload(date, done, total) {
  return JSON.stringify({
    date: String(date || ""),
    done: Number(done || 0),
    total: Number(total || 0)
  }) + "\n"
}

var PLUGIN_ID = "io.github.arynothic.daily-todos"

function settingsFromShellJson(raw, pluginId) {
  var id = pluginId || PLUGIN_ID
  try {
    var config = JSON.parse(String(raw || "{}"))
    var layout = config.bar && config.bar.layout
    if (!layout) return null
    var sections = ["left", "centerBegin", "center", "centerEnd", "right", "tray"]
    for (var s = 0; s < sections.length; s++) {
      var list = layout[sections[s]]
      if (!Array.isArray(list)) continue
      for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        if (entry && String(entry.id || "") === id) return entry
      }
    }
  } catch (e) {}
  return null
}

function configValue(name, settings, manifest, fallback) {
  if (settings && settings[name] !== undefined && settings[name] !== null)
    return settings[name]
  var defs = manifest && manifest.barWidget && manifest.barWidget.defaults
  if (defs && defs[name] !== undefined && defs[name] !== null) return defs[name]
  return fallback
}
