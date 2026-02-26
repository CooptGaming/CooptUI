"""
MacroQuest root directory validation.
Checks for MacroQuest.exe or config/ folder, and lua/ and Macros/ directories; no network calls.
"""

import os

MSG_NOT_MQ_ROOT = "MacroQuest root not found. Run this from the folder containing MacroQuest.exe or config/."
MSG_NOT_MQ_INSTALL = "This doesn't look like a MacroQuest installation. Expected to find `lua/` and `Macros/` directories."


def validate_mq_root(root_path: str | None = None) -> tuple[bool, str]:
    """
    Verify that root_path (or cwd) is a valid MacroQuest root directory.

    Checks in order:
    1. Root is an existing directory.
    2. At least one of MacroQuest.exe (file) or config/ (directory) exists.
    3. lua/ directory exists.
    4. Macros/ directory exists.

    Returns:
        (success: bool, message: str)
        On failure, message is a user-friendly error string.
    """
    root = os.path.abspath(root_path or os.getcwd())
    if not os.path.isdir(root):
        return False, MSG_NOT_MQ_ROOT

    exe_path = os.path.join(root, "MacroQuest.exe")
    config_path = os.path.join(root, "config")
    if not os.path.isfile(exe_path) and not os.path.isdir(config_path):
        return False, MSG_NOT_MQ_ROOT

    lua_path = os.path.join(root, "lua")
    macros_path = os.path.join(root, "Macros")
    if not os.path.isdir(lua_path) or not os.path.isdir(macros_path):
        return False, MSG_NOT_MQ_INSTALL

    return True, ""
