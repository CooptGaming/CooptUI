#!/usr/bin/env python3
r"""
CoOpt UI — Python Build System (Restructured)

Sources:
  - E3Next: https://github.com/RekkasGit/E3Next
  - MQ2Mono: https://github.com/RekkasGit/MQ2Mono
  - Prebuilt: https://github.com/RekkasGit/E3NextAndMQNextBinary/archive/refs/heads/main.zip
  - MacroQuest: https://github.com/macroquest/MacroQuest (EMU: rel-emu tag)

Outputs:
  1. Source/ — All source trees (E3Next, MQ2Mono, E3NextAndMQNextBinary, MacroQuest, CoOptUI)
  2. build_E3Source/ — Prebuilt + E3Next from source + Mono + CoOptUI + MQ2CoOptUI plugin
  3. build_MacroQuestDefault/ — MacroQuest from source + E3 + Mono + CoOptUI + MQ2CoOptUI plugin
  4. ZIPs: Full-E3Source, Full-MacroQuestDefault, Patcher-Plugin, PatcherOnly, Patcher

Sources/Outputs:
  Both deployment outputs use the same MacroQuest ref (EMU, from plugin/MQ_COMMIT_SHA.txt; default rel-emu)—i.e. both are "latest EMU" builds.
  E3 Source = prebuilt-compatible EMU base + our full MQ build + E3 + Mono + CoOptUI. Suited for Rekkas prebuilt users and as a standalone full pack.
  MacroQuest Default = same MQ ref, same stack, alternate assembly order. Both produce a full EMU pack with CoOptUI.

Usage:
  python build/build.py --output C:\MIS\FullDeployTest
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VERSION = "1.0.0"
E3NEXT_REPO = "https://github.com/RekkasGit/E3Next.git"
MQ2MONO_REPO = "https://github.com/RekkasGit/MQ2Mono.git"
MACROQUEST_REPO = "https://github.com/macroquest/MacroQuest.git"
PREBUILT_URL = "https://github.com/RekkasGit/E3NextAndMQNextBinary/archive/refs/heads/main.zip"

COOPT_LUA_DIRS = ["lua/itemui", "lua/coopui", "lua/scripttracker"]
COOPT_RESOURCES = [
    "resources/UIFiles/Default/EQUI.xml",
    "resources/UIFiles/Default/MQUI_ItemColorAnimation.xml",
    "resources/UIFiles/Default/ItemColorBG.tga",
]
COOPT_CONFIG_TEMPLATES = "config_templates"
COOPT_ROOT_FILES = ["DEPLOY.md", "CHANGELOG.md"]
COOPT_PLUGIN_DLL = "plugins/MQ2CoOptUI.dll"
# CoopHelper (C#) is deprecated — MQ2CoOptUI (C++) is the only supported backend. Left for rollback reference:
# COOPT_COOPHELPER_DST = "Mono/macros/coophelper/CoopHelper.dll"
# ItemUI keybinding: MQ2CustomBinds plugin + config file
COOPT_CONFIG_MQ2CUSTOMBINDS = "config/MQ2CustomBinds.txt"
COOPT_CONFIG_MACROQUEST_INI = "config/MacroQuest.ini"
# Patcher-equivalent: default config (create-if-missing into Macros/sell_config, shared_config, loot_config)
DEFAULT_CONFIG_MANIFEST = "default_config_manifest.json"
COOPT_CORE_INI_TEMPLATE = "config_templates/config/CoOptCore.ini"
COOPT_CORE_INI_DST = "config/CoOptCore.ini"
# COOPT_COOPHELPER_SRC = "csharp/coophelper/bin/Release/CoopHelper.dll"  # deprecated
# config_templates subdir -> (Macros parent, Macros subdir) for fallback when manifest missing
DEFAULT_CONFIG_INSTALL_MAP = [
    ("sell_config", "Macros", "sell_config"),
    ("shared_config", "Macros", "shared_config"),
    ("loot_config", "Macros", "loot_config"),
]
ITEMUI_EXCLUDE_DIRS = {"docs"}
ITEMUI_EXCLUDE_FILES = {"upvalue_check.lua"}
DEFAULT_CMAKE_PATH = Path("C:/MIS/CMake-3.30")
# EMU builds require Win32 (32-bit); rel-emu tag targets EMU servers
MQ_BUILD_PLATFORM = "Win32"
MQ_VCPKG_TRIPLET = "x86-windows-static"
PLUGIN_DLL_CANDIDATES = [
    "build/solution/bin/release/plugins/MQ2CoOptUI.dll",
    "build/solution/bin/Release/plugins/MQ2CoOptUI.dll",
    "build/solution/plugins/Release/MQ2CoOptUI.dll",
]
VCPKG_EXE_URL = "https://github.com/microsoft/vcpkg-tool/releases/download/2024-04-23/vcpkg.exe"
_PATCHER_BUILT = False
_PATCHER_EXE_CACHE: Path | None = None


def _platform_to_vcpkg_triplet(platform: str) -> str:
    return "x86-windows-static" if platform == "Win32" else "x64-windows-static"


def setup_logging() -> None:
    logging.basicConfig(level=logging.INFO, format="%(message)s")


def log_phase(phase: str) -> None:
    logging.info("")
    logging.info("=" * 60)
    logging.info(f"  {phase}")
    logging.info("=" * 60)


def log_step(msg: str) -> None:
    logging.info(f"  [OK] {msg}")


def log_warn(msg: str) -> None:
    logging.warning(f"  [WARN] {msg}")


def log_err(msg: str) -> None:
    logging.error(f"  [ERR] {msg}")


def _rmtree_onerror(func, path, exc_info):
    """Best-effort handler for readonly files during tree delete."""
    try:
        os.chmod(path, 0o700)
        func(path)
    except OSError:
        pass


def safe_rmtree(path: Path, retries: int = 8, base_delay_s: float = 0.5) -> None:
    """Delete directory tree with retries to survive transient file locks on Windows."""
    if not path.exists():
        return
    last_exc: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            shutil.rmtree(path, onerror=_rmtree_onerror)
            return
        except (PermissionError, OSError) as exc:
            last_exc = exc
            time.sleep(base_delay_s * attempt)
    # Last resort on Windows: move locked tree aside so build can proceed.
    try:
        stale = path.with_name(f"{path.name}.stale-{int(time.time())}")
        os.replace(path, stale)
        log_warn(f"Could not fully delete {path}; moved aside to {stale}")
        return
    except OSError:
        pass
    if last_exc:
        raise last_exc


def download_file(url: str, dest: Path) -> None:
    req = Request(url, headers={"User-Agent": "CoOptUI-Build/1.0"})
    with urlopen(req, timeout=180) as resp:
        with open(dest, "wb") as f:
            shutil.copyfileobj(resp, f)


def _ensure_vcpkg_bootstrapped(vcpkg: Path) -> None:
    """Ensure vcpkg.exe exists; retry bootstrap and fall back to direct download."""
    exe = vcpkg / "vcpkg.exe"
    if exe.exists():
        return

    bootstrap = vcpkg / "bootstrap-vcpkg.bat"
    last_exc: Exception | None = None
    for attempt in range(1, 4):
        try:
            subprocess.run([str(bootstrap)], cwd=vcpkg, check=True, shell=True)
            if exe.exists():
                return
        except subprocess.CalledProcessError as exc:
            last_exc = exc
            log_warn(f"vcpkg bootstrap failed (attempt {attempt}/3); retrying")
            time.sleep(min(5 * attempt, 15))

    # Network/bootstrap fallback: fetch vcpkg.exe directly.
    try:
        log_warn("vcpkg bootstrap retries exhausted; downloading vcpkg.exe directly")
        download_file(VCPKG_EXE_URL, exe)
    except (OSError, URLError, HTTPError) as exc:
        if last_exc:
            raise last_exc
        raise exc

    if not exe.exists():
        if last_exc:
            raise last_exc
        raise RuntimeError("vcpkg bootstrap failed and direct vcpkg.exe download did not produce vcpkg.exe")


def _git_clone(repo: str, dest: Path, ref: str = "master") -> bool:
    if dest.exists():
        try:
            subprocess.run(["git", "fetch", "origin"], cwd=dest, check=True, capture_output=True)
            subprocess.run(["git", "fetch", "origin", ref], cwd=dest, check=True, capture_output=True)
            subprocess.run(["git", "checkout", "-f", ref], cwd=dest, check=True, capture_output=True)
            # Ensure reruns start from a pristine tree (we patch build files during previous attempts).
            # FETCH_HEAD works for both branches and tags (e.g. rel-emu)
            subprocess.run(["git", "reset", "--hard", "FETCH_HEAD"], cwd=dest, check=True, capture_output=True)
            subprocess.run(["git", "clean", "-fd"], cwd=dest, check=True, capture_output=True)
            subprocess.run(["git", "submodule", "update", "--init", "--recursive"], cwd=dest, check=True, capture_output=True)
            subprocess.run(["git", "submodule", "foreach", "--recursive", "git reset --hard"], cwd=dest, check=True, capture_output=True)
            subprocess.run(["git", "submodule", "foreach", "--recursive", "git clean -fd"], cwd=dest, check=True, capture_output=True)
        except subprocess.CalledProcessError:
            log_warn(f"git update failed for {dest.name}")
        return True
    try:
        subprocess.run(["git", "clone", "--recursive", repo, str(dest)], check=True, capture_output=True)
        subprocess.run(["git", "checkout", ref], cwd=dest, check=True, capture_output=True)
        subprocess.run(["git", "submodule", "update", "--init", "--recursive"], cwd=dest, check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        log_err(f"git clone failed: {e}")
        return False
    return True


# ---------------------------------------------------------------------------
# Phase 1: Sources
# ---------------------------------------------------------------------------


def phase_sources(output_dir: Path, repo_root: Path) -> dict[str, Path]:
    """Download/clone all sources. Returns paths dict."""
    log_phase("SOURCES")

    src_dir = output_dir / "Source"
    src_dir.mkdir(parents=True, exist_ok=True)

    paths = {}

    # E3Next
    e3_src = src_dir / "E3Next"
    if _git_clone(E3NEXT_REPO, e3_src, "master"):
        paths["E3Next"] = e3_src
        log_step(f"E3Next -> {e3_src}")
    else:
        paths["E3Next"] = None

    # MQ2Mono
    mono_src = src_dir / "MQ2Mono"
    if _git_clone(MQ2MONO_REPO, mono_src, "master"):
        paths["MQ2Mono"] = mono_src
        log_step(f"MQ2Mono -> {mono_src}")
    else:
        paths["MQ2Mono"] = None

    # Prebuilt
    zip_path = output_dir / "E3NextAndMQNextBinary-main.zip"
    if not zip_path.exists():
        log_step("Downloading prebuilt...")
        download_file(PREBUILT_URL, zip_path)
    prebuilt_extract = src_dir / "E3NextAndMQNextBinary"
    if prebuilt_extract.exists():
        safe_rmtree(prebuilt_extract)
    prebuilt_extract.mkdir(parents=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        for name in zf.namelist():
            if name.startswith("E3NextAndMQNextBinary-main/"):
                rel = name[len("E3NextAndMQNextBinary-main/"):]
                if not rel:
                    continue
                tgt = prebuilt_extract / rel.replace("/", os.sep)
                if rel.endswith("/"):
                    tgt.mkdir(parents=True, exist_ok=True)
                else:
                    tgt.parent.mkdir(parents=True, exist_ok=True)
                    with zf.open(name) as src, open(tgt, "wb") as dst:
                        shutil.copyfileobj(src, dst)
    paths["Prebuilt"] = prebuilt_extract
    log_step(f"Prebuilt -> {prebuilt_extract}")

    # MacroQuest (default: rel-emu for EMU; override via MQ_COMMIT_SHA.txt)
    mq_ref = "rel-emu"
    sha_file = repo_root / "plugin" / "MQ_COMMIT_SHA.txt"
    if sha_file.is_file():
        for line in sha_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                mq_ref = line
                break
    mq_src = src_dir / "MacroQuest"
    if _git_clone(MACROQUEST_REPO, mq_src, mq_ref):
        paths["MacroQuest"] = mq_src
        log_step(f"MacroQuest -> {mq_src} (ref={mq_ref})")
    else:
        paths["MacroQuest"] = None

    # CoOptUI (from repo, no built plugin)
    coop_src = src_dir / "CoOptUI"
    if coop_src.exists():
        safe_rmtree(coop_src)
    coop_src.mkdir(parents=True)
    for d in COOPT_LUA_DIRS:
        s = repo_root / d.replace("/", os.sep)
        if s.is_dir():
            dst = coop_src / d.replace("/", os.sep)
            shutil.copytree(s, dst)
            if d == "lua/itemui":
                for x in ITEMUI_EXCLUDE_DIRS:
                    (dst / x).exists() and safe_rmtree(dst / x)
                (dst / "upvalue_check.lua").exists() and (dst / "upvalue_check.lua").unlink()
    (coop_src / "lua" / "mq").mkdir(parents=True, exist_ok=True)
    if (repo_root / "lua" / "mq" / "ItemUtils.lua").is_file():
        shutil.copy2(repo_root / "lua" / "mq" / "ItemUtils.lua", coop_src / "lua" / "mq" / "ItemUtils.lua")
    (coop_src / "Macros").mkdir(parents=True, exist_ok=True)
    (coop_src / "Macros").mkdir(parents=True, exist_ok=True)
    for m in ["sell.mac", "loot.mac"]:
        if (repo_root / "Macros" / m).is_file():
            shutil.copy2(repo_root / "Macros" / m, coop_src / "Macros" / m)
    (coop_src / "Macros" / "shared_config").mkdir(parents=True, exist_ok=True)
    for f in (repo_root / "Macros" / "shared_config").glob("*.mac") or []:
        shutil.copy2(f, coop_src / "Macros" / "shared_config" / f.name)
    if (repo_root / COOPT_CONFIG_TEMPLATES).is_dir():
        shutil.copytree(repo_root / COOPT_CONFIG_TEMPLATES, coop_src / COOPT_CONFIG_TEMPLATES)
    (coop_src / "resources" / "UIFiles" / "Default").mkdir(parents=True, exist_ok=True)
    for r in COOPT_RESOURCES:
        s = repo_root / r.replace("/", os.sep)
        if s.is_file():
            shutil.copy2(s, coop_src / "resources" / "UIFiles" / "Default" / Path(r).name)
    for f in COOPT_ROOT_FILES:
        if (repo_root / f).is_file():
            shutil.copy2(repo_root / f, coop_src / f)
    shutil.copytree(repo_root / "patcher", coop_src / "patcher")
    shutil.copytree(repo_root / "plugin", coop_src / "plugin")
    paths["CoOptUI"] = coop_src
    log_step(f"CoOptUI -> {coop_src}")

    return paths


# ---------------------------------------------------------------------------
# Build E3Next
# ---------------------------------------------------------------------------


def build_e3next(e3_src: Path) -> Path | None:
    """Build E3Next C# solution. Returns path to E3 output dir or None."""
    sln = e3_src / "MQ2MonoSharp.sln"
    if not sln.exists():
        log_warn("MQ2MonoSharp.sln not found")
        return None
    try:
        # E3Next still uses packages.config-style references; explicit restore is required.
        subprocess.run(
            ["msbuild", str(sln), "/t:Restore", "/p:RestorePackagesConfig=true", "/v:minimal"],
            cwd=e3_src,
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["msbuild", str(sln), "/p:Configuration=Release", "/v:minimal"],
            cwd=e3_src,
            check=True,
            capture_output=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        log_warn(f"E3Next build failed: {e}")
        return None
    out = e3_src / "E3Next" / "bin" / "Release"
    if out.exists():
        return out
    out = e3_src / "bin" / "Release"
    return out if out.exists() else None


# ---------------------------------------------------------------------------
# Toolchain environment helpers
# ---------------------------------------------------------------------------


def _prepend_cmake_to_path(env: dict[str, str], cmake_path: Path) -> None:
    """Ensure preferred CMake is first on PATH so vcpkg uses a compatible version."""
    cmake_bin = cmake_path / "bin" if (cmake_path / "bin").exists() else cmake_path
    if cmake_bin.exists():
        env["PATH"] = str(cmake_bin.resolve()) + os.pathsep + env.get("PATH", "")


def _repair_vcpkg_ninja_command(root: Path) -> int:
    """Repair stale local edits where vcpkg parallel configure command was changed to --version."""
    count = 0
    for path in root.rglob("*.cmake"):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
            orig = text
            text = text.replace("\"${NINJA}\" --version", "\"${NINJA}\" -v")
            text = text.replace("${NINJA} --version", "${NINJA} -v")
            if text != orig:
                path.write_text(text, encoding="utf-8")
                count += 1
        except (OSError, ValueError):
            pass
    return count


def _ensure_mq_build_platform(mq_src: Path, expected_platform: str) -> None:
    """Delete stale build/solution when CMake cache platform mismatches expected platform."""
    build_dir = mq_src / "build" / "solution"
    cache = build_dir / "CMakeCache.txt"
    if not cache.exists():
        return
    try:
        text = cache.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return

    m = re.search(r"^CMAKE_GENERATOR_PLATFORM:INTERNAL=(.+)$", text, re.MULTILINE)
    if m and m.group(1).strip().lower() != expected_platform.strip().lower():
        try:
            safe_rmtree(build_dir)
            log_step(f"Removed stale MQ build cache (platform {m.group(1).strip()} -> {expected_platform})")
        except OSError:
            pass


def _patch_crashpad_config(config_path: Path) -> bool:
    """Patch crashpad config to link release/debug libs by configuration."""
    if not config_path.exists():
        return False
    try:
        text = config_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False

    old_block = """foreach(LIB_NAME ${CRASHPAD_LIBRARIES})
  find_library(_LIB ${LIB_NAME})
  target_link_libraries(crashpad INTERFACE ${_LIB})
  unset(_LIB CACHE)
endforeach()"""
    new_block = """foreach(LIB_NAME ${CRASHPAD_LIBRARIES})
  find_library(_LIB_RELEASE ${LIB_NAME} PATHS "${_IMPORT_PREFIX}/lib" NO_DEFAULT_PATH)
  find_library(_LIB_DEBUG ${LIB_NAME} PATHS "${_IMPORT_PREFIX}/debug/lib" NO_DEFAULT_PATH)
  if(_LIB_RELEASE)
    target_link_libraries(crashpad INTERFACE "$<$<NOT:$<CONFIG:Debug>>:${_LIB_RELEASE}>")
  endif()
  if(_LIB_DEBUG)
    target_link_libraries(crashpad INTERFACE "$<$<CONFIG:Debug>:${_LIB_DEBUG}>")
  endif()
  unset(_LIB_RELEASE CACHE)
  unset(_LIB_DEBUG CACHE)
endforeach()"""

    if old_block not in text:
        return False
    try:
        config_path.write_text(text.replace(old_block, new_block), encoding="utf-8")
        return True
    except OSError:
        return False


def _patch_crashpad_duplicate_guard(config_path: Path) -> bool:
    """Prevent duplicate crashpad target definitions in generated/package config."""
    if not config_path.exists():
        return False
    try:
        text = config_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False

    if "add_library(crashpad" not in text:
        return False
    if re.search(r"if\s*\(\s*TARGET\s+crashpad\s*\)\s*return\(\)\s*endif\(\)", text, re.IGNORECASE | re.MULTILINE):
        return False

    replaced = text.replace(
        "add_library(crashpad INTERFACE)",
        "if(TARGET crashpad)\n  return()\nendif()\nadd_library(crashpad INTERFACE)",
        1,
    )
    if replaced == text:
        return False
    try:
        config_path.write_text(replaced, encoding="utf-8")
        return True
    except OSError:
        return False


# ---------------------------------------------------------------------------
# Build MQ2CoOptUI plugin
# ---------------------------------------------------------------------------


def build_mq2cooptui(
    mq_src: Path,
    plugin_src: Path,
    cmake_path: Path,
    repo_root: Path,
    platform: str = MQ_BUILD_PLATFORM,
    vcpkg_triplet: str | None = None,
) -> Path | None:
    """Build MQ2CoOptUI. Returns path to DLL or None."""
    if vcpkg_triplet is None:
        vcpkg_triplet = _platform_to_vcpkg_triplet(platform)
    plugin_link = mq_src / "plugins" / "MQ2CoOptUI"
    plugin_link.parent.mkdir(parents=True, exist_ok=True)
    if plugin_link.exists():
        if plugin_link.is_symlink():
            plugin_link.unlink()
        else:
            safe_rmtree(plugin_link)
    try:
        os.symlink(plugin_src.resolve(), plugin_link, target_is_directory=True)
    except OSError:
        shutil.copytree(plugin_src, plugin_link)

    gotchas = repo_root / "scripts" / "apply-build-gotchas.ps1"
    if gotchas.is_file():
        try:
            subprocess.run(
                ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(gotchas), "-MQClone", str(mq_src)],
                check=True,
                capture_output=True,
            )
        except subprocess.CalledProcessError:
            pass

    vcpkg = mq_src / "contrib" / "vcpkg"
    _ensure_mq_build_platform(mq_src, platform)
    if not (vcpkg / "vcpkg.exe").exists():
        _ensure_vcpkg_bootstrapped(vcpkg)
    repaired = _repair_vcpkg_ninja_command(vcpkg)
    if repaired:
        log_step(f"Repaired stale vcpkg ninja command in {repaired} .cmake file(s)")
    installed = mq_src / "build" / "solution" / "vcpkg_installed"
    if installed.exists():
        repaired_installed = _repair_vcpkg_ninja_command(installed)
        if repaired_installed:
            log_step(f"Repaired stale vcpkg_installed ninja command in {repaired_installed} .cmake file(s)")
    # Ensure crashpad config links correct lib variant per config (avoid Debug CRT libs in Release).
    for p in (
        vcpkg / "ports" / "crashpad" / "crashpadConfig.cmake.in",
        vcpkg / "ports" / "crashpad-backtrace" / "crashpadConfig.cmake.in",
        mq_src / "contrib" / "vcpkg-ports" / "crashpad-backtrace" / "crashpadConfig.cmake.in",
    ):
        if _patch_crashpad_duplicate_guard(p):
            log_step(f"Patched crashpad duplicate-target guard: {p.name}")
        if _patch_crashpad_config(p):
            log_step(f"Patched crashpad config template: {p.name}")

    cmake_exe = cmake_path / "bin" / "cmake.exe" if (cmake_path / "bin").exists() else cmake_path / "cmake.exe"
    cmake_str = str(cmake_exe) if cmake_exe.exists() else "cmake"
    env = os.environ.copy()
    env["VCPKG_ROOT"] = str(vcpkg.resolve())
    env["VCPKG_DEFAULT_TRIPLET"] = vcpkg_triplet
    env["VCPKG_TARGET_TRIPLET"] = vcpkg_triplet
    env["VCPKG_BUILD_TYPE"] = "release"
    _prepend_cmake_to_path(env, cmake_path)

    def run_cmake() -> bool:
        try:
            subprocess.run(
                [cmake_str, "-B", "build/solution", "-G", "Visual Studio 17 2022", "-A", platform,
                 "-DVCPKG_TARGET_TRIPLET=" + vcpkg_triplet, "-DVCPKG_BUILD_TYPE=release",
                 "-DMQ_BUILD_CUSTOM_PLUGINS=ON", "-DMQ_BUILD_LAUNCHER=ON", "-DMQ_REGENERATE_SOLUTION=OFF"],
                cwd=mq_src,
                env=env,
                check=True,
            )
            for p in (
                mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad" / "crashpadConfig.cmake",
                mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad-backtrace" / "crashpadConfig.cmake",
            ):
                _patch_crashpad_duplicate_guard(p)
                _patch_crashpad_config(p)
            subprocess.run(
                [cmake_str, "--build", "build/solution", "--config", "Release", "--clean-first", "--target", "MQ2CoOptUI"],
                cwd=mq_src,
                env=env,
                check=True,
                timeout=1800,
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
            # Configure can fail after generating crashpadConfig; patch generated files and let outer retry run.
            for p in (
                mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad" / "crashpadConfig.cmake",
                mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad-backtrace" / "crashpadConfig.cmake",
            ):
                _patch_crashpad_duplicate_guard(p)
                _patch_crashpad_config(p)
            return False

    if not run_cmake():
        # One retry after an initial configure/build failure can recover transient download/setup issues.
        if not run_cmake():
            return None

    for cand in PLUGIN_DLL_CANDIDATES:
        dll = mq_src / cand.replace("/", os.sep)
        if dll.is_file():
            return dll
    return None


# ---------------------------------------------------------------------------
# Copy CoOptUI onto build
# ---------------------------------------------------------------------------


def copy_coopt_ui(repo_root: Path, build_root: Path, plugin_dll: Path | None) -> None:
    """Overlay CoOptUI files onto build."""
    for d in COOPT_LUA_DIRS:
        s = repo_root / d.replace("/", os.sep)
        if s.is_dir():
            dst = build_root / d.replace("/", os.sep)
            if dst.exists():
                safe_rmtree(dst)
            shutil.copytree(s, dst)
            if d == "lua/itemui":
                for x in ITEMUI_EXCLUDE_DIRS:
                    (dst / x).exists() and safe_rmtree(dst / x)
                (dst / "upvalue_check.lua").exists() and (dst / "upvalue_check.lua").unlink()
    (build_root / "lua" / "mq").mkdir(parents=True, exist_ok=True)
    if (repo_root / "lua" / "mq" / "ItemUtils.lua").is_file():
        shutil.copy2(repo_root / "lua" / "mq" / "ItemUtils.lua", build_root / "lua" / "mq" / "ItemUtils.lua")
    (build_root / "Macros").mkdir(parents=True, exist_ok=True)
    for m in ["sell.mac", "loot.mac"]:
        if (repo_root / "Macros" / m).is_file():
            shutil.copy2(repo_root / "Macros" / m, build_root / "Macros" / m)
    (build_root / "Macros" / "shared_config").mkdir(parents=True, exist_ok=True)
    for f in (repo_root / "Macros" / "shared_config").glob("*.mac") or []:
        shutil.copy2(f, build_root / "Macros" / "shared_config" / f.name)
    if (repo_root / COOPT_CONFIG_TEMPLATES).is_dir():
        ct_dst = build_root / COOPT_CONFIG_TEMPLATES
        if ct_dst.exists():
            safe_rmtree(ct_dst)
        shutil.copytree(repo_root / COOPT_CONFIG_TEMPLATES, ct_dst)
    (build_root / "resources" / "UIFiles" / "Default").mkdir(parents=True, exist_ok=True)
    for r in COOPT_RESOURCES:
        s = repo_root / r.replace("/", os.sep)
        if s.is_file():
            shutil.copy2(s, build_root / "resources" / "UIFiles" / "Default" / Path(r).name)
    for f in COOPT_ROOT_FILES:
        if (repo_root / f).is_file():
            shutil.copy2(repo_root / f, build_root / f)
    if plugin_dll and plugin_dll.is_file():
        (build_root / "plugins").mkdir(parents=True, exist_ok=True)
        plugin_dst = build_root / COOPT_PLUGIN_DLL.replace("/", os.sep)
        # Avoid copying file onto itself when caller already passed build_root/plugins/MQ2CoOptUI.dll
        if plugin_dll.resolve() != plugin_dst.resolve():
            shutil.copy2(plugin_dll, plugin_dst)


def deploy_keybind_config(repo_root: Path, build_root: Path) -> None:
    """Deploy ItemUI keybinding: MQ2CustomBinds.txt and ensure mq2mono=1, MQ2CoOptUI=1, mq2custombinds=1 in MacroQuest.ini."""
    config_dir = build_root / "config"
    config_dir.mkdir(parents=True, exist_ok=True)

    # Copy MQ2CustomBinds.txt so ItemUI toggle key (e.g. shift+q) works
    src_binds = repo_root / COOPT_CONFIG_MQ2CUSTOMBINDS.replace("/", os.sep)
    if src_binds.is_file():
        dst_binds = build_root / COOPT_CONFIG_MQ2CUSTOMBINDS.replace("/", os.sep)
        shutil.copy2(src_binds, dst_binds)
        log_step("config/MQ2CustomBinds.txt (ItemUI keybind)")

    # Ensure mq2mono=1, MQ2CoOptUI=1, mq2custombinds=1 in MacroQuest.ini (match build-and-deploy.ps1)
    ini_path = build_root / COOPT_CONFIG_MACROQUEST_INI.replace("/", os.sep)
    required_plugins = ["mq2mono=1", "MQ2CoOptUI=1", "mq2custombinds=1"]
    if ini_path.is_file():
        try:
            text = ini_path.read_text(encoding="utf-8", errors="replace")
            missing = [
                plug for plug in required_plugins
                if not re.search(rf"{re.escape(plug.split('=')[0])}\s*=\s*1", text, re.IGNORECASE)
            ]
            if missing:
                if re.search(r"\[Plugins\]", text, re.IGNORECASE):
                    text = re.sub(r"(\[Plugins\])", r"\1\n" + "\n".join(missing), text, count=1)
                else:
                    text = text.rstrip() + "\n\n[Plugins]\n" + "\n".join(missing) + "\n"
                ini_path.write_text(text, encoding="utf-8")
                log_step("MacroQuest.ini: mq2mono=1, MQ2CoOptUI=1, mq2custombinds=1")
        except (OSError, ValueError):
            pass
    else:
        # Create minimal ini so keybinding works out of the box (match PS1 minimal)
        minimal = (
            "[MacroQuest]\nMacroQuestWinClassName=__MacroQuestTray\nMacroQuestWinName=MacroQuest\n"
            "ShowLoaderConsole=0\nShowMacroQuestConsole=1\n\n[Plugins]\n"
            "mq2lua=1\nmq2mono=1\nMQ2CoOptUI=1\nmq2chatwnd=1\nmq2custombinds=1\n"
            "mq2itemdisplay=1\nmq2map=1\nmq2nav=1\nmq2dannet=1\n"
        )
        try:
            ini_path.write_text(minimal, encoding="utf-8")
            log_step("config/MacroQuest.ini (minimal)")
        except OSError:
            pass


def deploy_default_config(repo_root: Path, build_root: Path) -> None:
    """Deploy patcher-equivalent default config: Macros/sell_config, shared_config, loot_config + config/CoOptCore.ini (create-if-missing)."""
    count = 0

    # 1. Default config manifest: config_templates -> Macros/sell_config, shared_config, loot_config
    manifest_path = repo_root / DEFAULT_CONFIG_MANIFEST
    if manifest_path.is_file():
        try:
            data = json.loads(manifest_path.read_text(encoding="utf-8"))
            entries = data.get("files") or []
            for entry in entries:
                repo_path = (entry.get("repoPath") or "").replace("/", os.sep)
                install_path = (entry.get("installPath") or "").replace("/", os.sep)
                if not repo_path or not install_path:
                    continue
                src = repo_root / repo_path
                dst = build_root / install_path
                if src.is_file() and (not dst.exists() or not dst.is_file()):
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(src, dst)
                    count += 1
        except (OSError, json.JSONDecodeError, ValueError):
            pass
    else:
        # Fallback: copy config_templates subdirs into Macros (create-if-missing per file)
        ct = repo_root / COOPT_CONFIG_TEMPLATES.replace("/", os.sep)
        if ct.is_dir():
            for subdir, macro_parent, macro_subdir in DEFAULT_CONFIG_INSTALL_MAP:
                src_dir = ct / subdir
                if not src_dir.is_dir():
                    continue
                for f in src_dir.iterdir():
                    if not f.is_file() or f.name.startswith(".") or f.name.lower().endswith(".md"):
                        continue
                    dst = build_root / macro_parent / macro_subdir / f.name
                    if not dst.exists():
                        dst.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(f, dst)
                        count += 1

    # 2. CoOptCore.ini for plugin (config_templates/config/CoOptCore.ini -> config/CoOptCore.ini)
    src_ini = repo_root / COOPT_CORE_INI_TEMPLATE.replace("/", os.sep)
    dst_ini = build_root / COOPT_CORE_INI_DST.replace("/", os.sep)
    if src_ini.is_file() and (not dst_ini.exists() or not dst_ini.is_file()):
        dst_ini.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_ini, dst_ini)
        count += 1

    if count > 0:
        log_step(f"Default config (patcher-equivalent): {count} file(s) -> Macros/sell_config, shared_config, loot_config, config/")


