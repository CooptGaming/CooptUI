"""
MacroQuest root directory validation.
Checks for MacroQuest.exe or config/ folder; no network calls.
"""

import os


def validate_mq_root(root_path: str | None = None) -> tuple[bool, str]:
    """
    Verify that root_path (or cwd) is a valid MacroQuest root directory.

    Checks for presence of either:
    - MacroQuest.exe in the root, or
    - a directory named config/ in the root.

    Returns:
        (success: bool, message: str)
        On failure, message is a user-friendly error string.
    """
    root = os.path.abspath(root_path or os.getcwd())
    if not os.path.isdir(root):
        return False, "MacroQuest root not found. Run this from the folder containing MacroQuest.exe or config/."

    exe_path = os.path.join(root, "MacroQuest.exe")
    config_path = os.path.join(root, "config")

    if os.path.isfile(exe_path):
        return True, ""
    if os.path.isdir(config_path):
        return True, ""

    return False, "MacroQuest root not found. Run this from the folder containing MacroQuest.exe or config/."
