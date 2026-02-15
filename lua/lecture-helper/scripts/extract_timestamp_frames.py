#!/usr/bin/env python3
import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

YTDLP_VENV_PYTHON = Path("~/.virtualenv/bin/python3").expanduser()


class ScriptError(Exception):
    pass


def fail(message: str) -> None:
    raise ScriptError(message)


def sanitize_cache_name(name: str) -> str:
    normalized = re.sub(r"\.[^.]+$", "", name)
    normalized = re.sub(r"[^\w\-._]", "_", normalized)
    if normalized == "":
        return "buffer"
    return normalized


def timestamp_to_filename(ts: str) -> str:
    return ts.replace(":", "-") + ".png"


def parse_timestamp(line: str) -> tuple[str, int] | None:
    match = re.search(r"(\d+):(\d+):(\d+)", line)
    if not match:
        return None

    h = int(match.group(1))
    m = int(match.group(2))
    s = int(match.group(3))
    if h < 0 or m < 0 or m > 59 or s < 0 or s > 59:
        return None

    timestamp = f"{h:02d}:{m:02d}:{s:02d}"
    seconds = h * 3600 + m * 60 + s
    return timestamp, seconds


def get_yt_dlp_cmd() -> list[str]:
    if not YTDLP_VENV_PYTHON.exists():
        fail(f"yt-dlp python not found: {YTDLP_VENV_PYTHON}")

    cmd = [str(YTDLP_VENV_PYTHON), "-m", "yt_dlp"]
    try:
        subprocess.run(
            cmd + ["--version"],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        fail(f"yt_dlp is not available in {YTDLP_VENV_PYTHON}")

    return cmd


def run_checked(cmd: list[str]) -> None:
    try:
        subprocess.run(cmd, check=True, text=True)
    except subprocess.CalledProcessError as exc:
        fail(f"command failed ({exc.returncode}): {' '.join(cmd)}")


def parse_timestamp_file(path: Path) -> tuple[str, dict[str, int]]:
    if not path.exists():
        fail(f"file not found: {path}")

    url = None
    timestamps: dict[str, int] = {}

    for line in path.read_text(encoding="utf-8").splitlines():
        if url is None:
            url_match = re.search(r"xdg-open\s+(https?://\S+)", line)
            if url_match:
                url = url_match.group(1)

        parsed = parse_timestamp(line)
        if parsed:
            ts, seconds = parsed
            timestamps[ts] = seconds

    if not url:
        fail("no youtube url found (expected a line like: xdg-open https://...)")
    if not timestamps:
        fail("no timestamps found (expected lines containing hh:mm:ss)")

    return url, timestamps


def download_video(url: str, output_dir: Path) -> Path:
    yt_dlp_cmd = get_yt_dlp_cmd()
    output_dir.mkdir(parents=True, exist_ok=True)
    output_template = output_dir / "video.%(ext)s"
    fmt = "best[height<=360][ext=mp4]/best[height<=360]/worst[ext=mp4]/worst"

    run_checked(
        yt_dlp_cmd
        + [
            "--force-overwrites",
            "--no-playlist",
            "--extractor-args",
            "youtube:player_client=default",
            "-f",
            fmt,
            "-o",
            str(output_template),
            url,
        ]
    )

    candidates = sorted(output_dir.glob("video.*"))
    if not candidates:
        fail("yt-dlp downloaded no video file")
    return candidates[0]


def extract_frame(video_path: Path, seconds: int, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    run_checked(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            str(seconds),
            "-i",
            str(video_path),
            "-frames:v",
            "1",
            str(out_path),
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract cached png frames for all timestamps in a lecture-helper timestamp file."
    )
    parser.add_argument("timestamp_file", help="Path to timestamp file")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-extract frames even if png files already exist",
    )
    args = parser.parse_args()

    timestamp_file = Path(args.timestamp_file).expanduser().resolve()
    url, timestamps = parse_timestamp_file(timestamp_file)

    cache_dir = timestamp_file.parent / ".frames" / sanitize_cache_name(timestamp_file.name)
    targets: list[tuple[str, int, Path]] = []
    for ts, seconds in timestamps.items():
        out_path = cache_dir / timestamp_to_filename(ts)
        if args.force or not out_path.exists():
            targets.append((ts, seconds, out_path))

    if not targets:
        print(f"All frames already exist in {cache_dir}")
        return

    with tempfile.TemporaryDirectory(prefix="lecture-helper-batch-yt-") as tmp_dir:
        video_path = download_video(url, Path(tmp_dir))
        for ts, seconds, out_path in targets:
            extract_frame(video_path, seconds, out_path)
            print(f"Saved {ts} -> {out_path}")


if __name__ == "__main__":
    try:
        main()
    except ScriptError as exc:
        print(f"[lecture-helper] {exc}", file=sys.stderr)
        raise SystemExit(1)
