"""
Fresh install flow: download latest release ZIP from GitHub Releases, extract to target folder.

The patcher prefers the full EMU ZIP (CoOptUI-EMU-*.zip) which contains MacroQuest + Mono +
E3Next + CoOpt UI — everything needed to play. Falls back to the CoOpt-UI-only ZIP if the
EMU ZIP is not available on the release.
"""

import json
import os
import tempfile
import urllib.error
import urllib.request
import zipfile
from typing import Callable

# GitHub API endpoints
GITHUB_API_RELEASES = "https://api.github.com/repos/RekkasGit/E3NextAndMQNextBinary/releases/latest"
GITHUB_API_ALL_RELEASES = "https://api.github.com/repos/RekkasGit/E3NextAndMQNextBinary/releases"


def get_latest_release_zip_url() -> tuple[str | None, str | None, str | None]:
    """
    Query GitHub Releases API for the latest published release.

    Prefers the full EMU ZIP (CoOptUI-EMU-*.zip) which includes MacroQuest, Mono, E3Next,
    and CoOpt UI. Falls back to the CoOpt-UI-only ZIP (CoOpt UI_v*.zip) if the EMU ZIP
    is not available.

    Returns:
        (zip_download_url, version_string, error_message)
        On success error_message is None; on failure url and version are None.
    """
    for url in [GITHUB_API_RELEASES, GITHUB_API_ALL_RELEASES]:
        try:
            req = urllib.request.Request(url)
            req.add_header("Accept", "application/vnd.github+json")
            req.add_header("User-Agent", "CoOptUIPatcher")
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except (urllib.error.URLError, OSError, json.JSONDecodeError):
            continue

        # /releases/latest returns a single object; /releases returns a list
        releases = data if isinstance(data, list) else [data]

        for release in releases:
            if not isinstance(release, dict):
                continue
            if release.get("draft", False):
                continue
            tag = release.get("tag_name", "")
            version = tag.lstrip("v") if tag else None
            assets = release.get("assets", [])

            # First pass: look for the full EMU ZIP (preferred)
            emu_url = None
            coopt_url = None
            for asset in assets:
                name = asset.get("name", "")
                dl = asset.get("browser_download_url")
                if not name.lower().endswith(".zip") or not dl:
                    continue
                name_lower = name.lower()
                if "emu" in name_lower and "coopt" in name_lower:
                    emu_url = dl
                elif "coopt" in name_lower:
                    coopt_url = dl

            # Prefer EMU ZIP, fall back to CoOpt-UI-only
            if emu_url:
                return emu_url, version, None
            if coopt_url:
                return coopt_url, version, None

    return None, None, "No release ZIP found on GitHub. Check that a release has been published."


def download_and_extract_zip(
    zip_url: str,
    target_dir: str,
    progress_callback: Callable[[str, float], None] | None = None,
) -> tuple[bool, str]:
    """
    Download ZIP from url, extract contents into target_dir.

    The ZIP contains top-level dirs like lua/, Macros/, config_templates/, resources/.
    These are extracted directly into target_dir (which should be the MQ root).

    progress_callback(status_message, fraction_0_to_1)
    Returns (success, message).
    """
    if not os.path.isdir(target_dir):
        try:
            os.makedirs(target_dir, exist_ok=True)
        except OSError as e:
            return False, f"Could not create target directory: {e}"

    if progress_callback:
        progress_callback("Downloading release ZIP...", 0.0)

    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".zip")
    try:
        req = urllib.request.Request(zip_url)
        req.add_header("User-Agent", "CoOptUIPatcher")
        with urllib.request.urlopen(req, timeout=120) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            downloaded = 0
            with os.fdopen(tmp_fd, "wb") as tmp_file:
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    tmp_file.write(chunk)
                    downloaded += len(chunk)
                    if progress_callback and total > 0:
                        progress_callback(
                            f"Downloading... {downloaded // 1024}KB / {total // 1024}KB",
                            min(downloaded / total * 0.7, 0.7),
                        )
                tmp_fd = -1  # Prevent double-close

        if progress_callback:
            progress_callback("Extracting files...", 0.75)

        with zipfile.ZipFile(tmp_path, "r") as zf:
            members = zf.namelist()
            total_members = len(members)
            for i, member in enumerate(members):
                if member.endswith("/"):
                    continue
                zf.extract(member, target_dir)
                if progress_callback and total_members > 0:
                    frac = 0.75 + (0.25 * (i + 1) / total_members)
                    progress_callback(f"Extracting: {member}", min(frac, 1.0))

        if progress_callback:
            progress_callback("Fresh install complete!", 1.0)

        return True, "Fresh install complete."

    except zipfile.BadZipFile:
        return False, "Downloaded file is not a valid ZIP. The release may be corrupted."
    except (urllib.error.URLError, OSError) as e:
        return False, f"Download failed: {e}"
    finally:
        if tmp_fd >= 0:
            try:
                os.close(tmp_fd)
            except OSError:
                pass
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
