#Requires -Version 5.1
<#
.SYNOPSIS
    Build or rebuild the MQ2CoOptUI plugin against the MacroQuest EMU or Live clone.

.DESCRIPTION
    Handles two modes:
      update  - Fast: just run cmake --build --target MQ2CoOptUI (no reconfigure).
      rebuild - Full: apply all known gotcha patches to the MQ clone (idempotent),
                ensure the plugin symlink exists, reconfigure CMake, then build.

    All gotcha patches are idempotent -- safe to run on an already-patched clone.

.PARAMETER Target
    "emu"  - Build against MacroquestEMU\macroquest-clone  (Win32)
    "live" - Build against MacroquestLive\macroquest-clone (x64)
    "both" - Build against both clones.
    Omit to be prompted interactively.

.PARAMETER Mode
    "update"  - cmake --build --target MQ2CoOptUI only (fast, routine changes).
    "rebuild" - Apply all patches, reconfigure, then build (new clone or broken build).
    Omit to be prompted interactively.

.EXAMPLE
    .\scripts\rebuild-plugin.ps1
    .\scripts\rebuild-plugin.ps1 -Target emu -Mode update
    .\scripts\rebuild-plugin.ps1 -Target both -Mode rebuild
#>

[CmdletBinding()]
param(
    [ValidateSet('emu', 'live', 'both')]
    [string]$Target = '',

    [ValidateSet('update', 'rebuild')]
    [string]$Mode = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$CMAKE      = 'C:\MIS\CMake-3.30\bin\cmake.exe'
$E3_ROOT    = Split-Path -Parent $PSScriptRoot    # repo root (scripts/ is one level in)
$PLUGIN_SRC = Join-Path $E3_ROOT 'plugin\MQ2CoOptUI'

$CLONE_EMU  = 'C:\MIS\MacroquestEnvironments\MacroquestEMU\macroquest-clone'
$CLONE_LIVE = 'C:\MIS\MacroquestEnvironments\MacroquestLive\macroquest-clone'

$CLONES = @(
    @{ Key='emu';  Path=$CLONE_EMU;  Arch='EMU';  Platform='Win32' }
    @{ Key='live'; Path=$CLONE_LIVE; Arch='Live'; Platform='x64'   }
)

# ---------------------------------------------------------------------------
# Prompt helpers (PS 5.1 compatible -- no ternary)
# ---------------------------------------------------------------------------
function Prompt-Menu {
    param(
        [string]   $Title,
        [string[]] $Labels,
        [string[]] $Values
    )
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Labels.Length; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i+1), $Labels[$i])
    }
    $n = 0
    while ($n -lt 1 -or $n -gt $Labels.Length) {
        $raw = Read-Host 'Enter number'
        if ([int]::TryParse($raw, [ref]$null)) { $n = [int]$raw }
    }
    return $Values[$n - 1]
}

if (-not $Target) {
    $Target = Prompt-Menu -Title 'Which target?' `
        -Labels @('EMU  (Win32)', 'Live (x64)', 'Both') `
        -Values @('emu', 'live', 'both')
}

