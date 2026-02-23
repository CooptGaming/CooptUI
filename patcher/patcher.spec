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
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=icon_path,
)
