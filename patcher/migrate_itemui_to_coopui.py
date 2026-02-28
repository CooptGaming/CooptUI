"""
Migrate existing CoOpt UI install from lua/itemui/ to lua/coopui/ (Task 3.5).
Run from patcher after validating MQ root; moves directory contents, rewrites path-bearing INI values.
"""

import os
import re
import shutil
from typing import Callable


def _log(log_cb: Callable[[str], None] | None, msg: str) -> None:
    if log_cb:
        log_cb(msg)


def _old_layout_exists(root: str) -> bool:
    """Return True if the old layout is present (itemui kernel file exists)."""
    wiring = os.path.join(root, "lua", "itemui", "wiring.lua")
    app = os.path.join(root, "lua", "itemui", "app.lua")
    return os.path.isfile(wiring) or os.path.isfile(app)


def _coopui_has_app(root: str) -> bool:
    """Return True if coopui already has the application (so we don't overwrite)."""
    wiring = os.path.join(root, "lua", "coopui", "wiring.lua")
    app = os.path.join(root, "lua", "coopui", "app.lua")
    return os.path.isfile(wiring) or os.path.isfile(app)


def _rewrite_ini_paths(file_path: str, log_cb: Callable[[str], None] | None) -> tuple[bool, str]:
    """
    If the file contains path-bearing values with 'itemui', rewrite to 'coopui'.
    Returns (success, error_message). Empty error_message on success.
    """
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError as e:
        return False, f"Could not read {file_path}: {e}"

    if "itemui" not in content:
        return True, ""

    new_content = re.sub(
        r"([\\/])itemui([\\/])",
        r"\1coopui\2",
        content,
    )
    new_content = re.sub(
        r"([\\/])lua([\\/])itemui\b",
        r"\1lua\2coopui",
        new_content,
    )
    if new_content == content:
        return True, ""

    try:
        with open(file_path, "w", encoding="utf-8", newline="") as f:
            f.write(new_content)
    except OSError as e:
        return False, f"Could not write {file_path}: {e}"

    _log(log_cb, f"  Rewrote path-bearing values in {file_path}")
    return True, ""


def _collect_ini_files(root: str) -> list[str]:
    """Collect INI files under sell_config, shared_config, loot_config, and lua/itemui/lua/coopui."""
    out: list[str] = []
    for sub in ("Macros/sell_config", "Macros/shared_config", "Macros/loot_config"):
        base = os.path.join(root, sub.replace("/", os.sep))
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for name in filenames:
                if name.lower().endswith(".ini"):
                    out.append(os.path.join(dirpath, name))
    for folder in ("lua/itemui", "lua/coopui"):
        base = os.path.join(root, folder.replace("/", os.sep))
        if not os.path.isdir(base):
            continue
        for dirpath, _dirnames, filenames in os.walk(base):
            for name in filenames:
                if name.lower().endswith(".ini"):
                    out.append(os.path.join(dirpath, name))
    return out


def migrate_itemui_to_coopui(
    root_path: str,
    log_callback: Callable[[str], None] | None = None,
) -> tuple[bool, str]:
    """
    If the old layout (lua/itemui with wiring.lua or app.lua) exists, move its contents
    to lua/coopui (merge), rewrite path-bearing INI values (itemui -> coopui), and log actions.
    """
    root = os.path.abspath(root_path)
    if not _old_layout_exists(root):
        return True, ""

    if _coopui_has_app(root):
        _log(log_callback, "lua/coopui already present; skipping migration.")
        return True, ""

    itemui_dir = os.path.join(root, "lua", "itemui")
    coopui_dir = os.path.join(root, "lua", "coopui")

    if not os.path.isdir(itemui_dir):
        return True, ""

    _log(log_callback, "Migrating lua/itemui -> lua/coopui (merge).")

    try:
        os.makedirs(coopui_dir, exist_ok=True)
    except OSError as e:
        return False, f"Could not create lua/coopui. {e}. Resolve permissions and run the patcher again."

    for entry in os.listdir(itemui_dir):
        src = os.path.join(itemui_dir, entry)
        dst = os.path.join(coopui_dir, entry)
        try:
            if os.path.isdir(src):
                if os.path.isdir(dst):
                    for sub in os.listdir(src):
                        s = os.path.join(src, sub)
                        d = os.path.join(dst, sub)
                        if os.path.isdir(s):
                            shutil.copytree(s, d, dirs_exist_ok=True)
                        else:
                            shutil.copy2(s, d)
                else:
                    shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)
            _log(log_callback, f"  Copied {entry} -> lua/coopui/")
        except OSError as e:
            return False, f"Could not copy {entry} to lua/coopui. {e}. Resolve permissions and run the patcher again."

    for ini_path in _collect_ini_files(root):
        ok, err = _rewrite_ini_paths(ini_path, log_callback)
        if not ok:
            return False, err or f"Failed to rewrite INI: {ini_path}"

    _log(log_callback, "Migration complete. You can remove lua/itemui manually if desired.")
    return True, ""


def ensure_env_after_patch(root_path: str) -> None:
    """
    Ensure CoOpt UI environment (Task 8.4): create Macros/sell_config, shared_config, loot_config
    if missing, and minimal INI files so Welcome process reaches tutorial without red validation.
    """
    root = os.path.abspath(root_path)
    for folder in ("Macros/sell_config", "Macros/shared_config", "Macros/loot_config"):
        d = os.path.join(root, folder.replace("/", os.sep))
        try:
            os.makedirs(d, exist_ok=True)
        except OSError:
            pass
    inis = [
        ("Macros/sell_config/itemui_layout.ini", "[Layout]\n"),
        ("Macros/sell_config/sell_flags.ini", "[Settings]\n"),
        ("Macros/loot_config/loot_flags.ini", "[Settings]\n"),
    ]
    for rel_path, default in inis:
        full = os.path.join(root, rel_path.replace("/", os.sep))
        if not os.path.isfile(full):
            try:
                with open(full, "w", encoding="utf-8") as f:
                    f.write(default)
            except OSError:
                pass
