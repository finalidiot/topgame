"""Conservative shared workspace paths and artifact helpers (stdlib only)."""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

TASK_PATTERN = re.compile(r"^\d{3}[A-Z](?:\.\d+)*$")
CATEGORIES = ("video", "images", "frames", "logs", "manifests", "benchmarks", "temp")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def qa_root(override=None) -> Path:
    value = override or os.environ.get("TOPGAME_QA_ROOT")
    result = Path(value).expanduser().resolve() if value else repo_root().parent / "GyroBrothers-QA"
    if result == repo_root() or repo_root() in result.parents:
        raise ValueError("QA output must be outside the game repository")
    return result


def valid_task(task: str) -> str:
    if not TASK_PATTERN.fullmatch(task):
        raise ValueError("Use a task ID such as 002C.5.1 or 003A")
    return task


def create_task_workspace(task: str, root=None) -> Path:
    base = qa_root(root).resolve()
    path = base / valid_task(task)
    if is_link(path) or path.resolve() != path or base not in path.resolve().parents:
        raise ValueError("Task directory must stay inside the configured QA root")
    for category in CATEGORIES:
        destination = path / category
        if is_link(destination) or destination.resolve() != destination or path not in destination.resolve().parents:
            raise ValueError(f"Unsafe task category: {destination}")
    for category in CATEGORIES:
        (path / category).mkdir(parents=True, exist_ok=True)
    return path


def find_tool(name: str, override=None) -> str:
    env = {"godot": "TOPGAME_GODOT", "ffmpeg": "TOPGAME_FFMPEG", "aseprite": "TOPGAME_ASEPRITE"}
    configured = override or os.environ.get(env.get(name, "TOPGAME_" + name.upper()))
    if configured:
        found = shutil.which(str(configured))
        if found:
            return found
        if Path(configured).is_file():
            return str(Path(configured).resolve())
        raise FileNotFoundError(f"Configured {name} executable does not exist: {configured}")
    for candidate in {"godot": ("godot", "godot_console"), "ffmpeg": ("ffmpeg",), "aseprite": ("aseprite",)}.get(name, (name,)):
        if found := shutil.which(candidate):
            return found
    defaults = {
        "godot": [Path("E:/Desktop/Godot_v4.7.2-stable_win64_console.exe")],
        "aseprite": [Path("F:/SteamLibrary/steamapps/common/Aseprite/Aseprite.exe")],
        "ffmpeg": list((qa_root() / "archive/tools/imageio_ffmpeg/binaries").glob("ffmpeg*.exe")),
    }
    for candidate in defaults.get(name, []):
        if candidate.is_file():
            return str(candidate.resolve())
    raise FileNotFoundError(f"Set {env.get(name, 'TOPGAME_' + name.upper())} or put {name} on PATH")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def is_link(path: Path) -> bool:
    return path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction())


def git_paths(*args) -> set[str]:
    data = subprocess.check_output(["git", "ls-files", "-z", *args], cwd=repo_root())
    return set(data.decode("utf-8").rstrip("\0").split("\0")) - {""}