def deploy_mono_runtime(build_root: Path, mono_src: Path | None) -> None:
    """Deploy full Mono runtime: mono-2.0-sgen.dll + resources/mono/32bit (match build-and-deploy.ps1)."""
    if not mono_src or not mono_src.exists():
        if not (build_root / "mono-2.0-sgen.dll").exists():
            log_warn("Mono runtime not found; MQ2Mono may not load. Clone MQ2Mono or provide mono-2.0-sgen.dll.")
        return

    mono_dll = mono_src / "mono-2.0-sgen.dll"
    if mono_dll.exists():
        shutil.copy2(mono_dll, build_root / "mono-2.0-sgen.dll")
        log_step("mono-2.0-sgen.dll from MQ2Mono")

    # MQ2Mono requires resources/mono/32bit for mono_set_dirs (match PS1)
    for sub in ["resources/Mono/32bit", "resources/mono/32bit"]:
        mono32_src = mono_src / sub.replace("/", os.sep)
        if mono32_src.exists():
            mono32_dst = build_root / "resources" / "mono" / "32bit"
            if mono32_dst.exists():
                safe_rmtree(mono32_dst)
            mono32_dst.mkdir(parents=True, exist_ok=True)
            shutil.copytree(mono32_src, mono32_dst, dirs_exist_ok=True)
            log_step("resources/mono/32bit (Mono runtime for /mono load)")
            break

    # Copy BCL if present (legacy)
    for sub in ["lib/mono", "lib/Mono"]:
        mono_bcl = mono_src / sub.replace("/", os.sep)
        if mono_bcl.exists():
            dst_bcl = build_root / "lib" / "mono"
            dst_bcl.mkdir(parents=True, exist_ok=True)
            for f in mono_bcl.iterdir():
                if f.is_file():
                    shutil.copy2(f, dst_bcl / f.name)
                else:
                    shutil.copytree(f, dst_bcl / f.name)
            log_step("Mono BCL")
            break


