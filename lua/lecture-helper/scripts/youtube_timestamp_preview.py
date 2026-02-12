#!/usr/bin/env python3
import argparse
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

YTDLP_VENV_PYTHON = os.path.expanduser("~/.virtualenv/bin/python3")
_YTDLP_CMD: list[str] | None = None


class ScriptError(Exception):
    pass


def fail(msg: str) -> None:
    raise ScriptError(msg)


def timestamp_to_seconds(ts: str) -> int:
    parts = ts.split(":")
    if len(parts) != 3:
        fail("timestamp must be in hh:mm:ss format")

    try:
        h, m, s = (int(p) for p in parts)
    except ValueError:
        fail("timestamp contains non-numeric parts")

    if m < 0 or m > 59 or s < 0 or s > 59 or h < 0:
        fail("timestamp out of range")

    return h * 3600 + m * 60 + s


def timestamp_to_filename(ts: str) -> str:
    return ts.replace(":", "-") + ".png"


def ensure_tool(name: str) -> None:
    if not shutil.which(name):
        fail(f"required tool '{name}' was not found in PATH")


def get_yt_dlp_cmd() -> list[str]:
    global _YTDLP_CMD
    if _YTDLP_CMD is not None:
        return _YTDLP_CMD

    venv_python = Path(YTDLP_VENV_PYTHON)
    if venv_python.exists():
        try:
            subprocess.run(
                [str(venv_python), "-m", "yt_dlp", "--version"],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            _YTDLP_CMD = [str(venv_python), "-m", "yt_dlp"]
            return _YTDLP_CMD
        except subprocess.CalledProcessError:
            pass

    if shutil.which("yt-dlp"):
        _YTDLP_CMD = ["yt-dlp"]
        return _YTDLP_CMD

    fail("yt-dlp not found (tried ~/.virtualenv/bin/python3 -m yt_dlp and yt-dlp in PATH)")


def run_checked(cmd: list[str], capture: bool = False) -> str | None:
    kwargs = {
        "check": True,
        "text": True,
    }
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["stderr"] = subprocess.PIPE

    try:
        cp = subprocess.run(cmd, **kwargs)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        fail(f"command failed: {' '.join(cmd)}{': ' + stderr if stderr else ''}")

    if capture:
        out = (cp.stdout or "").strip()
        if not out:
            fail(f"command returned no output: {' '.join(cmd)}")
        return out
    return None


def resolve_stream_url(url: str) -> str:
    yt_dlp_cmd = get_yt_dlp_cmd()
    fmt = "bestvideo[height<=720]+bestaudio/best[height<=720]/best"
    out = run_checked(yt_dlp_cmd + [
        "--extractor-args",
        "youtube:player_client=default",
        "-g",
        "-f",
        fmt,
        url,
    ], capture=True)
    return out.splitlines()[0].strip()


def download_small_section(url: str, timestamp: str, output_dir: Path) -> Path:
    yt_dlp_cmd = get_yt_dlp_cmd()
    output_dir.mkdir(parents=True, exist_ok=True)
    output_template = output_dir / "segment.%(ext)s"
    section = f"*{timestamp}-{timestamp}.500"
    fmt = "bestvideo[height<=720]/best[height<=720]/best"
    run_checked(yt_dlp_cmd + [
        "--force-overwrites",
        "--no-playlist",
        "--extractor-args",
        "youtube:player_client=default",
        "--download-sections",
        section,
        "-f",
        fmt,
        "-o",
        str(output_template),
        url,
    ])

    candidates = sorted(output_dir.glob("segment.*"))
    if not candidates:
        fail("yt-dlp downloaded no section file")
    return candidates[0]


def download_lowres_video(url: str, output_dir: Path) -> Path:
    yt_dlp_cmd = get_yt_dlp_cmd()
    output_dir.mkdir(parents=True, exist_ok=True)
    output_template = output_dir / "video.%(ext)s"
    fmt = "best[height<=360][ext=mp4]/best[height<=360]/worst[ext=mp4]/worst"
    run_checked(yt_dlp_cmd + [
        "--force-overwrites",
        "--no-playlist",
        "--extractor-args",
        "youtube:player_client=default",
        "-f",
        fmt,
        "-o",
        str(output_template),
        url,
    ])

    candidates = sorted(output_dir.glob("video.*"))
    if not candidates:
        fail("yt-dlp downloaded no video file")
    return candidates[0]


def capture_frame(stream_url: str, out_path: Path, seconds: int) -> None:
    ensure_tool("ffmpeg")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    run_checked([
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-ss",
        str(seconds),
        "-i",
        stream_url,
        "-frames:v",
        "1",
        str(out_path),
    ])


def open_viewer(image_path: Path, viewer: str) -> None:
    if not viewer:
        viewer = "nsxiv"

    parts = shlex.split(viewer)
    if not parts:
        parts = ["nsxiv"]

    if shutil.which(parts[0]):
        cmd = parts + [str(image_path)]
    else:
        xdg = shutil.which("xdg-open")
        if not xdg:
            fail(f"viewer '{parts[0]}' and fallback 'xdg-open' were not found")
        cmd = [xdg, str(image_path)]

    subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Preview a youtube frame at a specific timestamp")
    parser.add_argument("--url", required=True, help="YouTube URL")
    parser.add_argument("--timestamp", required=True, help="Timestamp in hh:mm:ss")
    parser.add_argument("--viewer", default="nsxiv", help="Viewer command, e.g. 'nsxiv -a'")
    parser.add_argument("--cache-dir", default=".frames", help="Directory for cached frames")
    parser.add_argument("--force", action="store_true", help="Force re-render even if frame exists")
    args = parser.parse_args()

    seconds = timestamp_to_seconds(args.timestamp)
    cache_root = Path(os.path.expanduser(args.cache_dir))
    frame_path = cache_root / timestamp_to_filename(args.timestamp)

    try:
        if args.force or not frame_path.exists():
            try:
                stream = resolve_stream_url(args.url)
                capture_frame(stream, frame_path, seconds)
            except ScriptError:
                # Some youtube stream URLs need extra request metadata; fallback
                # to section download via yt-dlp and extract frame locally.
                try:
                    with tempfile.TemporaryDirectory(prefix="lecture-helper-yt-") as tmp_dir:
                        local_segment = download_small_section(args.url, args.timestamp, Path(tmp_dir))
                        capture_frame(str(local_segment), frame_path, 0)
                except ScriptError:
                    # Final fallback: download a small-quality local copy and
                    # extract frame from local file.
                    with tempfile.TemporaryDirectory(prefix="lecture-helper-yt-full-") as tmp_dir:
                        local_video = download_lowres_video(args.url, Path(tmp_dir))
                        capture_frame(str(local_video), frame_path, seconds)

        open_viewer(frame_path, args.viewer)
    except ScriptError as exc:
        print(f"[lecture-helper] {exc}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
