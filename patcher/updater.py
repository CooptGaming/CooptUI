"""
GitHub-based updater: fetch release_manifest.json, compare local files by hash,
download only changed files via raw GitHub URLs, write to MQ root.
"""

import hashlib
import json
import os
import urllib.error
import urllib.request
from typing import Callable


def _raw_url(base_url: str, path: str) -> str:
    """Build raw GitHub URL for a repo path. base_url should not end with /."""
    path = path.replace("\\", "/").lstrip("/")
    return f"{base_url.rstrip('/')}/{path}" if path else base_url


def _sha256_file(file_path: str) -> str:
    """Return SHA256 hex digest of file contents. Returns '' if file missing or unreadable."""
    try:
        with open(file_path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return ""


def check_for_updates(
    repo_base_url: str,
    root_path: str,
    manifest_path: str = "release_manifest.json",
) -> tuple[list[dict], str | None]:
    """
    Fetch manifest from repo, compare each file to local; return list of entries that need update.

    repo_base_url: e.g. https://raw.githubusercontent.com/owner/repo/main
    root_path: validated MacroQuest root directory
    manifest_path: path to manifest in repo (e.g. "release_manifest.json" or "patcher/release_manifest.json")

    Returns:
        (list of manifest file entries to update, error_message or None)
        Each entry is a dict with "path" and "hash" (and optionally "version").
    """
    manifest_url = _raw_url(repo_base_url, manifest_path)
    try:
        req = urllib.request.Request(manifest_url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return [], (
                "Manifest not found (404). Check that release_manifest.json is in the repo "
                "and that the repo URL and branch in patcher.py are correct."
            )
        return [], "Could not reach GitHub. Check your connection."
    except (urllib.error.URLError, OSError):
        return [], "Could not reach GitHub. Check your connection."

    try:
        manifest = json.loads(data)
    except json.JSONDecodeError:
        return [], "Update list from repo is not valid JSON. Check release_manifest.json format."

    files = manifest.get("files")
    if not isinstance(files, list):
        return [], "Update list has no 'files' array. Check release_manifest.json format."

    to_update: list[dict] = []
    for entry in files:
        if not isinstance(entry, dict):
            continue
        path = entry.get("path")
        expected_hash = (entry.get("hash") or "").strip().lower()
        if not path or not expected_hash:
            continue
        local_path = os.path.join(root_path, path.replace("/", os.sep))
        local_hash = _sha256_file(local_path)
        if local_hash != expected_hash:
            to_update.append(entry)

    return to_update, None


def patch(
    files_to_download: list[dict],
    repo_base_url: str,
    root_path: str,
    progress_callback: Callable[[int, int, str], None] | None = None,
) -> tuple[bool, str]:
    """
    Download each file from raw GitHub and write to root_path. Creates parent dirs as needed.

    progress_callback(current_1based_index, total, path_or_message)
    Returns (success, message). Message is user-friendly.
    """
    total = len(files_to_download)
    if total == 0:
        return True, "Nothing to update."

    for i, entry in enumerate(files_to_download):
        path = entry.get("path")
        if not path:
            continue
        path_norm = path.replace("\\", "/")
        url = _raw_url(repo_base_url, path_norm)
        local_path = os.path.join(root_path, path_norm.replace("/", os.sep))

        if progress_callback:
            progress_callback(i + 1, total, path_norm)

        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=30) as resp:
                content = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return False, f"File not found: {path_norm}"
            return False, "Could not reach GitHub. Check your connection."
        except (urllib.error.URLError, OSError):
            return False, "Could not reach GitHub. Check your connection."

        try:
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            with open(local_path, "wb") as f:
                f.write(content)
        except OSError:
            return False, f"Could not write to {path_norm}. Check permissions."

    if progress_callback:
        progress_callback(total, total, "Done")
    return True, "Update complete."


def check_for_default_config(
    repo_base_url: str,
    root_path: str,
    manifest_path: str = "default_config_manifest.json",
) -> tuple[list[dict], str | None]:
    """
    Fetch default config manifest; return list of entries where install path is missing (create-if-missing).
    Each entry has "repoPath" and "installPath". Only includes entries for which the file does not exist.
    """
    manifest_url = _raw_url(repo_base_url, manifest_path)
    try:
        req = urllib.request.Request(manifest_url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return [], None  # No default config manifest is OK; skip install-only
        return [], "Could not reach GitHub (default config)."
    except (urllib.error.URLError, OSError):
        return [], "Could not reach GitHub (default config)."

    try:
        manifest = json.loads(data)
    except json.JSONDecodeError:
        return [], "default_config_manifest.json is not valid JSON."

    files = manifest.get("files")
    if not isinstance(files, list):
        return [], None

    to_install: list[dict] = []
    for entry in files:
        if not isinstance(entry, dict):
            continue
        repo_path = (entry.get("repoPath") or "").strip()
        install_path = (entry.get("installPath") or "").strip()
        if not repo_path or not install_path:
            continue
        local_path = os.path.join(root_path, install_path.replace("/", os.sep))
        if not os.path.isfile(local_path):
            to_install.append({"repoPath": repo_path, "installPath": install_path})

    return to_install, None


def install_default_config(
    entries: list[dict],
    repo_base_url: str,
    root_path: str,
    progress_callback: Callable[[int, int, str], None] | None = None,
) -> tuple[bool, str]:
    """
    Download each file from repo (repoPath) and write to root_path/installPath. Creates parent dirs.
    Only call with entries where the file is missing (create-if-missing).
    """
    total = len(entries)
    if total == 0:
        return True, "No default config to install."

    for i, entry in enumerate(entries):
        repo_path = (entry.get("repoPath") or "").replace("\\", "/")
        install_path = (entry.get("installPath") or "").replace("\\", "/")
        if not repo_path or not install_path:
            continue
        local_path = os.path.join(root_path, install_path.replace("/", os.sep))

        if progress_callback:
            progress_callback(i + 1, total, install_path)

        try:
            url = _raw_url(repo_base_url, repo_path)
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=30) as resp:
                content = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return False, f"Default config not found: {repo_path}"
            return False, "Could not reach GitHub."
        except (urllib.error.URLError, OSError):
            return False, "Could not reach GitHub."

        try:
            os.makedirs(os.path.dirname(local_path), exist_ok=True)
            with open(local_path, "wb") as f:
                f.write(content)
        except OSError:
            return False, f"Could not write {install_path}. Check permissions."

    if progress_callback:
        progress_callback(total, total, "Done")
    return True, "Default config installed."
