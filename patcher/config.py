"""
Persistent patcher configuration stored as patcher_config.json next to the executable.
"""

import json
import os
import sys

CONFIG_FILENAME = "patcher_config.json"

# Default config values
DEFAULTS = {
    "mq_root": "",
    "recent_paths": [],
    "window_x": None,
    "window_y": None,
}


def _config_path() -> str:
    """Return path to patcher_config.json next to the exe/script."""
    try:
        if hasattr(sys, "_MEIPASS"):
            # PyInstaller one-file: sys.executable is the real exe path
            base = os.path.dirname(os.path.abspath(sys.executable))
        else:
            # Running as script: config next to this file
            base = os.path.dirname(os.path.abspath(__file__))
    except Exception:
        base = os.path.abspath(".")
    return os.path.join(base, CONFIG_FILENAME)


def load() -> dict:
    """Load config from disk. Returns defaults if file missing or corrupt."""
    path = _config_path()
    config = dict(DEFAULTS)
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            config.update(data)
    except (OSError, json.JSONDecodeError):
        pass
    return config


def save(config: dict) -> bool:
    """Save config to disk. Returns True on success."""
    path = _config_path()
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(config, f, indent=2)
        return True
    except OSError:
        return False


def add_recent_path(config: dict, path: str) -> dict:
    """Add a path to recent_paths (deduped, max 5, most recent first)."""
    path = os.path.normpath(path)
    recent = config.get("recent_paths", [])
    # Remove if already present, then prepend
    recent = [p for p in recent if os.path.normpath(p) != path]
    recent.insert(0, path)
    config["recent_paths"] = recent[:5]
    config["mq_root"] = path
    return config
