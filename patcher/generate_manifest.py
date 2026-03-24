"""
Generate release_manifest.json for the patcher from the repo's release file list.
Run from repo root: python patcher/generate_manifest.py
Writes release_manifest.json at repo root (so raw URL is .../main/release_manifest.json).
Uses same "replace on update" list as build-release.ps1 / RELEASE_AND_DEPLOYMENT.md.
"""

import hashlib
import json
import os
import re

# Repo root (parent of patcher/)
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _read_coopt_version() -> str:
    """Read PACKAGE version from lua/coopui/version.lua."""
    version_file = os.path.join(REPO_ROOT, "lua", "coopui", "version.lua")
    if not os.path.isfile(version_file):
        return "0.0.0"
    with open(version_file, "r", encoding="utf-8") as f:
        content = f.read()
    m = re.search(r'PACKAGE\s*=\s*"([^"]+)"', content)
    return m.group(1) if m else "0.0.0"

# Paths to include (relative to repo root). Mirrors build-release.ps1 replace-on-update list.
# We collect lua/itemui (excluding docs, upvalue_check), scripttracker, coopui, mq/ItemUtils,
# Macros sell.mac loot.mac shared_config/*.mac, resources/UIFiles/Default (3 files).
def _collect_release_paths():
    paths = []
    # lua/itemui (exclude dev-only)
    itemui = os.path.join(REPO_ROOT, "lua", "itemui")
    if os.path.isdir(itemui):
        for root, dirs, files in os.walk(itemui):
            dirs[:] = [d for d in dirs if d != "docs"]
            for f in files:
                if f in ("upvalue_check.lua",):
                    continue
                rel = os.path.relpath(os.path.join(root, f), REPO_ROOT)
                paths.append(rel.replace("\\", "/"))
    # lua/scripttracker (exclude .ini so user scripttracker.ini is not overwritten on update)
    st = os.path.join(REPO_ROOT, "lua", "scripttracker")
    if os.path.isdir(st):
        for root, dirs, files in os.walk(st):
            for f in files:
                if f == "scripttracker.ini":
                    continue
                rel = os.path.relpath(os.path.join(root, f), REPO_ROOT)
                paths.append(rel.replace("\\", "/"))
    # lua/coopui
    coopui = os.path.join(REPO_ROOT, "lua", "coopui")
    if os.path.isdir(coopui):
        for root, dirs, files in os.walk(coopui):
            for f in files:
                rel = os.path.relpath(os.path.join(root, f), REPO_ROOT)
                paths.append(rel.replace("\\", "/"))
    # lua/mq/ItemUtils.lua
    mq_utils = os.path.join(REPO_ROOT, "lua", "mq", "ItemUtils.lua")
    if os.path.isfile(mq_utils):
        paths.append("lua/mq/ItemUtils.lua")
    # Macros
    for name in ("sell.mac", "loot.mac"):
        p = os.path.join(REPO_ROOT, "Macros", name)
        if os.path.isfile(p):
            paths.append(f"Macros/{name}")
    shared_mac = os.path.join(REPO_ROOT, "Macros", "shared_config")
    if os.path.isdir(shared_mac):
        for f in os.listdir(shared_mac):
            if f.endswith(".mac"):
                paths.append(f"Macros/shared_config/{f}")
    # resources
    for name in ("EQUI.xml", "MQUI_ItemColorAnimation.xml", "ItemColorBG.tga"):
        p = os.path.join(REPO_ROOT, "resources", "UIFiles", "Default", name)
        if os.path.isfile(p):
            paths.append(f"resources/UIFiles/Default/{name}")
    # config: CoOpt UI bind definitions only (MQ2CustomBinds plugin reads this)
    cb = os.path.join(REPO_ROOT, "config", "MQ2CustomBinds.txt")
    if os.path.isfile(cb):
        paths.append("config/MQ2CustomBinds.txt")
    return sorted(paths)


def _read_changelog() -> list[str]:
    """Read latest version's changelog entries from CHANGELOG.md."""
    changelog_path = os.path.join(REPO_ROOT, "CHANGELOG.md")
    if not os.path.isfile(changelog_path):
        return []
    with open(changelog_path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.split("\n")
    entries = []
    in_version = False
    for line in lines:
        stripped = line.strip()
        # Version heading: ## [0.9.0-beta] or ## [1.0.0]
        if stripped.startswith("## [") and "Unreleased" not in stripped:
            if in_version:
                break  # Finished the latest version section
            in_version = True
            continue
        if in_version:
            if stripped.startswith("- ") or stripped.startswith("* "):
                entries.append(stripped[2:].strip())
            elif stripped.startswith("### "):
                entries.append(stripped)
    return entries


_TEXT_EXTS = frozenset({
    '.lua', '.mac', '.ini', '.txt', '.cfg', '.xml', '.json', '.md',
    '.py', '.ps1', '.bat', '.cmd', '.sh', '.csv', '.html', '.htm',
    '.yml', '.yaml', '.toml', '.reg', '.config',
})


def _sha256_file(file_path: str) -> str:
    """Hash file contents, normalizing CRLF→LF for text files.

    GitHub raw serves LF-normalized content, so manifest hashes must
    match what the patcher downloads regardless of local line endings.
    """
    with open(file_path, "rb") as f:
        content = f.read()
    ext = os.path.splitext(file_path)[1].lower()
    if ext in _TEXT_EXTS:
        content = content.replace(b"\r\n", b"\n")
    return hashlib.sha256(content).hexdigest()


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Generate release_manifest.json")
    parser.add_argument("--plugin-dll", help="Path to MQ2CoOptUI.dll to include as release-asset entry")
    parser.add_argument("--release-tag", help="GitHub release tag for asset URLs (e.g. v0.9.5)")
    args = parser.parse_args()

    paths = _collect_release_paths()
    files = []
    for path in paths:
        full = os.path.join(REPO_ROOT, path.replace("/", os.sep))
        if os.path.isfile(full):
            h = _sha256_file(full)
            files.append({"path": path, "hash": h})

    # Include MQ2CoOptUI.dll as a release-asset download (not in git repo)
    if args.plugin_dll and os.path.isfile(args.plugin_dll):
        h = _sha256_file(args.plugin_dll)
        entry = {"path": "plugins/MQ2CoOptUI.dll", "hash": h}
        if args.release_tag:
            entry["url"] = (
                f"https://github.com/CooptGaming/CooptUI/releases/download/"
                f"{args.release_tag}/MQ2CoOptUI.dll"
            )
        files.append(entry)
        print(f"  Included plugins/MQ2CoOptUI.dll (release asset, {h[:12]}...)")

    version = _read_coopt_version()
    manifest = {"version": version, "changelog": _read_changelog(), "files": files}
    out_path = os.path.join(REPO_ROOT, "release_manifest.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Wrote {out_path} with {len(files)} entries.")


if __name__ == "__main__":
    main()
