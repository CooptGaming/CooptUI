"""
Fresh install support: URLs for the base environment and the CoOpt release ZIPs.

The PRIMARY base is CoOpt's EMU ZIP (CoOptUI-EMU-*.zip): the complete,
self-consistent MQ family — core, Mono, E3, and the full plugin ecosystem
(nav/stick/advpath/casting + QoL set) compiled together in one solution, so
MQ2CoOptUI is safe and enabled. The stock E3NextAndMQNextBinary main-branch
zipball is the FALLBACK base when our release download fails; CoOpt runs in
Lua mode there (foreign MQ family — our plugin must not load). Download and
extraction are handled by installer.smart_install.
"""

import json
import urllib.error
import urllib.request

# The proven base environment: the E3NextAndMQNextBinary repo IS the binary
# distribution (its main branch is the install), so the branch zipball is the
# download. Static URL — no API call, no rate limiting.
BASE_BUNDLE_ZIP_URL = "https://github.com/RekkasGit/E3NextAndMQNextBinary/archive/refs/heads/main.zip"
BASE_BUNDLE_NAME = "E3NextAndMQNextBinary (main)"

# GitHub API endpoints
GITHUB_API_RELEASES = "https://api.github.com/repos/CooptGaming/CooptUI/releases/latest"
GITHUB_API_ALL_RELEASES = "https://api.github.com/repos/CooptGaming/CooptUI/releases"


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
    rate_limited = False
    for url in [GITHUB_API_RELEASES, GITHUB_API_ALL_RELEASES]:
        try:
            req = urllib.request.Request(url)
            req.add_header("Accept", "application/vnd.github+json")
            req.add_header("User-Agent", "CoOptUIPatcher")
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            # 403/429 = GitHub API rate limit — remember it so we don't report the
            # misleading "no release found" when nothing could actually be queried.
            if e.code in (403, 429):
                rate_limited = True
            continue
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

    if rate_limited:
        return None, None, (
            "GitHub is rate-limiting requests from your network (HTTP 403/429). "
            "Wait a few minutes and try again."
        )
    return None, None, "No release ZIP found on GitHub. Check that a release has been published."
