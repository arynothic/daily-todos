#!/usr/bin/env python3
"""Read and write Markdown checkbox tasks in Obsidian daily notes."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import quote

DONE_MARKERS = frozenset("xX-")
TASK_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?P<bullet>[-*+])[ \t]+"
    r"\[(?P<mark>[ xX\-])\][ \t]+(?P<text>.*)$"
)
DATE_FILE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.md$")


@dataclass(frozen=True)
class Config:
    vault_path: Path
    daily_folder: str
    backlog_days: int
    max_backlog_tasks: int
    today: dt.date

    @property
    def daily_dir(self) -> Path:
        return self.vault_path / self.daily_folder

    def note_path(self, day: dt.date) -> Path:
        return self.daily_dir / f"{day.isoformat()}.md"


@dataclass
class Task:
    line: int
    done: bool
    text: str
    indent: str
    bullet: str


def expand_path(value: str) -> Path:
    return Path(os.path.expanduser(value)).resolve()


def parse_date(value: str | None) -> dt.date:
    if not value:
        return dt.date.today()
    return dt.date.fromisoformat(value)


def load_config(args: argparse.Namespace) -> Config:
    raw_vault = str(args.vault_path or "").strip()
    if not raw_vault:
        raise ValueError("vault path is not configured; set Obsidian vault in plugin settings")
    vault = expand_path(raw_vault)
    return Config(
        vault_path=vault,
        daily_folder=str(args.daily_folder).strip("/").replace("\\", "/"),
        backlog_days=max(1, int(args.backlog_days)),
        max_backlog_tasks=max(1, int(args.max_backlog_tasks)),
        today=parse_date(args.date),
    )


def read_lines(path: Path) -> list[str]:
    if not path.is_file():
        return []
    text = path.read_text(encoding="utf-8")
    if not text:
        return []
    if not text.endswith("\n"):
        text += "\n"
    return text.splitlines(keepends=True)


def file_mtime(path: Path) -> float | None:
    try:
        return path.stat().st_mtime
    except OSError:
        return None


def parse_tasks(lines: list[str]) -> list[Task]:
    tasks: list[Task] = []
    for index, raw in enumerate(lines):
        line = raw.rstrip("\n")
        match = TASK_RE.match(line)
        if not match:
            continue
        mark = match.group("mark")
        tasks.append(
            Task(
                line=index,
                done=mark in DONE_MARKERS,
                text=match.group("text").strip(),
                indent=match.group("indent"),
                bullet=match.group("bullet"),
            )
        )
    return tasks


def sanitize_task_text(text: str) -> str:
    cleaned = "".join(ch for ch in text if ch == "\t" or ord(ch) >= 32)
    return cleaned.strip()


def atomic_write(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    content = "".join(lines)
    fd, tmp_name = tempfile.mkstemp(
        prefix=".todo-", suffix=".md", dir=str(path.parent)
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)


def check_mtime(path: Path, expected: float | None) -> None:
    if expected is None:
        return
    current = file_mtime(path)
    if current is not None and abs(current - expected) > 1e-6:
        raise RuntimeError("external_change")


def toggle_line(lines: list[str], line_index: int) -> list[str]:
    if line_index < 0 or line_index >= len(lines):
        raise ValueError("invalid line")
    raw = lines[line_index].rstrip("\n")
    match = TASK_RE.match(raw)
    if not match:
        raise ValueError("not a task line")
    mark = match.group("mark")
    new_mark = " " if mark in DONE_MARKERS else "x"
    prefix = raw[: match.start("mark")]
    suffix = raw[match.end("mark") :]
    updated = f"{prefix}{new_mark}{suffix}\n"
    out = list(lines)
    out[line_index] = updated
    return out


def append_tasks(path: Path, texts: list[str], create: bool) -> None:
    lines = read_lines(path)
    if not lines and not create and not path.is_file():
        lines = []
    for text in texts:
        safe = sanitize_task_text(text)
        if not safe:
            continue
        lines.append(f"- [ ] {safe}\n")
    if not lines and not texts:
        return
    atomic_write(path, lines)


def cmd_status(cfg: Config) -> dict[str, Any]:
    path = cfg.note_path(cfg.today)
    lines = read_lines(path)
    tasks = parse_tasks(lines)
    done = sum(1 for task in tasks if task.done)
    total = len(tasks)
    return {
        "date": cfg.today.isoformat(),
        "todayPath": str(path),
        "done": done,
        "total": total,
        "mtime": file_mtime(path),
        "exists": path.is_file(),
    }


def cmd_list_today(cfg: Config) -> dict[str, Any]:
    path = cfg.note_path(cfg.today)
    lines = read_lines(path)
    tasks = parse_tasks(lines)
    return {
        "date": cfg.today.isoformat(),
        "todayPath": str(path),
        "mtime": file_mtime(path),
        "tasks": [
            {"line": t.line, "done": t.done, "text": t.text} for t in tasks
        ],
    }


def iter_backlog_days(cfg: Config) -> list[dt.date]:
    days: list[dt.date] = []
    folder = cfg.daily_dir
    if not folder.is_dir():
        return days
    for entry in folder.iterdir():
        if not entry.is_file():
            continue
        match = DATE_FILE_RE.match(entry.name)
        if not match:
            continue
        day = dt.date.fromisoformat(match.group(1))
        if day >= cfg.today:
            continue
        if (cfg.today - day).days > cfg.backlog_days:
            continue
        days.append(day)
    days.sort(reverse=True)
    return days


def cmd_list_backlog(cfg: Config) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    for day in iter_backlog_days(cfg):
        path = cfg.note_path(day)
        for task in parse_tasks(read_lines(path)):
            if task.done:
                continue
            items.append(
                {
                    "date": day.isoformat(),
                    "line": task.line,
                    "text": task.text,
                    "key": f"{day.isoformat()}:{task.line}",
                }
            )
            if len(items) >= cfg.max_backlog_tasks:
                break
        if len(items) >= cfg.max_backlog_tasks:
            break
    return {"items": items}


def cmd_toggle(cfg: Config, line: int, mtime: float | None) -> dict[str, Any]:
    path = cfg.note_path(cfg.today)
    check_mtime(path, mtime)
    lines = read_lines(path)
    if not lines and not path.is_file():
        raise RuntimeError("missing_note")
    updated = toggle_line(lines, line)
    atomic_write(path, updated)
    return cmd_list_today(cfg)


def cmd_add(cfg: Config, text: str, mtime: float | None) -> dict[str, Any]:
    path = cfg.note_path(cfg.today)
    check_mtime(path, mtime)
    create = not path.is_file()
    append_tasks(path, [text], create=create)
    return cmd_list_today(cfg)


def cmd_carry(cfg: Config, keys: list[str], mtime: float | None) -> dict[str, Any]:
    path = cfg.note_path(cfg.today)
    check_mtime(path, mtime)
    backlog = cmd_list_backlog(cfg)
    by_key = {item["key"]: item for item in backlog["items"]}
    texts: list[str] = []
    for key in keys:
        item = by_key.get(key)
        if item:
            texts.append(item["text"])
    if texts:
        append_tasks(path, texts, create=True)
    return {"carried": len(texts), **cmd_list_today(cfg)}


def resolve_vault_label(vault_path: Path) -> str:
    obsidian_conf = Path.home() / ".config/obsidian/obsidian.json"
    target = vault_path.resolve()
    if obsidian_conf.is_file():
        try:
            data = json.loads(obsidian_conf.read_text(encoding="utf-8"))
            for entry in data.get("vaults", {}).values():
                entry_path = Path(str(entry.get("path", ""))).expanduser().resolve()
                if entry_path == target:
                    return target.name
        except (OSError, json.JSONDecodeError, TypeError, ValueError):
            pass
    return target.name


def obsidian_uri(cfg: Config, note_path: Path) -> str:
    resolved = note_path.resolve()
    vault = cfg.vault_path.resolve()
    try:
        rel = resolved.relative_to(vault)
    except ValueError:
        return "obsidian://open?path=" + quote(str(resolved))
    vault_name = resolve_vault_label(vault)
    file_path = str(rel).replace("\\", "/")
    return (
        "obsidian://open?vault="
        + quote(vault_name)
        + "&file="
        + quote(file_path, safe="/")
    )


def cmd_open_path(cfg: Config) -> dict[str, Any]:
    path = cfg.note_path(cfg.today)
    uri = obsidian_uri(cfg, path)
    return {"path": str(path), "uri": uri}


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--vault-path",
        default="",
    )
    parser.add_argument(
        "--daily-folder",
        default="Daily Notes",
    )
    parser.add_argument("--backlog-days", type=int, default=14)
    parser.add_argument("--max-backlog-tasks", type=int, default=20)
    parser.add_argument("--date", default="")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Obsidian daily todo helper")
    add_common_args(parser)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status")
    sub.add_parser("list-today")
    sub.add_parser("list-backlog")
    sub.add_parser("open-path")

    toggle = sub.add_parser("toggle")
    toggle.add_argument("--line", type=int, required=True)
    toggle.add_argument("--mtime", type=float, default=-1)

    add = sub.add_parser("add")
    add.add_argument("--text", required=True)
    add.add_argument("--mtime", type=float, default=-1)

    carry = sub.add_parser("carry")
    carry.add_argument("--keys", nargs="+", default=[])
    carry.add_argument("--mtime", type=float, default=-1)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    cfg = load_config(args)

    try:
        if args.command == "status":
            payload = cmd_status(cfg)
        elif args.command == "list-today":
            payload = cmd_list_today(cfg)
        elif args.command == "list-backlog":
            payload = cmd_list_backlog(cfg)
        elif args.command == "open-path":
            payload = cmd_open_path(cfg)
        elif args.command == "toggle":
            mtime = None if args.mtime < 0 else float(args.mtime)
            payload = cmd_toggle(cfg, args.line, mtime)
        elif args.command == "add":
            mtime = None if args.mtime < 0 else float(args.mtime)
            payload = cmd_add(cfg, args.text, mtime)
        elif args.command == "carry":
            mtime = None if args.mtime < 0 else float(args.mtime)
            payload = cmd_carry(cfg, args.keys, mtime)
        else:
            raise RuntimeError("unknown command")
    except RuntimeError as error:
        if str(error) == "external_change":
            print(json.dumps({"error": "external_change"}))
            return 2
        print(json.dumps({"error": str(error)}))
        return 1
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        return 1

    print(json.dumps(payload, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