def deploy_emu_config(build_root: Path, repo_root: Path) -> None:
    """Remove AutoExec.cfg, create e3 Bot Inis / e3 Macro Inis, add README.txt (match build-and-deploy.ps1)."""
    config_dir = build_root / "config"

    # Remove AutoExec.cfg - E3 loads via /mono load e3 when user chooses
    autoexec = config_dir / "Autoexec" / "AutoExec.cfg"
    if autoexec.exists():
        autoexec.unlink()
        log_step("Removed config/Autoexec/AutoExec.cfg (E3 loads with /mono load e3)")

    # E3 Bot Inis / E3 Macro Inis placeholders
    e3_bot_inis = config_dir / "e3 Bot Inis"
    e3_macro_inis = config_dir / "e3 Macro Inis"
    if not e3_bot_inis.exists():
        e3_bot_inis.mkdir(parents=True, exist_ok=True)
        (e3_bot_inis / "README.txt").write_text(
            "Place E3Next bot INI files here.\n"
            "Filename format: CharacterName_ServerShortName.ini\n"
            "See: https://github.com/RekkasGit/E3Next/wiki\n",
            encoding="utf-8",
        )
        log_step("Created config/e3 Bot Inis placeholder")
    if not e3_macro_inis.exists():
        e3_macro_inis.mkdir(parents=True, exist_ok=True)
        log_step("Created config/e3 Macro Inis placeholder")

    # README.txt (ready-to-go instructions)
    readme = build_root / "README.txt"
    readme.write_text(
        "MacroQuest EMU + E3Next + Mono + CoOpt UI (ready-to-go)\n\n"
        "CONTENTS\n"
        "  - MacroQuest launcher and EMU base (32-bit)\n"
        "  - MQ2Mono plugin + mono-2.0-sgen.dll (C#/E3Next runtime)\n"
        "  - E3Next (mono/macros/e3/) - load with /mono load e3\n"
        "  - MQ2CoOptUI plugin + CoOpt UI Lua, macros, UI resources\n"
        "  - config/MacroQuest.ini (mq2mono=1, MQ2CoOptUI=1, mq2lua=1, etc.)\n"
        "  - Full CoOptUI3 reference: plugins, lua, macros, modules, resources, utilities\n\n"
        "HOW TO USE\n"
        "  1. Unzip this folder anywhere (e.g. C:\\MQ-EMU).\n"
        "  2. Run MacroQuest.exe.\n"
        "  3. Launch EverQuest (EMU). Plugins load from config/MacroQuest.ini.\n"
        "  4. Load E3 with /mono load e3 when in game.\n\n"
        "FIRST RUN - What you should see\n"
        "  - MQ2CoOptUI loads automatically (MQ2CoOptUI=1 in config). In chat you will see:\n"
        "      [MQ2CoOptUI] v1.0.0 loaded - INI, IPC, cursor, items, loot, window capabilities ready.\n"
        "  - To confirm: /echo ${CoOptUI.Version}  (should print 1.0.0)\n"
        "  - Lua can use: require('plugin.MQ2CoOptUI') for ini, ipc, window, items, loot, cursor APIs.\n\n"
        "FOLDER STRUCTURE (do not move files)\n"
        "  MacroQuest.exe, mono-2.0-sgen.dll  (root)\n"
        "  config/MacroQuest.ini\n"
        "  plugins/MQ2Mono.dll, MQ2CoOptUI.dll, ...\n"
        "  lua/itemui, lua/coopui, lua/scripttracker, lua/mq\n"
        "  Macros/sell.mac, loot.mac, shared_config/\n"
        "  mono/macros/e3/   (E3Next)\n"
        "  config/e3 Bot Inis/   (place E3 bot INIs here)\n"
        "  config/e3 Macro Inis/\n"
        "  resources/UIFiles/Default/\n",
        encoding="utf-8",
    )
    log_step("README.txt (included in zip)")


