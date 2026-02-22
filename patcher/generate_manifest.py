"""
Generate release_manifest.json for the patcher from the repo's release file list.
Run from repo root: python patcher/generate_manifest.py
Writes release_manifest.json at repo root (so raw URL is .../main/release_manifest.json).
Uses same "replace on update" list as build-release.ps1 / RELEASE_AND_DEPLOYMENT.md.
"""

import hashlib
import json
import os

# Repo root (parent of patcher/)
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Paths to include (relative to repo root). Mirrors build-release.ps1 replace-on-update list.
# We collect lua/itemui (excluding docs, test_rules, upvalue_check, phase7_check), scripttracker, coopui, mq/ItemUtils,
# Macros sell.mac loot.mac shared_config/*.mac, resources/UIFiles/Default (3 files).
def _collect_release_paths():
    paths = []
    # lua/itemui (exclude dev-only)
    itemui = os.path.join(REPO_ROOT, "lua", "itemui")
    if os.path.isdir(itemui):
        for root, dirs, files in os.walk(itemui):
            dirs[:] = [d for d in dirs if d != "docs"]
            for f in files:
                if f in ("test_rules.lua", "upvalue_check.lua", "phase7_check.ps1", "test_augment_stat_debug.lua"):
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
    return sorted(paths)


def _sha256_file(file_path: str) -> str:
    with open(file_path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    paths = _collect_release_paths()
    files = []
    for path in paths:
        full = os.path.join(REPO_ROOT, path.replace("/", os.sep))
        if os.path.isfile(full):
            h = _sha256_file(full)
            files.append({"path": path, "hash": h})
    manifest = {"version": "1.0.0", "files": files}
    out_path = os.path.join(REPO_ROOT, "release_manifest.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Wrote {out_path} with {len(files)} entries.")


if __name__ == "__main__":
    main()
