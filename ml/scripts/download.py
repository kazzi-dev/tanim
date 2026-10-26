"""Download and extract the public rice leaf datasets listed in ml/sources.json.

Usage (from the repo root):
    python ml/scripts/download.py            # all sources
    python ml/scripts/download.py bd5        # just one

Archives go to ml/data/downloads/, and each one is extracted into its own
empty folder under ml/data/raw/<source id>/. Checksums are verified against
the values Mendeley Data publishes, so a broken or tampered file is rejected.
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ML_DIR = Path(__file__).resolve().parents[1]
DOWNLOADS = ML_DIR / "data" / "downloads"
RAW = ML_DIR / "data" / "raw"


def find_tar() -> str:
    # Windows ships bsdtar (libarchive), which reads zip, 7z and rar.
    # Git Bash's GNU tar comes first on PATH there and reads none of those.
    system_tar = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32" / "tar.exe"
    if system_tar.exists():
        return str(system_tar)
    for name in ("bsdtar", "tar"):
        if found := shutil.which(name):
            return found
    sys.exit("Need bsdtar (libarchive) to extract zip/7z/rar archives.")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(url) as resp, tmp.open("wb") as out:
        total = int(resp.headers.get("Content-Length") or 0)
        done = 0
        while chunk := resp.read(1 << 20):
            out.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r  {done / 1e6:7.1f} / {total / 1e6:.1f} MB", end="", flush=True)
    print()
    tmp.replace(dest)


def fetch(source: dict, tar: str) -> None:
    sid = source["id"]
    archive = DOWNLOADS / f"{sid}{Path(source['file']).suffix}"
    target = RAW / sid
    print(f"[{sid}] {source['name']}  ({source['license']})")

    if archive.exists() and sha256_of(archive) == source["sha256"]:
        print("  archive already downloaded")
    else:
        print(f"  downloading {source['file']}")
        download(source["url"], archive)
        if sha256_of(archive) != source["sha256"]:
            archive.unlink()
            sys.exit(f"  checksum mismatch for {sid}; deleted the file, try again")

    if target.exists() and any(target.iterdir()):
        print(f"  already extracted to {target.relative_to(ML_DIR)}")
        return
    target.mkdir(parents=True, exist_ok=True)
    print(f"  extracting to {target.relative_to(ML_DIR)}")
    subprocess.run([tar, "-xf", str(archive), "-C", str(target)], check=True)


def main() -> None:
    sources = json.loads((ML_DIR / "sources.json").read_text(encoding="utf-8"))["sources"]
    wanted = set(sys.argv[1:])
    if unknown := wanted - {s["id"] for s in sources}:
        sys.exit(f"Unknown source(s): {', '.join(sorted(unknown))}")
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    tar = find_tar()
    for source in sources:
        if not wanted or source["id"] in wanted:
            fetch(source, tar)


if __name__ == "__main__":
    main()