def copy_e3next_with_cleanup(e3_out: Path, build_dir: Path) -> None:
    """Copy E3Next to Mono/macros/e3, SQLite.Interop to mono/libs, trim dev artifacts (match PS1)."""
    e3_dst = build_dir / "Mono" / "macros" / "e3"
    e3_dst.mkdir(parents=True, exist_ok=True)
    for f in e3_out.iterdir():
        if f.is_file():
            shutil.copy2(f, e3_dst / f.name)

    # E3 expects mono/libs/32bit and 64bit for SQLite.Interop.dll
    e3x86 = e3_dst / "x86"
    e3x64 = e3_dst / "x64"
    mono_libs32 = build_dir / "mono" / "libs" / "32bit"
    mono_libs64 = build_dir / "mono" / "libs" / "64bit"
    if e3x86.exists():
        sqlite32 = e3x86 / "SQLite.Interop.dll"
        if sqlite32.exists():
            mono_libs32.mkdir(parents=True, exist_ok=True)
            shutil.copy2(sqlite32, mono_libs32 / "SQLite.Interop.dll")
            log_step("SQLite.Interop.dll -> mono/libs/32bit")
    if e3x64.exists():
        sqlite64 = e3x64 / "SQLite.Interop.dll"
        if sqlite64.exists():
            mono_libs64.mkdir(parents=True, exist_ok=True)
            shutil.copy2(sqlite64, mono_libs64 / "SQLite.Interop.dll")
            log_step("SQLite.Interop.dll -> mono/libs/64bit")

    # Trim dev/build artifacts (match CoOptUI3 layout)
    for d in [e3x64, e3x86]:
        if d.exists():
            safe_rmtree(d)
    for p in e3_dst.rglob("*.pdb"):
        if p.is_file():
            p.unlink()
    for p in e3_dst.rglob("*.xml"):
        if p.is_file():
            p.unlink()
    log_step("E3Next copied (trimmed .pdb, .xml, x64, x86)")