if (-not $Mode) {
    $Mode = Prompt-Menu -Title 'Which mode?' `
        -Labels @(
            'Update  -- fast cmake --build --target MQ2CoOptUI only',
            'Rebuild -- apply all patches, reconfigure, then build') `
        -Values @('update', 'rebuild')
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Step { param([string]$m) Write-Host ("`n==> " + $m) -ForegroundColor Cyan }
function OK   { param([string]$m) Write-Host ("    [OK]   " + $m) -ForegroundColor Green }
function Skip { param([string]$m) Write-Host ("    [SKIP] " + $m + " (already applied)") -ForegroundColor DarkGray }
function Warn { param([string]$m) Write-Host ("    [WARN] " + $m) -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Patch helpers (all idempotent)
# ---------------------------------------------------------------------------

# Replace $Old with $New (no-op if $Old not found = already patched).
function Patch-String {
    param([string]$File, [string]$Old, [string]$New, [string]$Label)
    if (-not (Test-Path $File)) { Warn ("File not found, skipping: " + $File); return }
    $c = [System.IO.File]::ReadAllText($File)
    if ($c.Contains($Old)) {
        [System.IO.File]::WriteAllText($File, $c.Replace($Old, $New))
        OK $Label
    } else {
        Skip $Label
    }
}

# Insert $Insert after the first occurrence of $Anchor, only if $Guard is absent.
function Patch-InsertAfter {
    param([string]$File, [string]$Anchor, [string]$Insert, [string]$Guard, [string]$Label)
    if (-not (Test-Path $File)) { Warn ("File not found, skipping: " + $File); return }
    $c = [System.IO.File]::ReadAllText($File)
    if ($c.Contains($Guard)) { Skip $Label; return }
    if (-not $c.Contains($Anchor)) { Warn ("Anchor not found in " + $File + " -- " + $Label); return }
    [System.IO.File]::WriteAllText($File, $c.Replace($Anchor, $Anchor + $Insert))
    OK $Label
}

# Prepend $Line to file if $Guard is absent.
function Patch-Prepend {
    param([string]$File, [string]$Line, [string]$Guard, [string]$Label)
    if (-not (Test-Path $File)) { Warn ("File not found, skipping: " + $File); return }
    $c = [System.IO.File]::ReadAllText($File)
    if ($c.Contains($Guard)) { Skip $Label; return }
    [System.IO.File]::WriteAllText($File, $Line + "`r`n" + $c)
    OK $Label
}

# ---------------------------------------------------------------------------
# Ensure plugin symlink
# ---------------------------------------------------------------------------
function Ensure-Symlink {
    param([string]$Clone)
    Step 'Plugin symlink'
    $pluginsDir = Join-Path $Clone 'plugins'
    $linkPath   = Join-Path $pluginsDir 'MQ2CoOptUI'

    if (-not (Test-Path $pluginsDir)) {
        New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
        OK 'Created plugins/ directory'
    }

    if (Test-Path $linkPath) {
        $item = Get-Item $linkPath -Force -ErrorAction SilentlyContinue
        if ($item.LinkType -eq 'SymbolicLink') {
            Skip ("Symlink already exists: " + $linkPath)
            return
        }
        Remove-Item $linkPath -Force -Recurse
    }

    New-Item -ItemType SymbolicLink -Path $linkPath -Target $PLUGIN_SRC | Out-Null
    OK ("Symlink created: " + $linkPath + " -> " + $PLUGIN_SRC)
}

# ---------------------------------------------------------------------------
# Apply all gotcha patches (idempotent).
# See .cursor/rules/mq-plugin-build-gotchas.mdc for full details on each fix.
# ---------------------------------------------------------------------------
function Apply-Patches {
    param([string]$Clone, [string]$Arch)

    Step ("Applying patches to " + $Arch + " clone")

    # --- #1: bzip2 cmake_minimum_required 3.0 -> 3.5 ---
    # The portfile copies this CMakeLists.txt into the build tree, so we patch
    # the port file. We also wipe the buildtrees cache so vcpkg re-extracts.
    $bzip2Cmake = $Clone + '\contrib\vcpkg\ports\bzip2\CMakeLists.txt'
    $bzip2Trees = $Clone + '\contrib\vcpkg\buildtrees\bzip2'
    $patched = $false
    if (Test-Path $bzip2Cmake) {
        $c = [System.IO.File]::ReadAllText($bzip2Cmake)
        if ($c.Contains('cmake_minimum_required(VERSION 3.0)')) {
            [System.IO.File]::WriteAllText($bzip2Cmake, $c.Replace('cmake_minimum_required(VERSION 3.0)', 'cmake_minimum_required(VERSION 3.5)'))
            OK '#1 bzip2: cmake_minimum_required 3.0 -> 3.5'
            $patched = $true
        } else {
            Skip '#1 bzip2: cmake_minimum_required already >= 3.5'
        }
    }
    # Clear bzip2 buildtrees so vcpkg re-extracts with the patched CMakeLists
    if ($patched -and (Test-Path $bzip2Trees)) {
        Remove-Item $bzip2Trees -Recurse -Force -ErrorAction SilentlyContinue
        OK '#1 bzip2: cleared buildtrees cache (forces fresh extract with patched CMakeLists)'
    }

    # --- #3: Loader portfile -- comment out vcpkg_install_empty_package() ---
    Patch-String `
        ($Clone + '\src\loader\portfile.cmake') `
        'vcpkg_install_empty_package()' `
        '# vcpkg_install_empty_package()  # removed: not available in this vcpkg' `
        '#3 loader portfile: comment out vcpkg_install_empty_package()'

    # --- #4: Crashpad duplicate target guard (check only -- complex block) ---
    $crashpadCfg = $Clone + '\contrib\vcpkg-ports\crashpad-backtrace\crashpadConfig.cmake.in'
    if (Test-Path $crashpadCfg) {
        $c = [System.IO.File]::ReadAllText($crashpadCfg)
        if ($c -match 'if\(NOT TARGET crashpad\)') {
            Skip '#4 crashpad: if(NOT TARGET crashpad) guard'
        } else {
            Warn ('#4 crashpad: guard missing in ' + $crashpadCfg)
            Warn '    Manually wrap add_library(crashpad INTERFACE) block in if(NOT TARGET crashpad)...endif()'
        }
    }

    # --- #5: curl-84 target name curl-84::curl-84 -> CURL-84::libcurl ---
    Patch-String `
        ($Clone + '\src\loader\CMakeLists.txt') `
        'curl-84::curl-84' `
        'CURL-84::libcurl' `
        '#5 loader: curl-84::curl-84 -> CURL-84::libcurl'

    # --- #6: PostOffice.h missing windows.h ---
    $foundPostOffice = $false
    foreach ($p in @(($Clone + '\src\loader\PostOffice.h'), ($Clone + '\src\main\PostOffice.h'))) {
        if (Test-Path $p) {
            Patch-Prepend $p '#include <windows.h>' 'windows.h' '#6 PostOffice.h: add windows.h include'
            $foundPostOffice = $true
            break
        }
    }
    if (-not $foundPostOffice) { Warn '#6 PostOffice.h not found in src/loader or src/main' }

    # --- #7: MQ2Lua C++20 override after target_Plugin_props ---
    $luaInsert  = "`r`nset_target_properties(MQ2Lua PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED YES)"
    $luaInsert += "`r`ntarget_compile_options(MQ2Lua PRIVATE `"/std:c++20`")"
    Patch-InsertAfter `
        ($Clone + '\src\plugins\lua\CMakeLists.txt') `
        'target_Plugin_props(MQ2Lua)' `
        $luaInsert `
        'CXX_STANDARD 20' `
        '#7 MQ2Lua: C++20 override after target_Plugin_props'

    # --- #8: imgui imanim sources ---
    $imguiCmake = $Clone + '\src\imgui\CMakeLists.txt'
    if (Test-Path $imguiCmake) {
        $c = [System.IO.File]::ReadAllText($imguiCmake)
        if ($c -match 'imanim/im_anim\.cpp') {
            Skip '#8 imgui: imanim sources already present'
        } else {
            # Insert sources before the closing ) of imgui_SOURCES, anchored on implot_items.cpp
            $srcAnchor  = '    "implot/implot_items.cpp"'
            $srcInsert  = "`r`n    `"imanim/im_anim.cpp`""
            $srcInsert += "`r`n    `"imanim/im_anim_demo.cpp`""
            $srcInsert += "`r`n    `"imanim/im_anim_doc.cpp`""
            $srcInsert += "`r`n    `"imanim/im_anim_usecase.cpp`""
            Patch-InsertAfter $imguiCmake $srcAnchor $srcInsert 'imanim/im_anim.cpp' '#8 imgui: add imanim sources'
            # Insert headers anchored on implot_internal.h
            $hdrAnchor  = '    "implot/implot_internal.h"'
            $hdrInsert  = "`r`n    `"imanim/im_anim.h`""
            $hdrInsert += "`r`n    `"imanim/im_anim_internal.h`""
            Patch-InsertAfter $imguiCmake $hdrAnchor $hdrInsert 'imanim/im_anim.h' '#8 imgui: add imanim headers'
        }
    }

    # --- #9: Loader link libs (d3d11, version, etc.) ---
    $loaderCmake = $Clone + '\src\loader\CMakeLists.txt'
    if (Test-Path $loaderCmake) {
        $c = [System.IO.File]::ReadAllText($loaderCmake)
        if ($c -match '\bd3d11\b') {
            Skip '#9 loader: system link libs (d3d11 etc.) already present'
        } else {
            $block  = "`r`n# System libs for D3D11, version API, etc. (gotcha #9)"
            $block += "`r`ntarget_link_libraries(MacroQuest PRIVATE"
            $block += "`r`n    d3d11 version Setupapi imm32 Ws2_32 Wldap32"
            $block += "`r`n)"
            [System.IO.File]::WriteAllText($loaderCmake, $c + $block)
            OK '#9 loader: added system link libs (d3d11, version, etc.)'
        }
    }

    # --- #10: MQ2CoOptUI capability headers -- sol forward decl (in E3 repo) ---
    foreach ($hdr in @('window.h','ipc.h','items.h','loot.h','ini.h')) {
        $hdrPath = Join-Path $PLUGIN_SRC ('capabilities\' + $hdr)
        if (Test-Path $hdrPath) {
            $c = [System.IO.File]::ReadAllText($hdrPath)
            if ($c -match 'namespace sol \{ class table;') {
                Patch-String $hdrPath `
                    'namespace sol { class table; }' `
                    '#include <sol/forward.hpp>' `
                    ('#10 capabilities/' + $hdr + ': replace sol forward decl')
            } else {
                Skip ('#10 capabilities/' + $hdr + ': sol forward decl already correct')
            }
        }
    }

    # --- #11: detect_custom_plugins argument quoting ---
    Patch-String `
        ($Clone + '\CMakeLists.txt') `
        'detect_custom_plugins(MQ_CUSTOM_PLUGIN_SUBDIRS ${MQ_CUSTOM_PLUGINS_FILE})' `
        'detect_custom_plugins(MQ_CUSTOM_PLUGIN_SUBDIRS "${MQ_CUSTOM_PLUGINS_FILE}")' `
        '#11 CMakeLists: detect_custom_plugins argument quoting'

    # --- #12: Network.cpp .contains() -> .find() ---
    Patch-String `
        ($Clone + '\src\routing\Network.cpp') `
        '!m_selfHosts.contains(address)' `
        '(m_selfHosts.find(address) == m_selfHosts.end())' `
        '#12 Network.cpp: .contains() -> .find()'
}

# ---------------------------------------------------------------------------
# Configure
# ---------------------------------------------------------------------------
function Configure-Clone {
    param([string]$Clone, [string]$Arch, [string]$Platform)

    Step ("CMake configure (" + $Arch + " / " + $Platform + ")")

    # Delete the build directory if it exists -- stale cmake 4.x artifacts cause
    # mixed-module-path errors when switching to cmake 3.30. Always start clean.
    $buildDir = $Clone + '\build\solution'
    if (Test-Path $buildDir) {
        Write-Host "    Removing stale build/solution directory..." -ForegroundColor DarkGray
        Remove-Item $buildDir -Recurse -Force -ErrorAction SilentlyContinue
        OK "Cleared build/solution"
    }

    $env:VCPKG_ROOT = $Clone + '\contrib\vcpkg'

    # Build each cmake argument as a plain string so PowerShell passes them
    # as individual arguments without splitting on '=' or '\'
    $buildDir    = $Clone + '\build\solution'
    $toolchain   = $Clone + '\contrib\vcpkg\scripts\buildsystems\vcpkg.cmake'
    $argToolchain = "-DCMAKE_TOOLCHAIN_FILE=$toolchain"

    & $CMAKE `
        -B $buildDir `
        -G 'Visual Studio 17 2022' `
        -A $Platform `
        $argToolchain `
        '-DMQ_BUILD_CUSTOM_PLUGINS=ON' `
        '-DMQ_BUILD_LAUNCHER=ON'

    if ($LASTEXITCODE -ne 0) {
        throw ("CMake configure failed for " + $Arch + " (exit " + $LASTEXITCODE + ")")
    }
    OK ("Configure succeeded (" + $Arch + ")")
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
function Build-Plugin {
    param([string]$Clone, [string]$Arch)

    Step ("cmake --build --target MQ2CoOptUI (" + $Arch + ")")

    $env:VCPKG_ROOT = $Clone + '\contrib\vcpkg'
    $buildDir = $Clone + '\build\solution'

    & $CMAKE --build $buildDir --config Release --target MQ2CoOptUI

    if ($LASTEXITCODE -ne 0) {
        $hint = if ($Mode -eq 'update') { " (Try: -Mode rebuild to reconfigure from scratch)" } else { "" }
        throw ("Build failed for " + $Arch + " (exit " + $LASTEXITCODE + ")" + $hint)
    }

    # Report DLL location
    $candidates = @(
        ($Clone + '\build\solution\bin\release\plugins\MQ2CoOptUI.dll'),
        ($Clone + '\build\solution\plugins\Release\MQ2CoOptUI.dll'),
        ($Clone + '\build\solution\bin\plugins\MQ2CoOptUI.dll')
    )
    $dll = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($dll) {
        $info = Get-Item $dll
        OK ("DLL: " + $dll + " (" + [math]::Round($info.Length/1KB, 1) + " KB, " + $info.LastWriteTime + ")")
    } else {
        Warn 'Build succeeded but DLL path not found in expected locations.'
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if (-not (Test-Path $CMAKE)) {
    Write-Error ("CMake 3.30 not found at: " + $CMAKE + "`nInstall CMake 3.30 there before running this script.")
    exit 1
}

# Gotcha #1: Put CMake 3.30 FIRST on PATH so vcpkg sub-invocations also use it,
# not whatever cmake.exe the system has installed (e.g. the VS-bundled 4.x).
$cmake330Bin = Split-Path -Parent $CMAKE
if ($env:Path -notlike ($cmake330Bin + '*')) {
    $env:Path = $cmake330Bin + ';' + $env:Path
}

$cmakeVer = (& $CMAKE --version 2>&1)[0].ToString().Trim()
Write-Host "`n=== MQ2CoOptUI Plugin Builder ===" -ForegroundColor White
Write-Host ("    CMake:  " + $cmakeVer) -ForegroundColor DarkGray
Write-Host ("    Mode:   " + $Mode) -ForegroundColor White
Write-Host ("    Target: " + $Target) -ForegroundColor White

$targets = $CLONES | Where-Object { $Target -eq 'both' -or $_.Key -eq $Target }

$anyFailed = $false
foreach ($t in $targets) {
    $clone    = $t.Path
    $arch     = $t.Arch
    $platform = $t.Platform

    Write-Host ("`n" + ('-' * 60)) -ForegroundColor DarkGray
    Write-Host ("  " + $arch + " (" + $platform + ") -- " + $clone) -ForegroundColor White
    Write-Host ('-' * 60) -ForegroundColor DarkGray

    if (-not (Test-Path $clone)) {
        Warn ($arch + " clone not found at " + $clone + " -- skipping.")
        $anyFailed = $true
        continue
    }

    try {
        # Always ensure bzip2 port is patched (CMake re-runs on stale stamp even in update mode)
        $bzip2Cmake = $clone + '\contrib\vcpkg\ports\bzip2\CMakeLists.txt'
        if (Test-Path $bzip2Cmake) {
            $bzip2Content = [System.IO.File]::ReadAllText($bzip2Cmake)
            if ($bzip2Content.Contains('cmake_minimum_required(VERSION 3.0)')) {
                [System.IO.File]::WriteAllText($bzip2Cmake, $bzip2Content.Replace('cmake_minimum_required(VERSION 3.0)', 'cmake_minimum_required(VERSION 3.5)'))
                $bzip2Trees = $clone + '\contrib\vcpkg\buildtrees\bzip2'
                if (Test-Path $bzip2Trees) { Remove-Item $bzip2Trees -Recurse -Force -ErrorAction SilentlyContinue }
                OK 'Pre-build: bzip2 CMakeLists patched (3.0 -> 3.5) + buildtrees cleared'
            }
        }

        if ($Mode -eq 'rebuild') {
            Apply-Patches $clone $arch
        }
        Ensure-Symlink $clone
        if ($Mode -eq 'rebuild') {
            Configure-Clone $clone $arch $platform
        }
        Build-Plugin $clone $arch
        Write-Host ("`n  [SUCCESS] " + $arch + " plugin built.") -ForegroundColor Green
    } catch {
        Write-Host ("`n  [FAILED]  " + $arch + ": " + $_.Exception.Message) -ForegroundColor Red
        $anyFailed = $true
    }
}

Write-Host ""
if ($anyFailed) {
    Write-Host 'One or more targets failed. See output above.' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'Done.' -ForegroundColor Green
}
