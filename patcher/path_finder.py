"""
Auto-detect MacroQuest installations via Windows registry and common filesystem paths.
"""

import os
import winreg


def find_mq_installations() -> list[str]:
    """
    Return list of candidate MQ root paths, ordered by likelihood.
    Each path has been verified to contain MacroQuest.exe or config/.
    """
    candidates = set()

    # Strategy 1: Check registry for EverQuest install paths
    _check_registry(candidates)

    # Strategy 2: Scan common filesystem locations
    _check_common_paths(candidates)

    # Validate each candidate
    valid = []
    for path in candidates:
        path = os.path.normpath(path)
        if _looks_like_mq_root(path):
            valid.append(path)

    return sorted(set(valid))


def _looks_like_mq_root(path: str) -> bool:
    """Return True if path contains MacroQuest.exe or config/ directory."""
    if not os.path.isdir(path):
        return False
    has_exe = os.path.isfile(os.path.join(path, "MacroQuest.exe"))
    has_config = os.path.isdir(os.path.join(path, "config"))
    return has_exe or has_config


def _check_registry(candidates: set):
    """Check Windows registry for EQ/MQ related install paths."""
    registry_keys = [
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Daybreak Game Company\EverQuest"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Daybreak Game Company\EverQuest"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Sony Online Entertainment\EverQuest"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Sony Online Entertainment\EverQuest"),
        (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Daybreak Game Company\EverQuest"),
    ]
    for hive, key_path in registry_keys:
        try:
            with winreg.OpenKey(hive, key_path) as key:
                val, _ = winreg.QueryValueEx(key, "InstallPath")
                if val and os.path.isdir(val):
                    candidates.add(val)
                    # MQ is often in same dir or a sibling folder
                    for sub in ("MacroQuest", "MQ2", "MQ"):
                        sub_path = os.path.join(val, sub)
                        if os.path.isdir(sub_path):
                            candidates.add(sub_path)
        except (OSError, FileNotFoundError):
            pass


def _check_common_paths(candidates: set):
    """Check common filesystem locations where users install MQ."""
    home = os.path.expanduser("~")
    drives = [d + ":\\" for d in "CDEFG" if os.path.isdir(d + ":\\")]

    mq_names = ["MacroQuest", "MQ2", "MQ", "MQNext", "MacroQuest2"]

    parents = [
        *drives,
        *[os.path.join(d, "Games") for d in drives],
        *[os.path.join(d, "EQ") for d in drives],
        *[os.path.join(d, "EverQuest") for d in drives],
        os.path.join(home, "Documents"),
        os.path.join(home, "Desktop"),
    ]

    for parent in parents:
        if not os.path.isdir(parent):
            continue
        for name in mq_names:
            candidate = os.path.join(parent, name)
            if os.path.isdir(candidate):
                candidates.add(candidate)
        # Also check if the parent itself is an MQ root
        candidates.add(parent)