# ---------------------------------------------------------------------------
# Phase 2: Build E3 Source
# ---------------------------------------------------------------------------


def phase_build_e3_source(
    output_dir: Path,
    paths: dict,
    repo_root: Path,
    cmake_path: Path,
    platform: str = MQ_BUILD_PLATFORM,
    vcpkg_triplet: str | None = None,
) -> Path | None:
    """Build 1: Prebuilt + E3Next from source + Mono + CoOptUI + MQ2CoOptUI."""
    log_phase("BUILD 1: E3 Source (Prebuilt + E3Next source + Mono + CoOptUI + Plugin)")

    prebuilt = paths.get("Prebuilt")
    if not prebuilt or not prebuilt.exists():
        log_err("Prebuilt not available")
        return None

    build_dir = output_dir / "build_E3Source"
    if build_dir.exists():
        safe_rmtree(build_dir)
    shutil.copytree(prebuilt, build_dir)
    log_step(f"Base: prebuilt -> {build_dir}")

    # E3Next from source (with SQLite.Interop + cleanup to match PS1)
    e3_src = paths.get("E3Next")
    if e3_src and e3_src.exists():
        e3_out = build_e3next(e3_src)
        if e3_out:
            copy_e3next_with_cleanup(e3_out, build_dir)
            log_step("E3Next built from source -> Mono/macros/e3/")
        else:
            log_warn("E3Next build failed; using prebuilt E3")
    else:
        log_warn("E3Next source not available")

    # MQ2CoOptUI plugin (built from same MQ ref as prebuilt, e.g. rel-emu, so it can be used as drop-in for that prebuilt when toolchains align)
    mq_src = paths.get("MacroQuest")
    if not mq_src or not mq_src.exists():
        raise RuntimeError("MacroQuest source not available; cannot build MQ2CoOptUI.dll for E3 Source build")
    plugin_dll = build_mq2cooptui(
        mq_src, repo_root / "plugin" / "MQ2CoOptUI", cmake_path, repo_root,
        platform=platform, vcpkg_triplet=vcpkg_triplet,
    )
    if not plugin_dll or not plugin_dll.is_file():
        raise RuntimeError("MQ2CoOptUI build failed for E3 Source build; refusing to fall back to prebuilt plugin")
    log_step("MQ2CoOptUI built from source")

    # Full MQ build and copy: overwrite prebuilt MQ core with our build so plugin ABI matches (same as MacroQuest Default)
    if vcpkg_triplet is None:
        vcpkg_triplet = _platform_to_vcpkg_triplet(platform)
    cmake_exe = cmake_path / "bin" / "cmake.exe" if (cmake_path / "bin").exists() else cmake_path / "cmake.exe"
    cmake_str = str(cmake_exe) if cmake_exe.exists() else "cmake"
    env = os.environ.copy()
    env["VCPKG_DEFAULT_TRIPLET"] = vcpkg_triplet
    env["VCPKG_TARGET_TRIPLET"] = vcpkg_triplet
    env["VCPKG_BUILD_TYPE"] = "release"
    _prepend_cmake_to_path(env, cmake_path)
    for p in (
        mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad" / "crashpadConfig.cmake",
        mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad-backtrace" / "crashpadConfig.cmake",
    ):
        if p.exists():
            _patch_crashpad_duplicate_guard(p)
            _patch_crashpad_config(p)
    try:
        subprocess.run(
            [cmake_str, "--build", "build/solution", "--config", "Release", "--clean-first"],
            cwd=mq_src,
            env=env,
            check=True,
            capture_output=True,
            timeout=3600,
        )
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f"MacroQuest full build failed for E3 Source: {e}")
    mq_bin = mq_src / "build" / "solution" / "bin" / "release"
    if not mq_bin.exists():
        mq_bin = mq_src / "build" / "solution" / "bin" / "Release"
    if mq_bin.exists():
        for f in mq_bin.iterdir():
            if f.is_file() and f.suffix.lower() in (".exe", ".dll"):
                shutil.copy2(f, build_dir / f.name)
        plugins_src = mq_bin / "plugins"
        if plugins_src.exists():
            (build_dir / "plugins").mkdir(parents=True, exist_ok=True)
            for p in plugins_src.iterdir():
                if p.is_file():
                    shutil.copy2(p, build_dir / "plugins" / p.name)
        log_step("MacroQuest binaries from full source build")
    else:
        raise RuntimeError("MacroQuest build output not found after full build for E3 Source")

    # CoOptUI files
    copy_coopt_ui(repo_root, build_dir, plugin_dll)
    log_step("CoOptUI files overlaid")

    # ItemUI keybinding (MQ2CustomBinds.txt + mq2custombinds=1)
    deploy_keybind_config(repo_root, build_dir)

    # Default config (patcher-equivalent: Macros/sell_config, shared_config, loot_config, config/CoOptCore.ini)
    deploy_default_config(repo_root, build_dir)

    # Full Mono runtime (resources/mono/32bit) - match build-and-deploy.ps1
    deploy_mono_runtime(build_dir, paths.get("MQ2Mono"))

    # EMU config: remove AutoExec.cfg, e3 Bot/Macro Inis, README.txt
    deploy_emu_config(build_dir, repo_root)

    # CoopHelper (C#) build/copy removed — deprecated; MQ2CoOptUI (C++) is the only supported backend.

    # Patcher
    patcher_exe = build_patcher(repo_root)
    if patcher_exe:
        shutil.copy2(patcher_exe, build_dir / "CoOptUIPatcher.exe")
        log_step("CoOptUIPatcher.exe")

    return build_dir


