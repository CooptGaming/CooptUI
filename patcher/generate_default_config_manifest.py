"""
Generate default_config_manifest.json for the patcher (create-if-missing install of config templates).
Run from repo root: python patcher/generate_default_config_manifest.py
Writes default_config_manifest.json at repo root.
Each entry maps a repo path (config_templates/...) to an install path (Macros/...) under the MQ root.
Patcher installs only when the install path does not exist.
"""

import json
import os

# Repo root (parent of patcher/)
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CONFIG_TEMPLATES = os.path.join(REPO_ROOT, "config_templates")

# config_templates subdir -> Macros subdir
INSTALL_MAP = [
    ("sell_config", "Macros", "sell_config"),
    ("shared_config", "Macros", "shared_config"),
    ("loot_config", "Macros", "loot_config"),
]


def _collect_install_only_entries():
    entries = []
    if not os.path.isdir(CONFIG_TEMPLATES):
        return entries
    for subdir, macro_parent, macro_subdir in INSTALL_MAP:
        src_dir = os.path.join(CONFIG_TEMPLATES, subdir)
        if not os.path.isdir(src_dir):
            continue
        for name in os.listdir(src_dir):
            if name.startswith(".") or name.lower().endswith(".md"):
                continue
            src_path = os.path.join(src_dir, name)
            if not os.path.isfile(src_path):
                continue
            repo_path = f"config_templates/{subdir}/{name}".replace("\\", "/")
            install_path = f"{macro_parent}/{macro_subdir}/{name}".replace("\\", "/")
            entries.append({"repoPath": repo_path, "installPath": install_path})
    return sorted(entries, key=lambda e: (e["installPath"], e["repoPath"]))


def main():
    entries = _collect_install_only_entries()
    manifest = {"files": entries}
    out_path = os.path.join(REPO_ROOT, "default_config_manifest.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Wrote {out_path} with {len(entries)} install-only entries.")


if __name__ == "__main__":
    main()
