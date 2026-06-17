"""
Smart install / repair.

Overlay the full CoOpt UI EMU bundle (CoOptUI-EMU-*.zip — MacroQuest + Mono + E3Next +
the MQ2CoOptUI plugin + CoOpt UI Lua/macros) onto a target MacroQuest folder, OVERWRITING
binaries/code/CoOpt but PRESERVING the user's config and per-character data.

This turns any starting state into a working CoOpt UI instance with one operation:
  - an empty folder            -> a full instance from scratch
  - a vanilla MacroQuest        -> base runtime (Mono, E3) + plugin + CoOpt UI added
  - the E3 distribution         -> plugin + CoOpt UI added, the user's E3/config kept
  - an existing CoOpt install    -> repaired / updated, the user's settings kept

Because the bundle already contains everything needed to run, a preserve-aware overlay is
all that's required — no per-piece detection. The preserve rules below are the only thing
that protects user data, so they are deliberately conservative.
"""

import os
import shutil
import tempfile
import urllib.error
import urllib.request
import zipfile
from typing import Callable, Optional

from fresh_install import get_latest_release_zip_url

ProgressCb = Optional[Callable[[str, float], None]]

# Extensions that are always code / binaries / UI assets — never preserved, always refreshed.
_CODE_EXTS = frozenset({".exe", ".dll", ".lua", ".mac", ".png", ".ico"})


def should_preserve(rel_path: str) -> bool:
    """
    Return True if a bundle file should NOT overwrite an existing file in the target — i.e.
    it is user config / per-character data we must keep. Only meaningful when the target
    file already exists (callers check existence separately).

    Principle: never clobber the user's config or character data; always refresh code and
    binaries. `rel_path` is a bundle-relative path (either separator).
    """
    p = rel_path.replace("\\", "/").lstrip("/").lower()
    ext = os.path.splitext(p)[1]
    base = os.path.basename(p)

    # Code, binaries, UI assets: always refresh.
    if ext in _CODE_EXTS:
        return False
    if p.startswith("resources/"):
        return False

    # MacroQuest instance/plugin config: EQ path + server list (MacroQuest.ini), per-character
    # MQ inis, overlay layouts, AutoLogin, and the e3 Macro Inis (the user's E3 char/server
    # settings) all live under config/. Keep whatever the user already has.
    if p.startswith("config/"):
        return True

    # CoOpt UI + macro user rules and state: sell/loot/shared rule inis, saved layout, the
    # onboarding flag, filter presets. (.mac macro CODE is excluded above and gets refreshed.)
    if p.startswith("macros/") and ext in (".ini", ".cfg"):
        return True

    # Login / account databases.
    if base.startswith("login.db"):
        return True

    # E3 per-character data lives under mono/macros/e3/<CharName>/ as small inis/txts.
    if p.startswith("mono/macros/e3/") and ext in (".ini", ".txt"):
        return True

    # Everything else (MQ/Mono/E3 runtime binaries, CoOpt Lua, resources, …) -> refresh.
    return False