def build_patcher(repo_root: Path) -> Path | None:
    global _PATCHER_BUILT, _PATCHER_EXE_CACHE
    if _PATCHER_BUILT:
        return _PATCHER_EXE_CACHE if (_PATCHER_EXE_CACHE and _PATCHER_EXE_CACHE.exists()) else None

    patcher_dir = repo_root / "patcher"
    spec = patcher_dir / "patcher.spec"
    if not spec.exists():
        _PATCHER_BUILT = True
        _PATCHER_EXE_CACHE = None
        return None
    try:
        reqs = patcher_dir / "requirements.txt"
        if reqs.exists():
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "-r", str(reqs), "-q"],
                check=True,
                capture_output=True,
                timeout=300,
            )
        subprocess.run(
            [sys.executable, "-m", "PyInstaller", "--noconfirm", str(spec)],
            cwd=patcher_dir,
            check=True,
            capture_output=True,
            timeout=300,
        )
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired) as e:
        log_warn(f"Patcher build skipped: {e}")
        _PATCHER_BUILT = True
        _PATCHER_EXE_CACHE = None
        return None
    exe = patcher_dir / "dist" / "CoOptUIPatcher.exe"
    _PATCHER_BUILT = True
    _PATCHER_EXE_CACHE = exe if exe.exists() else None
    return _PATCHER_EXE_CACHE


# ---------------------------------------------------------------------------
# Phase 3: Build MacroQuest Default
# ---------------------------------------------------------------------------
# TODO: MacroQuest Default currently starts from the prebuilt zip.
# A future option could build the deploy from MQ build output only
# (build/solution/bin/release + Mono + E3 + CoOptUI layers), bypassing the zip entirely.


