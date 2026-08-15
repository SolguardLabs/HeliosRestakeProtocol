from __future__ import annotations

import hashlib
import json
import re
import struct
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROTECTED = {
    "src/core/HeliosRestakeVault.sol": "aada37ed82d493bb462753ab0862909121a4ec35",
    "src/core/WithdrawalQueue.sol": "0829ceb1963a5a83516cf1f1a1e93f7acd461d25",
    "src/core/SlashingController.sol": "7a9eb8911953683da15ba5c758ca5ccc4ce278ce",
    "src/core/DelegationManager.sol": "4384a4bded41811b17827d4ea2edc274b43fa895",
}
RESTRICTED = re.compile(
    r"\b(?:ctf|labs?|laboratorios?|vulnerabil(?:ity|idad|idades)|vulnerable|bugs?|exploits?|bypass|attackers?|atacantes?)\b",
    re.IGNORECASE,
)
TEXT_SUFFIXES = {".sol", ".s.sol", ".md", ".json", ".yml", ".yaml", ".toml", ".txt", ".py"}


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def nonblank(path: Path) -> int:
    return sum(bool(line.strip()) for line in path.read_text(encoding="utf-8").splitlines())


def main() -> int:
    errors: list[str] = []
    for path, expected in PROTECTED.items():
        if git("hash-object", path) != expected:
            errors.append(f"{path} does not match its approved source blob")

    docs = sorted((ROOT / "docs").glob("*.md"))
    if len(docs) != 7:
        errors.append(f"expected 7 operational documents, found {len(docs)}")
    markdown = [ROOT / "README.md", ROOT / "SECURITY.md", *docs]
    diagrams = sum(path.read_text(encoding="utf-8").count("```mermaid") for path in markdown)
    if diagrams != 27:
        errors.append(f"expected 27 Mermaid diagrams, found {diagrams}")

    banner = (ROOT / "assets" / "banner.png").read_bytes()
    width, height = struct.unpack(">II", banner[16:24])
    if not banner.startswith(b"\x89PNG") or (width, height) != (1672, 941):
        errors.append("banner must be a 1672x941 PNG")

    release = json.loads((ROOT / "RELEASE.json").read_text(encoding="utf-8"))
    if release.get("version") != "1.0.0" or release.get("tag") != "v1.0.0":
        errors.append("release metadata must identify v1.0.0")
    if not git("check-ignore", "test/private/proof.t.sol"):
        errors.append("private evidence path must remain ignored")

    tracked = git("ls-files").splitlines()
    excluded = {"LICENSE", "scripts/verify_release.py", *PROTECTED}
    for name in tracked:
        path = ROOT / name
        if name in excluded or path.suffix not in TEXT_SUFFIXES:
            continue
        if RESTRICTED.search(path.read_text(encoding="utf-8")):
            errors.append(f"{name} contains restricted public terminology")

    workflows = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / ".github" / "workflows").glob("*.yml"))
    for marker in ("actions/checkout@v7", "actions/setup-python@v7", "foundry-rs/foundry-toolchain@v1", "ubuntu-latest", "windows-latest"):
        if marker not in workflows:
            errors.append(f"workflow marker missing: {marker}")

    source_loc = sum(nonblank(ROOT / name) for name in tracked if name.startswith("src/") and name.endswith(".sol"))
    public_tests = sum(1 for name in tracked if name.startswith("test/") and name.endswith(".sol") for line in (ROOT / name).read_text(encoding="utf-8").splitlines() if re.match(r"\s*function test", line))
    public_text = sum(nonblank(ROOT / name) for name in tracked if Path(name).suffix in TEXT_SUFFIXES or name == "LICENSE")
    digest = hashlib.sha256("\n".join(path.read_text(encoding="utf-8") for path in markdown).encode()).hexdigest()

    if errors:
        for error in errors:
            print(f"- {error}")
        return 1
    print(json.dumps({"protocol": "HeliosRestakeProtocol", "version": "1.0.0", "source_nonblank": source_loc, "public_tests": public_tests, "public_text_nonblank": public_text, "docs": len(docs), "diagrams": diagrams, "protected_sources": len(PROTECTED), "documentation_sha256": digest}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
