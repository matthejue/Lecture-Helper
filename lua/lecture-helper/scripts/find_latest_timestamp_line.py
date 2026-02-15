#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

TIMESTAMP_RE = re.compile(r"(\d+):(\d{2}):(\d{2})")


def fail(msg: str, code: int = 1) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def timestamp_to_seconds(ts: str) -> int:
    match = TIMESTAMP_RE.fullmatch(ts.strip())
    if not match:
        fail("current time must be in hh:mm:ss format")

    hours, minutes, seconds = (int(part) for part in match.groups())
    if minutes > 59 or seconds > 59:
        fail("current time is out of range")

    return hours * 3600 + minutes * 60 + seconds


def parse_line_timestamp_seconds(line: str) -> int | None:
    match = TIMESTAMP_RE.search(line)
    if not match:
        return None

    hours, minutes, seconds = (int(part) for part in match.groups())
    if minutes > 59 or seconds > 59:
        return None

    return hours * 3600 + minutes * 60 + seconds


def find_latest_smaller_or_equal_timestamp_line(path: Path, current_seconds: int) -> int | None:
    best_line: int | None = None
    best_seconds = -1

    with path.open("r", encoding="utf-8") as handle:
        for line_nr, line in enumerate(handle, start=1):
            line_seconds = parse_line_timestamp_seconds(line)
            if line_seconds is None:
                continue

            if line_seconds <= current_seconds and line_seconds >= best_seconds:
                best_seconds = line_seconds
                best_line = line_nr

    return best_line


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Return the latest line number in a timestamp file where hh:mm:ss is <= current video time."
        )
    )
    parser.add_argument("--file", required=True, help="Path to the timestamp file")
    parser.add_argument("--current-time", required=True, help="Current player time in hh:mm:ss")
    args = parser.parse_args()

    path = Path(args.file).expanduser().resolve()
    if not path.exists() or not path.is_file():
        fail(f"timestamp file not found: {path}")

    current_seconds = timestamp_to_seconds(args.current_time)
    best_line = find_latest_smaller_or_equal_timestamp_line(path, current_seconds)
    if best_line is None:
        raise SystemExit(2)

    print(best_line)


if __name__ == "__main__":
    main()