def phase_build_macroquest_default(
    output_dir: Path,
    paths: dict,
    repo_root: Path,
    cmake_path: Path,
    platform: str = MQ_BUILD_PLATFORM,
    vcpkg_triplet: str | None = None,
) -> Path | None:
    """Build 2: MacroQuest from source + E3 + Mono + CoOptUI + MQ2CoOptUI."""
    if vcpkg_triplet is None:
        vcpkg_triplet = _platform_to_vcpkg_triplet(platform)
    log_phase("BUILD 2: MacroQuest Default (MQ source + E3 + Mono + CoOptUI + Plugin)")

    prebuilt = paths.get("Prebuilt")
    mq_src = paths.get("MacroQuest")
    if not prebuilt or not mq_src or not mq_src.exists():
        log_err("Prebuilt or MacroQuest source not available")
        return None

    # Build full MacroQuest (including MQ2CoOptUI)
    plugin_dll = build_mq2cooptui(
        mq_src, repo_root / "plugin" / "MQ2CoOptUI", cmake_path, repo_root,
        platform=platform, vcpkg_triplet=vcpkg_triplet,
    )
    # Try full build to get MacroQuest.exe, MQ2Main.dll etc (plugin build may have partial output)
    cmake_exe = cmake_path / "bin" / "cmake.exe" if (cmake_path / "bin").exists() else cmake_path / "cmake.exe"
    cmake_str = str(cmake_exe) if cmake_exe.exists() else "cmake"
    env = os.environ.copy()
    env["VCPKG_DEFAULT_TRIPLET"] = vcpkg_triplet
    env["VCPKG_TARGET_TRIPLET"] = vcpkg_triplet
    env["VCPKG_BUILD_TYPE"] = "release"
    _prepend_cmake_to_path(env, cmake_path)
    for p in (
        mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad" / "crashpadConfig.cmake",
        mq_src / "build" / "solution" / "vcpkg_installed" / vcpkg_triplet / "share" / "crashpad-backtrace" / "crashpadConfig.cmake",
    ):
        if p.exists():
            _patch_crashpad_duplicate_guard(p)
            _patch_crashpad_config(p)
    try:
        subprocess.run(
            [cmake_str, "--build", "build/solution", "--config", "Release", "--clean-first"],
            cwd=mq_src,
            env=env,
            check=True,
            capture_output=True,
            timeout=3600,
        )
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f"MacroQuest source build failed: {e}")
    if not plugin_dll or not plugin_dll.is_file():
        raise RuntimeError("MQ2CoOptUI build failed for MacroQuest Default build")

    # Start from prebuilt structure, replace MQ binaries with our build
    build_dir = output_dir / "build_MacroQuestDefault"
    if build_dir.exists():
        safe_rmtree(build_dir)
    shutil.copytree(prebuilt, build_dir)

    # Replace MQ core from our MacroQuest build (try release and Release for Win32/x64)
    mq_bin = mq_src / "build" / "solution" / "bin" / "release"
    if not mq_bin.exists():
        mq_bin = mq_src / "build" / "solution" / "bin" / "Release"
    if mq_bin.exists():
        for f in mq_bin.iterdir():
            if f.is_file() and f.suffix.lower() in (".exe", ".dll"):
                shutil.copy2(f, build_dir / f.name)
        plugins_src = mq_bin / "plugins"
        if plugins_src.exists():
            (build_dir / "plugins").mkdir(parents=True, exist_ok=True)
            for p in plugins_src.iterdir():
                if p.is_file():
                    shutil.copy2(p, build_dir / "plugins" / p.name)
        log_step("MacroQuest binaries from source build")
    else:
        raise RuntimeError("MacroQuest build output not found after source build")

    # E3Next from source (with SQLite.Interop + cleanup to match PS1)
    e3_src = paths.get("E3Next")
    if e3_src and e3_src.exists():
        e3_out = build_e3next(e3_src)
        if e3_out:
            copy_e3next_with_cleanup(e3_out, build_dir)
            log_step("E3Next built from source")

    # Full Mono runtime (mono-2.0-sgen.dll + resources/mono/32bit) - match build-and-deploy.ps1
    deploy_mono_runtime(build_dir, paths.get("MQ2Mono"))

    # EMU config: remove AutoExec.cfg, e3 Bot/Macro Inis, README.txt
    deploy_emu_config(build_dir, repo_root)

    # Plugin (must be built from source for ABI correctness)
    (build_dir / "plugins").mkdir(parents=True, exist_ok=True)
    shutil.copy2(plugin_dll, build_dir / "plugins" / "MQ2CoOptUI.dll")
    log_step("MQ2CoOptUI from build")

    # CoOptUI files
    copy_coopt_ui(repo_root, build_dir, build_dir / "plugins" / "MQ2CoOptUI.dll" if (build_dir / "plugins" / "MQ2CoOptUI.dll").exists() else None)
    log_step("CoOptUI files overlaid")

    # ItemUI keybinding (MQ2CustomBinds.txt + mq2custombinds=1)
    deploy_keybind_config(repo_root, build_dir)

    # Default config (patcher-equivalent: Macros/sell_config, shared_config, loot_config, config/CoOptCore.ini)
    deploy_default_config(repo_root, build_dir)

    # CoopHelper (C#) build/copy removed — deprecated; MQ2CoOptUI (C++) is the only supported backend.

    # Patcher
    patcher_exe = build_patcher(repo_root)
    if patcher_exe:
        shutil.copy2(patcher_exe, build_dir / "CoOptUIPatcher.exe")
        log_step("CoOptUIPatcher.exe")

    return build_dir


# ---------------------------------------------------------------------------
# Phase 4: Staging + ZIPs
# ---------------------------------------------------------------------------


