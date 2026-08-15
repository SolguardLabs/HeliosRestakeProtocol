from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def forge() -> str:
    configured = os.getenv("FORGE_BIN")
    if configured:
        return configured
    found = shutil.which("forge") or shutil.which("forge.exe")
    if not found:
        raise SystemExit("forge was not found; install Foundry or set FORGE_BIN")
    return found


def run(*args: str) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


def main() -> int:
    binary = forge()
    run(binary, "fmt", "--check")
    run(binary, "build")
    run(binary, "test")
    run(sys.executable, "scripts/verify_release.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