def audit(root=None, duplicate_min_bytes=65536) -> dict:
    """Read-only audit. Reparse points are never traversed."""
    project = repo_root()
    tracked = git_paths()
    ignored = git_paths("--others", "--ignored", "--exclude-standard")
    rows = []
    for folder, dirs, files in os.walk(project, followlinks=False):
        dirs[:] = [d for d in dirs if d not in {".git", ".godot", "__pycache__"} and not is_link(Path(folder) / d)]
        for name in files:
            path = Path(folder) / name
            if is_link(path) or name == ".git":
                continue
            rel = path.relative_to(project).as_posix()
            rows.append({"path": rel, "bytes": path.stat().st_size, "tracked": rel in tracked, "ignored": rel in ignored})
    candidates = defaultdict(list)
    for row in rows:
        if row["bytes"] >= duplicate_min_bytes or Path(row["path"]).suffix.lower() in {".exe", ".mp4", ".aseprite"}:
            candidates[row["bytes"]].append(row)
    duplicates = []
    for group in candidates.values():
        if len(group) < 2:
            continue
        hashed = defaultdict(list)
        for row in group:
            hashed[sha256(project / row["path"])].append(row["path"])
        duplicates.extend({"sha256": digest, "bytes": group[0]["bytes"], "paths": paths} for digest, paths in hashed.items() if len(paths) > 1)
    text_extensions = {".py", ".ps1", ".gd", ".lua", ".bat", ".cmd", ".cfg"}
    stale = []
    for row in rows:
        path = project / row["path"]
        if row["tracked"] and path.suffix.lower() in text_extensions:
            for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if re.search(r"[A-Za-z]:[/\\].*(?:task-00[23].*-qa|topgame-task-)", line, re.I):
                    stale.append({"path": row["path"], "line": number, "text": line.strip()})
    expected = {".git", ".godot", "assets", "scripts", "tests", "tools", "docs", "builds"}
    return {
        "repository": str(project), "qa_root": str(qa_root(root)),
        "large_untracked": [row for row in rows if not row["tracked"] and not row["ignored"] and row["bytes"] >= 1024 * 1024],
        "unexpected_root_folders": [p.name for p in project.iterdir() if p.is_dir() and p.name not in expected],
        "qa_media_inside_repo": [row for row in rows if Path(row["path"]).suffix.lower() in {".mp4", ".avi", ".gif"} or (row["path"].startswith("tests/") and Path(row["path"]).suffix.lower() in {".png", ".log"})],
        "stray_executables": [row for row in rows if Path(row["path"]).suffix.lower() == ".exe" and not row["path"].startswith("builds/")],
        "largest_files": sorted(rows, key=lambda row: row["bytes"], reverse=True)[:30],
        "duplicates": duplicates, "unexpected_absolute_task_paths": stale,
        "note": "Read-only findings; duplicates and unknown files are never automatically removed.",
    }


def clean_temp(task=None, root=None, apply=False) -> list[str]:
    """Remove only explicit intermediate suffixes from a named QA temp directory.

    Media, manifests, source files, build staging and unknown files are retained.
    Every target is printed even in dry-run. No directory tree deletion exists.
    """
    base = qa_root(root).resolve()
    target = base / valid_task(task) / "temp" if task else base / "temp"
    if is_link(target) or target.resolve() != target or base not in target.parents:
        raise ValueError("Refusing a temp directory outside the configured QA root")
    selected = []
    for folder, dirs, files in os.walk(target, followlinks=False):
        dirs[:] = [d for d in dirs if not is_link(Path(folder) / d)]
        for name in files:
            path = Path(folder) / name
            if is_link(path) or path.suffix.lower() not in {".tmp", ".part", ".raw"}:
                continue
            if target not in path.resolve().parents:
                raise ValueError(f"Unsafe temp path: {path}")
            print(("REMOVE " if apply else "DRY-RUN ") + str(path))
            selected.append(str(path))
    if apply:
        for value in selected:
            path = Path(value)
            if is_link(target) or target.resolve() != target or is_link(path) or target not in path.resolve().parents:
                raise ValueError(f"Temp path changed scope before removal: {path}")
            if any(is_link(parent) for parent in path.parents if parent != base and base in parent.parents):
                raise ValueError(f"Reparse point in temp path: {path}")
            path.unlink()
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa-root", type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create-task")
    create.add_argument("task")
    review = commands.add_parser("audit")
    review.add_argument("--out", type=Path)
    cleanup = commands.add_parser("clean-temp")
    cleanup.add_argument("--task")
    cleanup_mode = cleanup.add_mutually_exclusive_group()
    cleanup_mode.add_argument("--dry-run", action="store_true", help="Print known intermediates without removing them (default)")
    cleanup_mode.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.command == "create-task":
        print(create_task_workspace(args.task, args.qa_root))
    elif args.command == "clean-temp":
        selected = clean_temp(args.task, args.qa_root, args.apply)
        print(f"{len(selected)} known intermediate files; {'removed' if args.apply else 'dry-run only'}")
    else:
        report = json.dumps(audit(args.qa_root), indent=2)
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            args.out.write_text(report + "\n", encoding="utf-8")
            print(args.out)
        else:
            print(report)


if __name__ == "__main__":
    main()
