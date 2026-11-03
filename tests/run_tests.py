#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "todo.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures"


def run_cmd(vault: Path, command: str, *extra: str, folder: str = "Dialy Notes", date: str = "", backlog_days: int = 0) -> dict:
    cmd = [
        sys.executable,
        str(SCRIPT),
        "--vault-path",
        str(vault),
        "--daily-folder",
        folder,
    ]
    if backlog_days > 0:
        cmd.extend(["--backlog-days", str(backlog_days)])
    if date:
        cmd.extend(["--date", date])
    cmd.append(command)
    cmd.extend(extra)
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr or result.stdout
    return json.loads(result.stdout)


def test_parse_and_toggle(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    note_dir = vault / "Dialy Notes"
    note_dir.mkdir(parents=True, exist_ok=True)
    sample = FIXTURES / "sample-day.md"
    target = note_dir / "2026-09-13.md"
    shutil.copy(sample, target)

    listed = run_cmd(vault, "list-today", date="2026-09-13")
    assert len(listed["tasks"]) == 7
    assert listed["tasks"][0]["done"] is True

    toggled = run_cmd(vault, "toggle", "--line", "2", date="2026-09-13")
    assert toggled["tasks"][1]["done"] is True

    text = target.read_text(encoding="utf-8")
    assert "- [x] https://www.youtube.com" in text
    assert "# Todo's" in text


def test_add_creates_note(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    run_cmd(vault, "add", "--text", "Ship plugin", date="2026-11-03")
    note = vault / "Dialy Notes" / "2026-11-03.md"
    assert note.is_file()
    assert "- [ ] Ship plugin" in note.read_text(encoding="utf-8")


def test_backlog_and_carry(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    note_dir = vault / "Dialy Notes"
    note_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy(FIXTURES / "sample-day.md", note_dir / "2026-09-13.md")

    backlog = run_cmd(vault, "list-backlog", date="2026-11-03", backlog_days=60)
    assert len(backlog["items"]) >= 1

    key = backlog["items"][0]["key"]
    carried = run_cmd(vault, "carry", "--keys", key, date="2026-11-03", backlog_days=60)
    assert carried["carried"] == 1
    today = (vault / "Dialy Notes" / "2026-11-03.md").read_text(encoding="utf-8")
    assert "- [ ]" in today


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        test_parse_and_toggle(base)
        test_add_creates_note(base)
        test_backlog_and_carry(base)
    print("ok")
