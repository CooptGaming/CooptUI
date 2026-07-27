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

import errno
import http.client
import os
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.request
import zipfile
from typing import Callable, Optional

from fresh_install import BASE_BUNDLE_NAME, BASE_BUNDLE_ZIP_URL, get_latest_release_zip_url
from updater import (
    check_for_default_config,
    check_for_updates,
    install_default_config,
    patch,
    write_installed_version,
)

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

    # ScriptTracker user settings: the update path deliberately never ships this file
    # (excluded from the release manifest), so Full Install / Repair must keep it too.
    if p == "lua/scripttracker/scripttracker.ini":
        return True

    # Login / account databases.
    if base.startswith("login.db"):
        return True

    # E3 per-character data lives under mono/macros/e3/<CharName>/ as small inis/txts.
    if p.startswith("mono/macros/e3/") and ext in (".ini", ".txt"):
        return True

    # Everything else (MQ/Mono/E3 runtime binaries, CoOpt Lua, resources, …) -> refresh.
    return False


def ensure_plugin_keys(ini_path: str, enable_coopt_plugin: bool = True) -> bool:
    """
    Ensure config/MacroQuest.ini loads the plugins CoOpt UI needs (mq2mono, MQ2Lua, and —
    only when enable_coopt_plugin — MQ2CoOptUI) under [Plugins], without disturbing the
    rest of the file (EQ path, server list, comments, formatting). Line-based on purpose.

    enable_coopt_plugin=False is for installs running the STOCK MQ family (the E3 base
    bundle): MQ2CoOptUI.dll is built against OUR MacroQuest (it links MQ2Main/eqlib and
    statically embeds LuaJIT), and loading it into a different MQ build corrupts the Lua
    runtime — field signature: crash in mq2lua invoking a Lua-bound command, hard freeze
    on /lua stop. In that mode any existing MQ2CoOptUI=1 is forced to 0 (the DLL may sit
    on disk; it just must never load). CoOpt UI runs fully in Lua/TLO fallback mode.

    Returns True if the file was changed.
    """
    needed = [("mq2mono", "1"), ("MQ2Lua", "1")]
    if enable_coopt_plugin:
        needed.append(("MQ2CoOptUI", "1"))
    try:
        with open(ini_path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return False

    plugins_header = None
    existing = set()
    current = None
    forced_off = False
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            current = s[1:-1].strip().lower()
            if current == "plugins":
                plugins_header = i
            continue
        if current == "plugins" and "=" in s and not s.lstrip().startswith(";"):
            key = s.split("=", 1)[0].strip()
            existing.add(key.lower())
            if not enable_coopt_plugin and key.lower() == "mq2cooptui":
                val = s.split("=", 1)[1].strip()
                if val != "0":
                    lines[i] = f"{key}=0"
                    forced_off = True

    missing = [(k, v) for (k, v) in needed if k.lower() not in existing]
    if not enable_coopt_plugin and "mq2cooptui" not in existing:
        missing.append(("MQ2CoOptUI", "0"))  # explicit 0 documents the decision in the ini
    if not missing and not forced_off:
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
                    if progress_cb:
                        if total:
                            progress_cb(
                                f"Downloading... {done // 1048576}MB / {total // 1048576}MB",
                                min(done / total * 0.5, 0.5),
                            )
                        elif done % (8 * 1048576) < 65536:
                            # No Content-Length (e.g. GitHub zipball streams chunked):
                            # show a byte counter with a slow creep so a large download
                            # doesn't look hung. Sized against ~1GB; clamps below 0.5.
                            progress_cb(
                                f"Downloading... {done // 1048576}MB",
                                min(0.02 + (done / (1024 * 1048576)) * 0.45, 0.48),
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


def _long_path(p: str) -> str:
    """
    Extended-length form (\\\\?\\...) so file ops survive Windows' 260-char
    MAX_PATH. The base bundle nests Mono files ~200 chars deep; add the temp
    extract prefix and paths blow past the limit on stock systems (WinError 3).
    Absolute-izes first ( \\\\?\\ requires absolute, backslash paths).
    """
    if os.name != "nt":
        return p
    p = os.path.abspath(p)
    if p.startswith("\\\\?\\"):
        return p
    if p.startswith("\\\\"):  # UNC share -> \\?\UNC\server\share\...
        return "\\\\?\\UNC" + p[1:]
    return "\\\\?\\" + p


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


def overlay_bundle(zip_path: str, target_dir: str, progress_cb: ProgressCb = None,
                   enable_coopt_plugin: bool = True) -> dict:
    """
    Extract `zip_path` to a temp dir, then copy each file into `target_dir`, skipping user
    config/data that already exists (per should_preserve). Finally make sure MacroQuest.ini
    loads our plugins. Returns {written, preserved, total}.
    """
    os.makedirs(target_dir, exist_ok=True)
    written = 0
    preserved = 0
    # Manual temp dir + extended-path rmtree: TemporaryDirectory's own cleanup walks
    # the SHORT path and dies on the deep Mono tree (same MAX_PATH problem).
    tmp = tempfile.mkdtemp(prefix="coopui_bundle_")
    try:
        # Extract member-by-member so the UI shows progress instead of freezing on one
        # big extractall. Extraction covers 0.5→0.75 of the bar; the copy pass 0.75→1.0.
        # All paths go through _long_path: the temp prefix + the bundle's deep Mono
        # tree exceed MAX_PATH otherwise.
        tmp_ext = _long_path(tmp)
        with zipfile.ZipFile(zip_path, "r") as zf:
            members = zf.namelist()
            n_members = len(members)
            for i, member in enumerate(members):
                if member.endswith("/"):
                    continue
                zf.extract(member, tmp_ext)
                if progress_cb and n_members:
                    progress_cb(
                        f"Extracting: {member}",
                        0.5 + 0.25 * (i + 1) / n_members,
                    )
        src_root = _bundle_source_root(tmp_ext)

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
            dest_ext = _long_path(dest)
            if rel_norm.lower() == "config/macroquest.ini":
                macroquest_ini = dest
            if os.path.exists(dest_ext) and should_preserve(rel_norm):
                preserved += 1
            else:
                os.makedirs(os.path.dirname(dest_ext), exist_ok=True)
                # Atomic install: copy to <dest>.tmp then os.replace, so a crash
                # mid-copy can never leave a truncated target (e.g. MacroQuest.exe).
                tmp_dest = dest_ext + ".tmp"
                try:
                    shutil.copy2(full, tmp_dest)
                    os.replace(tmp_dest, dest_ext)
                except OSError:
                    try:
                        os.remove(tmp_dest)
                    except OSError:
                        pass
                    raise
                written += 1
            if progress_cb and total:
                progress_cb(f"Installing: {rel_norm}", 0.75 + 0.25 * (i + 1) / total)

        if macroquest_ini and os.path.isfile(_long_path(macroquest_ini)):
            ensure_plugin_keys(macroquest_ini, enable_coopt_plugin=enable_coopt_plugin)
    finally:
        shutil.rmtree(_long_path(tmp), ignore_errors=True)

    return {"written": written, "preserved": preserved, "total": total}


# Critical CoOpt UI lua entrypoints. If any is missing/empty after an install the scripts
# cannot load, so we verify them before reporting success — catches a partial or locked extract.
# NOTE: these must be files that genuinely exist in the bundle. The coopui/ package is a slim
# shared core required by submodule path (coopui.core.events, coopui.utils.theme); it has NO
# top-level coopui/init.lua, so do not list one here (it would false-fail every install).
_CRITICAL_FILES = (
    "lua/coopui/core/events.lua",
    "lua/coopui/utils/theme.lua",
    "lua/coopui/version.lua",
    "lua/itemui/init.lua",
    "lua/itemui/app.lua",
    "lua/scripttracker/init.lua",
)


def verify_install(target_dir: str) -> list:
    """Return critical CoOpt UI files that are missing or empty under target_dir (empty list = OK)."""
    missing = []
    for rel in _CRITICAL_FILES:
        p = os.path.join(target_dir, rel.replace("/", os.sep))
        try:
            if not os.path.isfile(p) or os.path.getsize(p) == 0:
                missing.append(rel)
        except OSError:
            missing.append(rel)
    return missing


def is_macroquest_running() -> bool:
    """Best-effort check for a live MacroQuest / EverQuest process. Installing over a running
    client is the usual cause of a first launch stuck on 'loop or previous error': MQ2Lua's
    require cache gets poisoned by a load against files that are still being replaced, and that
    poison persists for the whole session until a restart. Never raises."""
    try:
        for image in ("MacroQuest.exe", "eqgame.exe"):
            out = subprocess.run(
                ["tasklist", "/FI", f"IMAGENAME eq {image}"],
                capture_output=True, text=True, timeout=10,
                creationflags=0x08000000,  # CREATE_NO_WINDOW — no console flash from a GUI app
            )
            if image.lower() in (out.stdout or "").lower():
                return True
    except Exception:
        pass
    return False


def smart_install(target_dir: str, repo_base_url: str, progress_cb: ProgressCb = None) -> tuple[bool, str]:
    """
    Full install / repair in two phases — the same layering every working install in
    the field has. progress_cb(message, fraction_0_to_1).

      Phase 1  BASE environment: the stock E3NextAndMQNextBinary bundle (full
               MacroQuest + Mono + E3 + the whole plugin ecosystem and its seed
               configs). CoOpt's own EMU zip is only the FALLBACK when that
               download fails — it carries just the from-source plugin subset,
               which boots but lacks plugins E3 uses (MQ2AdvPath etc.).
      Phase 2  CoOpt overlay via the release manifest — exactly what the update
               path installs (Lua, macros, skin, MQ2CoOptUI.dll from the release
               asset). Deliberately NO MacroQuest core binaries, so the base's MQ
               family stays internally consistent (mixed plugin/core builds are a
               crash vector).
      Phase 3  Default config (create-if-missing) + installed-version marker.

    Works for an empty folder, a vanilla MQ, the E3 distro, or an existing CoOpt
    install (preserve rules keep user config in all cases).
    """
    def seg(lo: float, hi: float) -> ProgressCb:
        def cb(msg: str, frac: float):
            if progress_cb:
                progress_cb(msg, lo + max(0.0, min(frac, 1.0)) * (hi - lo))
        return cb

    # --- Phase 1: base bundle ---
    base_note = ""
    zip_path = None
    # True when the base is the STOCK bundle (their MQ family): our plugin DLL is
    # ABI-incompatible with it and must not load (see ensure_plugin_keys docstring).
    # The EMU-zip fallback is OUR MQ family, where the plugin is required-and-safe.
    stock_base = True
    try:
        if progress_cb:
            progress_cb(f"Downloading base environment: {BASE_BUNDLE_NAME}...", 0.0)
        try:
            zip_path = _download_zip(BASE_BUNDLE_ZIP_URL, seg(0.0, 0.7))
        except (http.client.HTTPException, urllib.error.URLError, OSError) as e:
            if getattr(e, "errno", None) == errno.ENOSPC:
                return False, "Not enough disk space."
            zip_path = None
        if zip_path is None:
            stock_base = False
            # Fallback: CoOpt's EMU zip (reduced plugin set, still runnable).
            url, _ver, err = get_latest_release_zip_url()
            if err or not url or "emu" not in (url or "").lower():
                return False, (
                    f"Could not download the base bundle ({BASE_BUNDLE_NAME}) and no "
                    "CoOptUI-EMU-*.zip fallback was found on the release. Check your "
                    "connection and try again."
                )
            base_note = (
                "\n\nNOTE: the stock E3 base bundle could not be downloaded, so the reduced "
                "CoOpt EMU bundle was installed instead (core plugins only). Run Install/"
                "Repair again later to layer in the full plugin set."
            )
            if progress_cb:
                progress_cb("Base unavailable - downloading CoOpt EMU bundle...", 0.0)
            zip_path = _download_zip(url, seg(0.0, 0.7))
        summary = overlay_bundle(zip_path, target_dir, seg(0.0, 0.7),
                                 enable_coopt_plugin=not stock_base)
    except zipfile.BadZipFile:
        return False, "Downloaded bundle is not a valid ZIP (the download may be corrupted)."
    except (http.client.HTTPException, urllib.error.URLError, OSError) as e:
        if getattr(e, "errno", None) == errno.ENOSPC:
            return False, "Not enough disk space."
        return False, f"Install failed: {e}"
    finally:
        if zip_path:
            try:
                os.unlink(zip_path)
            except OSError:
                pass

    # --- Phase 2: CoOpt overlay from the release manifest ---
    p2 = seg(0.7, 0.95)
    if progress_cb:
        progress_cb("Applying CoOpt UI (release manifest)...", 0.7)
    to_update, manifest_version, _changelog, err = check_for_updates(repo_base_url, target_dir)
    if err:
        return False, "Base environment installed, but the CoOpt overlay failed: " + err
    coopt_written = 0
    if to_update:
        ok, msg, _skipped = patch(
            to_update, repo_base_url, target_dir,
            progress_callback=lambda i, t, p: p2(f"CoOpt: {p}", (i / t) if t else 1.0),
        )
        if not ok:
            return False, "Base environment installed, but the CoOpt overlay failed: " + msg
        coopt_written = len(to_update)

    # --- Phase 3: defaults + version marker ---
    p3 = seg(0.95, 1.0)
    defaults_note = ""
    defaults, derr = check_for_default_config(repo_base_url, target_dir)
    if not derr and defaults:
        ok, dmsg = install_default_config(
            defaults, repo_base_url, target_dir,
            progress_callback=lambda i, t, p: p3(f"Defaults: {p}", (i / t) if t else 1.0),
        )
        if not ok:
            defaults_note = f"\n\nNOTE: default config install had a problem ({dmsg}) - the UI creates critical files on first run."
    if manifest_version:
        write_installed_version(target_dir, manifest_version)

    # Catch a partial / locked install before telling the user it worked.
    missing = verify_install(target_dir)
    if missing:
        return False, (
            "Install INCOMPLETE — these required CoOpt UI files are missing or empty:\n  "
            + "\n  ".join(missing)
            + "\n\nClose MacroQuest completely and run the install again."
        )

    if progress_cb:
        progress_cb("Install complete!", 1.0)
    vtag = f" (CoOpt UI v{manifest_version})" if manifest_version else ""
    plugin_note = ""
    if stock_base:
        plugin_note = (
            "\n\nThis install runs the stock MacroQuest build, so the MQ2CoOptUI plugin is "
            "disabled (it requires CoOpt's own MQ build) — CoOpt UI runs fully in Lua mode."
        )
    mq_note = ""
    if is_macroquest_running():
        mq_note = (
            "\n\nNOTE: MacroQuest looks like it's running. Close it completely and relaunch "
            "before loading the UI — installing over a live client can leave the scripts stuck "
            'on "loop or previous error" until a restart.'
        )
    return True, (
        f"Install/repair complete{vtag}: {summary['written']} base files written, "
        f"{coopt_written} CoOpt file(s) applied, {summary['preserved']} user config file(s) preserved."
        "\n\nNext: start MacroQuest fresh, then in-game run  /lua run itemui  "
        "(and /lua run scripttracker)." + plugin_note + base_note + defaults_note + mq_note
    )
