#!/usr/bin/env bash
set -euo pipefail

resolve_forge() {
    local candidate
    if candidate="$(command -v forge 2>/dev/null)"; then
        if "$candidate" --version >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return
        fi
    fi
    if candidate="$(command -v forge.exe 2>/dev/null)"; then
        if "$candidate" --version >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return
        fi
    fi
    if command -v powershell.exe >/dev/null 2>&1; then
        local win_path
        win_path="$(powershell.exe -NoProfile -Command '(Get-Command forge).Source' | tr -d '\r')"
        if [[ "$win_path" =~ ^([A-Za-z]):\\(.*)$ ]]; then
            local drive
            drive="$(printf '%s' "${BASH_REMATCH[1]}" | tr 'A-Z' 'a-z')"
            local rest="${BASH_REMATCH[2]//\\//}"
            candidate="/$drive/$rest"
            if "$candidate" --version >/dev/null 2>&1; then
                printf '%s\n' "$candidate"
                return
            fi
        fi
    fi
    printf 'forge was not found in this Bash environment. Install Foundry for this shell or run forge from PowerShell.\n' >&2
    return 127
}

FORGE_BIN="$(resolve_forge)"
"$FORGE_BIN" test "$@"
