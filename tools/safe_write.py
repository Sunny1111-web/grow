"""Preserve complete originals before replacing project files (user policy)."""
from datetime import datetime
from pathlib import Path
import shutil
import sys
import uuid

PROJECT = Path(__file__).resolve().parents[1]


def backup_file(path):
    source = Path(path).resolve()
    if not source.is_relative_to(PROJECT):
        raise ValueError(f"Outside project: {source}")
    if not source.is_file():
        raise ValueError(f"Not a file: {source}")
    now = datetime.now()
    directory = Path("C:/backup") / f"{now.year}年{now.month}月{now.day}日"
    directory.mkdir(parents=True, exist_ok=True)
    target = (directory / f"{source.stem}_{now:%H%M%S_%f}_{uuid.uuid4().hex[:8]}{source.suffix}").resolve()
    if not target.is_relative_to(directory.resolve()) or target.exists():
        raise ValueError("Unsafe backup destination")
    shutil.move(str(source), str(target))
    with Path("C:/backup/log.txt").open("a", encoding="utf-8") as log:
        log.write(f"原路径：{source}  => 目标路径：{target}\n")
    return target


def write_file(path, content):
    destination = Path(path).resolve()
    if not destination.is_relative_to(PROJECT):
        raise ValueError(f"Outside project: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        backup_file(destination)
    with destination.open("x", encoding="utf-8", newline="\n") as output:
        output.write(content)


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        print(backup_file(argument))