def phase_staging_and_zips(
    output_dir: Path,
    repo_root: Path,
    version: str,
    build_e3: Path | None,
    build_mq: Path | None,
) -> tuple[Path | None, Path | None, list[Path]]:
    """Create distribution staging and all ZIPs."""
    log_phase("STAGING & ZIPs")

    patcher_exe = build_patcher(repo_root)
    staging = output_dir / "dist_staging"
    if staging.exists():
        safe_rmtree(staging)
    staging.mkdir(parents=True)

    for d in COOPT_LUA_DIRS:
        s = repo_root / d.replace("/", os.sep)
        if s.is_dir():
            dst = staging / d.replace("/", os.sep)
            shutil.copytree(s, dst)
            if d == "lua/itemui":
                for x in ITEMUI_EXCLUDE_DIRS:
                    (dst / x).exists() and safe_rmtree(dst / x)
                (dst / "upvalue_check.lua").exists() and (dst / "upvalue_check.lua").unlink()
    (staging / "lua" / "mq").mkdir(parents=True, exist_ok=True)
    if (repo_root / "lua" / "mq" / "ItemUtils.lua").is_file():
        shutil.copy2(repo_root / "lua" / "mq" / "ItemUtils.lua", staging / "lua" / "mq" / "ItemUtils.lua")
    (staging / "Macros").mkdir(parents=True, exist_ok=True)
    for m in ["sell.mac", "loot.mac"]:
        if (repo_root / "Macros" / m).is_file():
            shutil.copy2(repo_root / "Macros" / m, staging / "Macros" / m)
    (staging / "Macros" / "shared_config").mkdir(parents=True, exist_ok=True)
    for f in (repo_root / "Macros" / "shared_config").glob("*.mac") or []:
        shutil.copy2(f, staging / "Macros" / "shared_config" / f.name)
    if (repo_root / COOPT_CONFIG_TEMPLATES).is_dir():
        shutil.copytree(repo_root / COOPT_CONFIG_TEMPLATES, staging / COOPT_CONFIG_TEMPLATES)
    (staging / "resources" / "UIFiles" / "Default").mkdir(parents=True, exist_ok=True)
    for r in COOPT_RESOURCES:
        s = repo_root / r.replace("/", os.sep)
        if s.is_file():
            shutil.copy2(s, staging / "resources" / "UIFiles" / "Default" / Path(r).name)
    for f in COOPT_ROOT_FILES:
        if (repo_root / f).is_file():
            shutil.copy2(repo_root / f, staging / f)
    if patcher_exe:
        shutil.copy2(patcher_exe, staging / "CoOptUIPatcher.exe")

    created = []

    def _zip_dir(src: Path, zip_path: Path, name: str):
        if zip_path.exists():
            zip_path.unlink()
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(src):
                for f in files:
                    p = Path(root) / f
                    zf.write(p, p.relative_to(src))
        log_step(f"{name}: {zip_path}")
        created.append(zip_path)

    # 1. Full E3 Source
    if build_e3 and build_e3.exists():
        _zip_dir(build_e3, output_dir / f"CoOptUI-Full-E3Source_v{version}.zip", "Full E3 Source")

    # 2. Full MacroQuest Default
    if build_mq and build_mq.exists():
        _zip_dir(build_mq, output_dir / f"CoOptUI-Full-MacroQuestDefault_v{version}.zip", "Full MacroQuest Default")

    # 3. CoOptUI + Patcher + Plugin
    staging_plugin = output_dir / "dist_staging_plugin"
    if staging_plugin.exists():
        safe_rmtree(staging_plugin)
    shutil.copytree(staging, staging_plugin)
    plugin_src = (build_e3 or build_mq or Path()) / "plugins" / "MQ2CoOptUI.dll"
    if plugin_src.exists():
        (staging_plugin / "plugins").mkdir(parents=True, exist_ok=True)
        shutil.copy2(plugin_src, staging_plugin / "plugins" / "MQ2CoOptUI.dll")
    _zip_dir(staging_plugin, output_dir / f"CoOptUI-Patcher-Plugin_v{version}.zip", "CoOptUI + Patcher + Plugin")
    safe_rmtree(staging_plugin)

    # 4. Patcher only
    if patcher_exe:
        zip_p = output_dir / f"CoOptUI-PatcherOnly_v{version}.zip"
        if zip_p.exists():
            zip_p.unlink()
        with zipfile.ZipFile(zip_p, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(patcher_exe, "CoOptUIPatcher.exe")
        log_step(f"Patcher only: {zip_p}")
        created.append(zip_p)

    # 5. CoOptUI + Patcher
    _zip_dir(staging, output_dir / f"CoOptUI-Patcher_v{version}.zip", "CoOptUI + Patcher")

    return staging, patcher_exe, created


# ---------------------------------------------------------------------------
# Phase 5: Final Verification
# ---------------------------------------------------------------------------


def phase_final_verification(
    output_dir: Path,
    version: str,
    build_e3: Path | None,
    build_mq: Path | None,
    created_zips: list[Path] | None = None,
) -> None:
    """Verify required build outputs and CoOpt payloads are present."""
    log_phase("FINAL VERIFICATION")

    def _check(path: Path, label: str, missing: list[str]) -> None:
        if path.exists():
            log_step(f"{label}: {path}")
        else:
            missing.append(f"{label}: {path}")

    missing: list[str] = []

    # Verify build outputs and required CoOpt payloads.
    if build_e3:
        _check(build_e3 / "MacroQuest.exe", "E3Source launcher", missing)
        _check(build_e3 / "plugins" / "MQ2CoOptUI.dll", "E3Source plugin", missing)
        _check(build_e3 / "lua" / "itemui" / "init.lua", "E3Source lua/itemui", missing)
        _check(build_e3 / "lua" / "coopui" / "version.lua", "E3Source lua/coopui", missing)
        _check(build_e3 / "config" / "MQ2CustomBinds.txt", "E3Source keybind config", missing)
        _check(build_e3 / "config" / "MacroQuest.ini", "E3Source MacroQuest.ini", missing)
        _check(build_e3 / "config" / "CoOptCore.ini", "E3Source CoOptCore.ini", missing)
        _check(build_e3 / "Macros" / "sell_config" / "sell_flags.ini", "E3Source default sell config", missing)
        _check(build_e3 / "Macros" / "loot_config" / "loot_flags.ini", "E3Source default loot config", missing)
        _check(build_e3 / "Macros" / "shared_config" / "epic_classes.ini", "E3Source default shared config", missing)
        _check(build_e3 / "resources" / "UIFiles" / "Default" / "EQUI.xml", "E3Source UI resource", missing)
        _check(build_e3 / "mono-2.0-sgen.dll", "E3Source mono runtime", missing)

    if build_mq:
        _check(build_mq / "plugins" / "MQ2CoOptUI.dll", "MacroQuestDefault plugin", missing)
        _check(build_mq / "MacroQuest.exe", "MacroQuestDefault launcher", missing)
        _check(build_mq / "lua" / "itemui" / "init.lua", "MacroQuestDefault lua/itemui", missing)
        _check(build_mq / "config" / "MQ2CustomBinds.txt", "MacroQuestDefault keybind config", missing)
        _check(build_mq / "config" / "CoOptCore.ini", "MacroQuestDefault CoOptCore.ini", missing)
        _check(build_mq / "Macros" / "sell_config" / "sell_flags.ini", "MacroQuestDefault default sell config", missing)
        _check(build_mq / "resources" / "UIFiles" / "Default" / "EQUI.xml", "MacroQuestDefault UI resource", missing)

    # Verify zip artifacts.
    expected_zips = [
        output_dir / f"CoOptUI-Patcher_v{version}.zip",
        output_dir / f"CoOptUI-Patcher-Plugin_v{version}.zip",
    ]
    if build_e3:
        expected_zips.append(output_dir / f"CoOptUI-Full-E3Source_v{version}.zip")
    if build_mq:
        expected_zips.append(output_dir / f"CoOptUI-Full-MacroQuestDefault_v{version}.zip")
    for zp in expected_zips:
        _check(zp, "ZIP", missing)

    # Optional consistency check: stage-reported zips should exist too.
    if created_zips:
        for zp in created_zips:
            _check(zp, "Created ZIP", missing)

    if missing:
        raise RuntimeError("Final verification failed:\n  - " + "\n  - ".join(missing))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    setup_logging()
    parser = argparse.ArgumentParser(description="CoOpt UI Build System (Restructured)")
    parser.add_argument("--output", "-o", required=True, type=Path)
    parser.add_argument("--version", default=os.environ.get("RELEASE_VERSION", VERSION))
    parser.add_argument("--cmake-path", type=Path, default=DEFAULT_CMAKE_PATH)
    parser.add_argument(
        "--platform",
        choices=["Win32", "x64"],
        default="Win32",
        help="MQ build platform: Win32 (EMU, 32-bit) or x64 (Live). Default: Win32",
    )
    parser.add_argument("--skip-e3-build", action="store_true", help="Skip E3 Source build")
    parser.add_argument("--skip-mq-build", action="store_true", help="Skip MacroQuest Default build")
    parser.add_argument("--verify-only", action="store_true", help="Run final verification only (no build)")
    args = parser.parse_args()

    output_dir = args.output.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    repo_root = Path(__file__).resolve().parent.parent

    mq_platform = args.platform
    mq_triplet = _platform_to_vcpkg_triplet(mq_platform)

    log_phase("CoOpt UI Build (Restructured)")
    logging.info(f"  Output: {output_dir}")
    logging.info(f"  Version: {args.version}")
    logging.info(f"  Platform: {mq_platform} ({mq_triplet})")

    try:
        if args.verify_only:
            phase_final_verification(
                output_dir=output_dir,
                version=args.version,
                build_e3=output_dir / "build_E3Source",
                build_mq=output_dir / "build_MacroQuestDefault",
                created_zips=None,
            )
            logging.info("")
            logging.info("Verification complete.")
            return 0

        paths = phase_sources(output_dir, repo_root)

        build_e3 = None
        if not args.skip_e3_build:
            build_e3 = phase_build_e3_source(
                output_dir, paths, repo_root, args.cmake_path,
                platform=mq_platform, vcpkg_triplet=mq_triplet,
            )
        else:
            log_phase("BUILD 1: E3 Source (skipped)")

        build_mq = None
        if not args.skip_mq_build:
            build_mq = phase_build_macroquest_default(
                output_dir, paths, repo_root, args.cmake_path,
                platform=mq_platform, vcpkg_triplet=mq_triplet,
            )
        else:
            log_phase("BUILD 2: MacroQuest Default (skipped)")

        _, _, created_zips = phase_staging_and_zips(output_dir, repo_root, args.version, build_e3, build_mq)
        phase_final_verification(output_dir, args.version, build_e3, build_mq, created_zips)

        logging.info("")
        logging.info("Build complete.")
        logging.info(f"  Source:     {output_dir / 'Source'}")
        if build_e3:
            logging.info(f"  E3 Source:  {build_e3}")
        if build_mq:
            logging.info(f"  MQ Default: {build_mq}")
        for z in output_dir.glob("*.zip"):
            logging.info(f"  ZIP: {z}")
        return 0

    except Exception as e:
        log_err(str(e))
        raise


if __name__ == "__main__":
    sys.exit(main())
