# Daily Todo (Obsidian)

Manage today’s tasks from the Omarchy desktop without opening Obsidian every time. The plugin reads and writes the same Markdown checkbox lines in your **daily notes**—Obsidian stays the source of truth; headings, links, and the rest of each note are left alone.

**Plugin id:** `io.github.arynothic.daily-todos`

## Install

Plugins run as unsandboxed code inside `omarchy-shell`. Only install repos you trust.

```bash
omarchy plugin add https://github.com/arynothic/daily-todos.git --enable
```

Pick a bar section when prompted (default: right). Set **Obsidian vault** and **Daily notes folder** in the plugin’s bar settings before use.

Optional keyboard binding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + T", "Daily todos", "omarchy-shell shell toggle io.github.arynothic.daily-todos")
```

Then `hyprctl reload` if needed.

## Remove

```bash
omarchy plugin remove io.github.arynothic.daily-todos
```

## Configure bar placement

```bash
omarchy bar move io.github.arynothic.daily-todos --section left
```

## Update

```bash
omarchy plugin update io.github.arynothic.daily-todos
```

## What you get

- **Floating panel** — today’s checklist, progress, quick add, and backlog from recent days
- **Bar control** — checkmark icon on the bar; click to open the panel
- **Live sync** — edits in the panel appear in the note file; saves in Obsidian refresh the panel within about a second

Tasks are standard list items: `- [ ]` open, `- [x]` done (same markers as Obsidian: `x`, `X`, `-`).

---

## Open the panel

| Action | How |
|--------|-----|
| Keyboard | **Super + Alt + T** (if bound) |
| Mouse | Click the **Daily Todo** icon on the bar |

Click outside the card or press **Escape** to close.

---

## Using the panel

**Today** — All checkbox tasks from today’s daily note (`YYYY-MM-DD.md` in your daily folder). Click a row or focus it and press **Space** / **Enter** to toggle done.

**Progress** — Header shows completed vs total and a thin progress bar.

**Quick add** — Type at the bottom and press **Enter**. Appends `- [ ] your text` to today’s file. If today’s note does not exist yet, the plugin creates it with only the new task lines.

**From earlier** — Incomplete tasks from past daily notes (within your backlog settings). **Carry to today** copies them as new `- [ ]` lines on today’s note; the original days’ notes are not modified.

**Open in Obsidian** — Opens today’s daily note via `obsidian://open?vault=…&file=…`.

### Keyboard (while panel is focused)

| Key | Action |
|-----|--------|
| **↑** / **k**, **↓** / **j** | Move selection |
| **Space** / **Enter** | Toggle selected task (or submit quick add if the add field has text) |
| **Escape** | Close panel |
| Type | Quick-add text (backspace/editing supported) |

---

## Obsidian setup

| Setting | Default |
|---------|---------|
| Vault path | *(empty — you must set this)* |
| Daily notes folder | `Daily Notes` (relative to vault root) |
| Note filename | `YYYY-MM-DD.md` (ISO date) |

Point **Daily notes folder** at wherever Obsidian stores dated notes (including nested paths like `journal/daily`).

---

## Plugin settings

In Omarchy bar / plugin settings for **Daily Todo**:

- **Obsidian vault** — Root directory of the vault
- **Daily notes folder** — Relative path from vault root to dated notes
- **Backlog scan (days)** — How many calendar days back to search (default 14)
- **Max backlog tasks** — Cap on “From earlier” rows (default 20)

Settings are stored in `~/.config/omarchy/shell.json` under your bar layout entry.

---

## Dependencies

- **Python 3** — used by `scripts/todo.py` (no extra pip packages)
- **Obsidian** — optional; only needed for “Open in Obsidian”

---

## Waybar (optional)

The plugin writes `~/.local/state/omarchy/daily-todos.json`:

```json
{"date":"2026-11-03","done":2,"total":5}
```

Example module:

```json
"custom/daily-todo": {
  "exec": "jq -r '[.done,.total]|join(\"/\")' ~/.local/state/omarchy/daily-todos.json 2>/dev/null || echo 0/0",
  "interval": 30,
  "tooltip": true
}
```

---

## Troubleshooting

**Panel does not open** — `omarchy restart shell`. Check `omarchy plugin list`.

**Empty today list** — Set **vault path** and **daily notes folder**. Today’s file must be `YYYY-MM-DD.md` under that folder.

**“Note changed externally”** — Obsidian and the panel edited the same file at once; reload and retry.

**Shortcut does nothing** — Confirm the binding in `~/.config/hypr/bindings.lua`.

---

## Development

```bash
git clone https://github.com/arynothic/daily-todos.git
cd daily-todos
omarchy plugin validate .
python3 tests/run_tests.py
```

Symlink or copy into `~/.config/omarchy/plugins/io.github.arynothic.daily-todos` while iterating; the shell hot-reloads local plugin changes.

## Marketplace

To list this plugin on [plugins.omarchy.org](https://plugins.omarchy.org/publish.html), open the marketplace submission form with this repository URL after the first public release.

## License

MIT — see [LICENSE](LICENSE).
