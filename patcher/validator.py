"""
MacroQuest root directory validation.
Three-tier result: valid, fixable (can create missing dirs), or invalid.
"""

import os

MSG_NOT_MQ_ROOT = "Not a MacroQuest root. Select the folder containing MacroQuest.exe or config/."
MSG_WILL_CREATE_DIRS = "MacroQuest found. Required folders (lua/, Macros/) will be created."


def validate_mq_root(root_path: str | None = None) -> tuple[bool, bool, str]:
    """
    Verify that root_path is a valid MacroQuest root directory.

    Returns:
        (is_valid: bool, needs_setup: bool, message: str)
        - is_valid=True, needs_setup=False: fully ready
        - is_valid=True, needs_setup=True: MQ root found but lua/ or Macros/ missing
        - is_valid=False: not an MQ root at all
    """
    root = os.path.abspath(root_path or os.getcwd())
    if not os.path.isdir(root):
        return False, False, MSG_NOT_MQ_ROOT

    exe_path = os.path.join(root, "MacroQuest.exe")
    config_path = os.path.join(root, "config")
    if not os.path.isfile(exe_path) and not os.path.isdir(config_path):
        return False, False, MSG_NOT_MQ_ROOT

    lua_path = os.path.join(root, "lua")
    macros_path = os.path.join(root, "Macros")
    missing_lua = not os.path.isdir(lua_path)
    missing_macros = not os.path.isdir(macros_path)

    if missing_lua or missing_macros:
        return True, True, MSG_WILL_CREATE_DIRS

    return True, False, ""


def ensure_directories(root_path: str) -> tuple[bool, str]:
    """Create lua/ and Macros/ if missing. Call after user confirms setup."""
    root = os.path.abspath(root_path)
    for d in ("lua", "Macros"):
        try:
            os.makedirs(os.path.join(root, d), exist_ok=True)
        except OSError as e:
            return False, f"Could not create {d}/: {e}"
    return True, ""
