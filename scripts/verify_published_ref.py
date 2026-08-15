from __future__ import annotations

import json
import os
import subprocess


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


event = os.getenv("VERIFY_EVENT", "local")
ref_type = os.getenv("VERIFY_REF_TYPE", "")
ref_name = os.getenv("VERIFY_REF_NAME", "")
if ref_name == "production" or ref_type == "tag" or event == "release":
    git("fetch", "origin", "main", "production", "--tags", "--force")
    main = git("rev-parse", "origin/main^{commit}")
    production = git("rev-parse", "origin/production^{commit}")
    if main != production:
        raise SystemExit("main and production do not identify the same commit")
    if ref_type == "tag" or event == "release":
        tag = ref_name or os.environ["GITHUB_REF_NAME"]
        if git("cat-file", "-t", f"refs/tags/{tag}") != "tag":
            raise SystemExit(f"{tag} must be annotated")
        if git("rev-parse", f"refs/tags/{tag}^{{commit}}") != main:
            raise SystemExit(f"{tag} does not identify the production commit")
print(json.dumps({"event": event, "ref_type": ref_type, "ref_name": ref_name, "commit": git("rev-parse", "HEAD")}))