def ensure_plugin_keys(ini_path: str) -> bool:
    """
    Ensure config/MacroQuest.ini loads the plugins CoOpt UI needs (mq2mono, MQ2CoOptUI,
    MQ2Lua) under [Plugins], without disturbing the rest of the file (EQ path, server list,
    comments, formatting). Line-based on purpose. Returns True if the file was changed.
    """
    needed = [("mq2mono", "1"), ("MQ2CoOptUI", "1"), ("MQ2Lua", "1")]
    try:
        with open(ini_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return False

    plugins_header = None
    existing = set()
    current = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            current = s[1:-1].strip().lower()
            if current == "plugins":
                plugins_header = i
            continue
        if current == "plugins" and "=" in s and not s.lstrip().startswith(";"):
            existing.add(s.split("=", 1)[0].strip().lower())

    missing = [(k, v) for (k, v) in needed if k.lower() not in existing]
    if not missing:
        return False

    additions = [f"{k}={v}" for (k, v) in missing]
    if plugins_header is not None:
        lines[plugins_header + 1:plugins_header + 1] = additions
    else:
        if lines and lines[-1].strip() != "":
            lines.append("")
        lines.append("[Plugins]")
        lines.extend(additions)

    try:
        with open(ini_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return True
    except OSError:
        return False


def _download_zip(url: str, progress_cb: ProgressCb = None) -> str:
    """Download a zip to a temp file and return its path. Raises on failure (caller cleans up)."""
    tmp_fd, tmp_path = tempfile.mkstemp(suffix=".zip")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "CoOptUIPatcher"})
        with urllib.request.urlopen(req, timeout=120) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            done = 0
            with os.fdopen(tmp_fd, "wb") as out:
                tmp_fd = -1  # owned by `out` now
                while True:
                    chunk = resp.read(65536)
                    if not chunk:
                        break
                    out.write(chunk)
                    done += len(chunk)
                    if progress_cb and total:
                        progress_cb(
                            f"Downloading... {done // 1048576}MB / {total // 1048576}MB",
                            min(done / total * 0.5, 0.5),
                        )
        return tmp_path
    except BaseException:
        if tmp_fd >= 0:
            try:
                os.close(tmp_fd)
            except OSError:
                pass
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def _bundle_source_root(extract_dir: str) -> str:
    """
    The EMU bundle normally extracts its files at the root (config/, lua/, MacroQuest.exe…),
    but tolerate a single wrapping folder too.
    """
    entries = os.listdir(extract_dir)
    if len(entries) == 1:
        only = os.path.join(extract_dir, entries[0])
        if os.path.isdir(only) and (
            os.path.isfile(os.path.join(only, "MacroQuest.exe"))
            or os.path.isdir(os.path.join(only, "lua"))
        ):
            return only
    return extract_dir


def overlay_bundle(zip_path: str, target_dir: str, progress_cb: ProgressCb = None) -> dict:
    """
    Extract `zip_path` to a temp dir, then copy each file into `target_dir`, skipping user
    config/data that already exists (per should_preserve). Finally make sure MacroQuest.ini
    loads our plugins. Returns {written, preserved, total}.
    """
    os.makedirs(target_dir, exist_ok=True)
    written = 0
    preserved = 0
    with tempfile.TemporaryDirectory(prefix="coopui_bundle_") as tmp:
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(tmp)
        src_root = _bundle_source_root(tmp)

        files = []
        for dirpath, _dirs, filenames in os.walk(src_root):
            for fn in filenames:
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, src_root)
                files.append((full, rel))

        total = len(files)
        macroquest_ini = None
        for i, (full, rel) in enumerate(files):
            rel_norm = rel.replace("\\", "/")
            dest = os.path.join(target_dir, rel)
            if rel_norm.lower() == "config/macroquest.ini":
                macroquest_ini = dest
            if os.path.exists(dest) and should_preserve(rel_norm):
                preserved += 1
            else:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(full, dest)
                written += 1
            if progress_cb and total:
                progress_cb(f"Installing: {rel_norm}", 0.5 + 0.5 * (i + 1) / total)

        if macroquest_ini and os.path.isfile(macroquest_ini):
            ensure_plugin_keys(macroquest_ini)

    return {"written": written, "preserved": preserved, "total": total}


def smart_install(target_dir: str, progress_cb: ProgressCb = None) -> tuple[bool, str]:
    """
    Full install / repair: download the latest EMU bundle and overlay it onto `target_dir`,
    preserving the user's config. Works for an empty folder, a vanilla MQ, the E3 distro, or
    an existing CoOpt install. progress_cb(message, fraction_0_to_1).
    """
    if progress_cb:
        progress_cb("Finding latest release...", 0.0)
    url, version, err = get_latest_release_zip_url()
    if err or not url:
        return False, err or "No release bundle found on GitHub."
    if "emu" not in url.lower():
        return False, (
            "The latest release has no full EMU bundle (only the CoOpt-UI-only zip). A full "
            "install needs CoOptUI-EMU-*.zip published on the release."
        )

    zip_path = None
    try:
        zip_path = _download_zip(url, progress_cb)
        summary = overlay_bundle(zip_path, target_dir, progress_cb)
    except zipfile.BadZipFile:
        return False, "Downloaded bundle is not a valid ZIP (the release may be corrupted)."
    except (urllib.error.URLError, OSError) as e:
        return False, f"Install failed: {e}"
    finally:
        if zip_path:
            try:
                os.unlink(zip_path)
            except OSError:
                pass

    if progress_cb:
        progress_cb("Install complete!", 1.0)
    vtag = f" (v{version})" if version else ""
    return True, (
        f"Install/repair complete{vtag}: {summary['written']} files written, "
        f"{summary['preserved']} user config file(s) preserved."
    )
