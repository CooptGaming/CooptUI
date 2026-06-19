# PyInstaller spec for CoOpt UI Patcher — single Windows .exe with bundled assets.
# Build: pyinstaller patcher.spec
# Run from patcher/ directory.

import os
import sys

block_cipher = None
assets_dir = 'assets'
datas = [(assets_dir, assets_dir)]  # bundle assets/ into the exe

# Resolve imports from this directory first so local updater.py is bundled (not any other updater on the path)
spec_dir = os.path.dirname(os.path.abspath(SPEC))

a = Analysis(
    ['patcher.py'],
    pathex=[spec_dir],
    binaries=[],
    datas=datas,
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

# Optional: add icon='assets/icon.ico' to EXE() when icon.ico is present
icon_path = None
if os.path.isfile(os.path.join(assets_dir, 'icon.ico')):
    icon_path = os.path.join(assets_dir, 'icon.ico')

# Stamp the exe with version metadata so it is not an anonymous binary. A blank publisher /
# description makes Windows SmartScreen and AV heuristics more suspicious; real ProductName /
# CompanyName / FileDescription also show in the file's Properties and the SmartScreen "More
# info" dialog. (This does NOT remove the "not commonly downloaded" reputation prompt — only a
# code-signing certificate does — but it makes the binary look legitimate, not anonymous.)
# Version is read from lua/coopui/version.lua so it stays in sync with releases.
import re as _re
import tempfile as _tempfile


def _package_version():
    vf = os.path.join(spec_dir, '..', 'lua', 'coopui', 'version.lua')
    try:
        with open(vf, encoding='utf-8') as f:
            m = _re.search(r'PACKAGE\s*=\s*"([^"]+)"', f.read())
        return m.group(1) if m else '0.0.0'
    except OSError:
        return '0.0.0'


_ver = _package_version()
_nums = (_re.findall(r'\d+', _ver) + ['0', '0', '0'])[:3]
_vtuple = (int(_nums[0]), int(_nums[1]), int(_nums[2]), 0)
version_file = os.path.join(_tempfile.gettempdir(), 'cooptui_patcher_version_info.txt')
with open(version_file, 'w', encoding='utf-8') as _vf:
    _vf.write(
        "VSVersionInfo(\n"
        f"  ffi=FixedFileInfo(filevers={_vtuple}, prodvers={_vtuple}, mask=0x3f, flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0, 0)),\n"
        "  kids=[\n"
        "    StringFileInfo([StringTable('040904B0', [\n"
        "      StringStruct('CompanyName', 'CoOpt UI - Perky Crew'),\n"
        "      StringStruct('FileDescription', 'CoOpt UI Patcher and Installer'),\n"
        f"      StringStruct('FileVersion', '{_ver}'),\n"
        "      StringStruct('InternalName', 'CoOptUIPatcher'),\n"
        "      StringStruct('OriginalFilename', 'CoOptUIPatcher.exe'),\n"
        "      StringStruct('ProductName', 'CoOpt UI'),\n"
        f"      StringStruct('ProductVersion', '{_ver}'),\n"
        "      StringStruct('LegalCopyright', 'CoOpt UI - Perky Crew'),\n"
        "    ])]),\n"
        "    VarFileInfo([VarStruct('Translation', [1033, 1200])]),\n"
        "  ]\n"
        ")\n"
    )

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='CoOptUIPatcher',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,  # UPX-packed PyInstaller exes trip more AV / SmartScreen heuristics
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon_path,
    version=version_file,
)
