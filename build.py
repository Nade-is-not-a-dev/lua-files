#!/usr/bin/env python3
"""Build VL Suite: concatenate suite modules (per manifest.txt)
into one distributable file, dist/vl-suite.lua, with a version
stamp header. Runs identically locally and in GitHub Actions.

Usage: python3 build.py
Env:   GITHUB_SHA (optional) -- commit stamped into the header.
"""
import os
import subprocess
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(ROOT, "dist")
OUT_FILE = os.path.join(OUT_DIR, "vl-suite.lua")
LOADSTRING_URL = "https://nade-is-not-a-dev.github.io/vl-suite/vl-suite.lua"


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def commit_sha():
    sha = os.environ.get("GITHUB_SHA", "").strip()
    if not sha:
        try:
            sha = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
            ).strip()
        except Exception:
            sha = "local"
    return sha


def main():
    version = read(os.path.join(ROOT, "VERSION")).strip()
    manifest = []
    for line in read(os.path.join(ROOT, "manifest.txt")).splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            manifest.append(line)
    if not manifest:
        print("manifest.txt is empty", file=sys.stderr)
        return 1

    sha = commit_sha()
    built = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    header = (
        "-- ============================================================\n"
        "--  VL Suite (modular build)\n"
        f"--  version : {version}\n"
        f"--  commit  : {sha[:7]}\n"
        f"--  built   : {built} (GitHub Actions)\n"
        f"--  loadstring:\n"
        f'--    loadstring(game:HttpGet("{LOADSTRING_URL}"))()\n'
        "--  File ini HASIL BUILD: inti di root repo, modul fitur di modules/.\n"
        "--  Jangan edit langsung -- edit modulnya, lalu push.\n"
        "-- ============================================================\n"
        f'print("[VL Suite] v{version} @ {sha[:7]} -- loading {len(manifest)} module(s)...")\n\n'
    )

    parts = [header]
    total = 0
    for entry in manifest:
        path = os.path.join(ROOT, entry)
        if not os.path.isfile(path):
            print(f"missing module: {entry}", file=sys.stderr)
            return 1
        src = read(path).rstrip() + "\n"
        total += len(src)
        if entry.startswith("modules/"):
            # Bungkus modul fitur dalam blok do..end: local top-level
            # modul jadi block-scoped dan TIDAK menyumbang register
            # chunk selamanya (chunk tunggal + 14 modul bisa
            # melampaui batas ~200 local per fungsi compiler executor
            # -> "Out of local registers"). Semua komunikasi antar
            # modul lewat FeatureAPI/local core+feature-shared yang
            # tetap di level chunk.
            parts.append(
                f"\n-- ===== module: {entry} =====\n"
                "do -- scope modul (batas register chunk)\n"
                + src
                + "end -- scope modul\n"
            )
        else:
            parts.append(
                f"\n-- ===== module: {entry} =====\n" + src
            )

    parts.append(
        "\n-- ===== end of modules =====\n"
        f'suiteArmReady("[VL Suite] READY -- all {len(manifest)} module(s) loaded '
        f'(v{version} @ {sha[:7]})")\n'
    )

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        f.write("".join(parts))
    print(f"built {OUT_FILE}: {os.path.getsize(OUT_FILE)} bytes "
          f"from {len(manifest)} module(s), version {version}, commit {sha[:7]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
