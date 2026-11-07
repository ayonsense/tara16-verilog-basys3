#!/usr/bin/env python3
"""Audit staged file names/content and the exact supplied release assets."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])

files = git("ls-files", "-z").decode().split("\0")
errors = []
asset_manifest = {}
if "release-assets.json" in files:
    asset_manifest = json.loads(git("show", ":release-assets.json"))
supplied_assets = set(asset_manifest)
blocked_parts = {
    ".idea", ".vscode", ".claude", ".codex", "__pycache__", "build",
    "dist", "host", "local", "private", ".Xil",
}
blocked_names = {".DS_Store"}
blocked_suffixes = {
    ".ai", ".bit", ".dcp", ".jpeg", ".jpg", ".key", ".pem", ".png",
    ".psd", ".pyc", ".svg", ".vvp",
}
for name in filter(None, files):
    p = Path(name)
    if (set(p.parts) & blocked_parts or p.name in blocked_names
            or p.name.startswith(".env") and p.name != ".env.example"
            or any(x.endswith(".egg-info") for x in p.parts)
            or (p.suffix.lower() in blocked_suffixes
                and name not in supplied_assets)):
        errors.append(f"Excluded file staged: {name}")
    if p.parts[:2] == ("tools", "assets") and name not in supplied_assets:
        errors.append(f"Unlisted release asset staged: {name}")
    mode = git("ls-files", "-s", "--", name).decode().split()[0]
    if mode == "120000":
        errors.append(f"Review symlink before publication: {name}")
    data = git("show", ":" + name)
    if b"\0" not in data:
        for pattern in (rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
                        rb"gh[pousr]_[A-Za-z0-9]{20,}",
                        rb"pypi-[A-Za-z0-9_-]{30,}",
                        rb"AKIA[0-9A-Z]{16}",
                        rb"(?:/Users/|/home/)[A-Za-z0-9_.-]+/"):
            if re.search(pattern, data):
                errors.append(f"Possible credential or personal path in: {name}")
for name, expected in asset_manifest.items():
    if name not in files:
        errors.append(f"Missing supplied asset: {name}")
    elif hashlib.sha256(git("show", ":" + name)).hexdigest() != expected:
        errors.append(f"Supplied asset changed: {name}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"Release audit passed: {len(list(filter(None, files)))} tracked files")
