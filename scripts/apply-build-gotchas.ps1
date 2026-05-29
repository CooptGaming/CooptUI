# Apply known build fixes to an MQ clone so it builds cleanly with CMake 3.30 + VS 2022.
# Reference: .cursor/rules/mq-plugin-build-gotchas.mdc
# All patches are idempotent (safe to run multiple times).
#
# Usage: .\scripts\apply-build-gotchas.ps1 -MQClone "C:\MQ-EMU-Dev\macroquest"

param(
    [Parameter(Mandatory)][string]$MQClone,
    [string]$MQBuildDir = "",
    [switch]$ShowSkipped
)

$ErrorActionPreference = "Stop"
$applied = 0
$skipped = 0

function Write-Fix {
    param([string]$Id, [string]$Message)
    Write-Host "  [FIX $Id] $Message" -ForegroundColor Green
    $script:applied++
}

function Write-Skip {
    param([string]$Id, [string]$Message)
    if ($ShowSkipped) { Write-Host "  [SKIP $Id] $Message" -ForegroundColor DarkGray }
    $script:skipped++
}

function Replace-InFile {
    param([string]$Path, [string]$Old, [string]$New, [string]$FixId)
    if (-not (Test-Path $Path)) {
        Write-Warning "  [$FixId] File not found: $Path"
        return $false
    }
    $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) { return $false }
    if ($content.Contains($New)) {
        Write-Skip $FixId "Already applied in $(Split-Path $Path -Leaf)"
        return $false
    }
    if (-not $content.Contains($Old)) {
        Write-Skip $FixId "Pattern not found in $(Split-Path $Path -Leaf) (may already be fixed or file changed)"
        return $false
    }
    $content = $content.Replace($Old, $New)
    Set-Content $Path $content -NoNewline
    return $true
}

if (-not (Test-Path $MQClone)) {
    Write-Error "MQ clone not found at: $MQClone"
}

Write-Host "Applying build gotchas to: $MQClone" -ForegroundColor Cyan

# --- #1 (Fix B): bzip2 cmake_minimum_required VERSION 3.0 -> 3.5 ---
$bzip2Cmake = Join-Path $MQClone "contrib\vcpkg\ports\bzip2\CMakeLists.txt"
if (Replace-InFile $bzip2Cmake "VERSION 3.0" "VERSION 3.5" "1") {
    Remove-Item (Join-Path $MQClone "contrib\vcpkg\buildtrees\bzip2") -Recurse -Force -ErrorAction SilentlyContinue
    Write-Fix "1" "bzip2 cmake_minimum_required 3.0 -> 3.5"
}

# --- #3: Loader portfile — remove vcpkg_install_empty_package() ---
$loaderPortfile = Join-Path $MQClone "src\loader\portfile.cmake"
if (Test-Path $loaderPortfile) {
    $content = Get-Content $loaderPortfile -Raw
    if ($content -match "vcpkg_install_empty_package\(\)") {
        $content = $content -replace "vcpkg_install_empty_package\(\)\r?\n?", ""
        Set-Content $loaderPortfile $content -NoNewline
        Write-Fix "3" "Removed vcpkg_install_empty_package() from loader portfile"
    } else {
        Write-Skip "3" "vcpkg_install_empty_package already removed"
    }
} else {
    Write-Skip "3" "Loader portfile not found"
}

# --- #4b: Crashpad duplicate target guard — patch in-tree port + ALL cached registry copies ---
# The macroquest vcpkg-configuration.json uses the macroquest/vcpkg git registry. vcpkg
# fetches port files into %LOCALAPPDATA%\vcpkg\registries\git-trees\<commit>\ and uses THOSE
# during port builds — not the contrib/vcpkg/ports/crashpad/ files in the clone. Patching only
# the in-tree copy is invisible to vcpkg's actual builds. Patch both:
#   (1) contrib/vcpkg/ports/crashpad/crashpadConfig.cmake.in   (in-tree, may be authoritative for some flows)
#   (2) %LOCALAPPDATA%\vcpkg\registries\git-trees\*\crashpadConfig.cmake.in  (the actual source vcpkg uses)
# Add `if(NOT TARGET crashpad)` ... `endif()` around `add_library(crashpad INTERFACE)`.
function Patch-CrashpadConfigIn {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -notmatch 'add_library\(crashpad INTERFACE\)') { return $false }
    $changed = $false
    # 1. Wrap add_library(crashpad INTERFACE) in `if(NOT TARGET crashpad)` ... `endif()` so
    #    re-loading the config (e.g. via multiple find_package calls) doesn't double-create the target.
    if ($content -notmatch 'if\s*\(\s*NOT\s+TARGET\s+crashpad\s*\)') {
        $content = $content -replace 'add_library\(crashpad INTERFACE\)', "if(NOT TARGET crashpad)`r`nadd_library(crashpad INTERFACE)"
        $content = $content.TrimEnd() + "`r`nendif()`r`n"
        $changed = $true
    }
    # 2. Restrict find_library to release lib dir only. Default `find_library(_LIB ${LIB_NAME})`
    #    with no paths searches both release and `debug/lib/` and may pick the DEBUG variant
    #    (built with `_DEBUG` defined) — that bakes /DEFAULTLIB:libucrtd.lib references into
    #    the lib's directives, causing LNK2001 __CrtDbgReport at link time when our Release
    #    build doesn't link the debug runtime. Force `PATHS "${_IMPORT_PREFIX}/lib" NO_DEFAULT_PATH`.
    if ($content -match 'find_library\(_LIB \$\{LIB_NAME\}\)' -and
        $content -notmatch 'PATHS "\$\{_IMPORT_PREFIX\}/lib" NO_DEFAULT_PATH') {
        $content = $content -replace 'find_library\(_LIB \$\{LIB_NAME\}\)', 'find_library(_LIB ${LIB_NAME} PATHS "${_IMPORT_PREFIX}/lib" NO_DEFAULT_PATH)'
        $changed = $true
    }
    if ($changed) {
        [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
    }
    return $changed
}
$inTreeIn = Join-Path $MQClone 'contrib\vcpkg\ports\crashpad\crashpadConfig.cmake.in'
$inTreeChanged = Patch-CrashpadConfigIn -Path $inTreeIn
if ($inTreeChanged) { Write-Fix "4a" "Wrapped crashpad target guard in in-tree crashpadConfig.cmake.in" }
# Find every cached registry copy (vcpkg's git-trees can have multiple if the registry has been
# updated; patch them all so any cache hit produces a guarded config).
$registryRoot = "$env:LOCALAPPDATA\vcpkg\registries\git-trees"
$cachedPatched = 0
if (Test-Path $registryRoot) {
    $cached = Get-ChildItem $registryRoot -Filter 'crashpadConfig.cmake.in' -Recurse -EA SilentlyContinue
    foreach ($f in $cached) {
        if (Patch-CrashpadConfigIn -Path $f.FullName) { $cachedPatched++ }
    }
}
if ($cachedPatched -gt 0) {
    Write-Fix "4b" "Wrapped crashpad target guard in $cachedPatched cached registry .in file(s)"
} elseif (-not $inTreeChanged) {
    Write-Skip "4" "All crashpadConfig.cmake.in files already have crashpad target guard"
}
# Old-style fix #4 (left for completeness if a future port reverts to inline config)
$crashpadConfig = Join-Path $MQClone "contrib\vcpkg-ports\crashpad-backtrace\crashpadConfig.cmake.in"
if (Test-Path $crashpadConfig) {
    $content = Get-Content $crashpadConfig -Raw
    if ($content -match "add_library\(crashpad" -and $content -notmatch "if\s*\(\s*NOT\s+TARGET\s+crashpad\s*\)") {
        $content = $content -replace "(add_library\(crashpad\s+INTERFACE\))", "if(NOT TARGET crashpad)`n`$1"
        $lines = $content -split "`n"
        $result = @()
        $inBlock = $false
        $depth = 0
        foreach ($line in $lines) {
            $result += $line
            if ($line -match "if\(NOT TARGET crashpad\)") { $inBlock = $true; $depth = 1 }
            elseif ($inBlock) {
                if ($line -match "target_include_directories\(crashpad") { $depth-- }
                if ($depth -le 0 -and $line.Trim() -ne "" -and $line -notmatch "^\s*#") {
                    if ($line -match "target_include_directories|target_link_libraries") {
                        $result += "endif()"
                        $inBlock = $false
                    }
                }
            }
        }
        if ($inBlock) { $result += "endif()" }
        Set-Content $crashpadConfig ($result -join "`n") -NoNewline
        Write-Fix "4" "Wrapped crashpad target in if(NOT TARGET) guard"
    } else {
        Write-Skip "4" "Crashpad guard already present or pattern changed"
    }
} else {
    Write-Skip "4" "crashpadConfig.cmake.in not found"
}

# --- #5: curl-84 target name ---
$loaderCMake = Join-Path $MQClone "src\loader\CMakeLists.txt"
if (Replace-InFile $loaderCMake "curl-84::curl-84" "CURL-84::libcurl" "5") {
    Write-Fix "5" "curl-84::curl-84 -> CURL-84::libcurl in loader CMakeLists"
}

# --- #6: PostOffice.h missing <windows.h> (both main and loader copies) ---
foreach ($subdir in @("src\main", "src\loader")) {
    $postOfficeH = Join-Path $MQClone "$subdir\PostOffice.h"
    if (Test-Path $postOfficeH) {
        $content = Get-Content $postOfficeH -Raw
        if ($content -match "HWND" -and $content -notmatch "#include\s*<[Ww]indows\.h>") {
            $content = $content -replace "(#pragma once)", "`$1`n#include <Windows.h>"
            Set-Content $postOfficeH $content -NoNewline
            Write-Fix "6" "Added #include <Windows.h> to $subdir\PostOffice.h"
        } else {
            Write-Skip "6" "$subdir\PostOffice.h already includes Windows.h or no HWND usage"
        }
    } else {
        Write-Skip "6" "$subdir\PostOffice.h not found"
    }
}

# --- #7: MQ2Lua C++20 ---
$mq2LuaCMake = Join-Path $MQClone "src\plugins\lua\CMakeLists.txt"
if (Test-Path $mq2LuaCMake) {
    $content = Get-Content $mq2LuaCMake -Raw
    if ($content -notmatch "CXX_STANDARD 20") {
        $content = $content -replace "(target_Plugin_props\(MQ2Lua\))", "`$1`nset_target_properties(MQ2Lua PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED YES)`ntarget_compile_options(MQ2Lua PRIVATE `"/std:c++20`")"
        Set-Content $mq2LuaCMake $content -NoNewline
        Write-Fix "7" "Added C++20 to MQ2Lua CMakeLists"
    } else {
        Write-Skip "7" "MQ2Lua already has C++20"
    }
} else {
    Write-Skip "7" "MQ2Lua CMakeLists not found"
}

# --- #8: imgui imanim source files ---
$imguiCMake = Join-Path $MQClone "src\imgui\CMakeLists.txt"
if (Test-Path $imguiCMake) {
    $content = Get-Content $imguiCMake -Raw
    if ($content -notmatch "imanim/im_anim\.cpp") {
        $imanimSources = @"

    imanim/im_anim.cpp
    imanim/im_anim_demo.cpp
    imanim/im_anim_doc.cpp
    imanim/im_anim_usecase.cpp
"@
        $imanimHeaders = @"

    imanim/im_anim.h
    imanim/im_anim_internal.h
"@
        if ($content -match "(set\(imgui_SOURCES[^)]+)(\))") {
            $content = $content -replace "(set\(imgui_SOURCES[^)]+)(\))", "`$1$imanimSources`n`$2"
        }
        if ($content -match "(set\(imgui_HEADERS[^)]+)(\))") {
            $content = $content -replace "(set\(imgui_HEADERS[^)]+)(\))", "`$1$imanimHeaders`n`$2"
        }
        Set-Content $imguiCMake $content -NoNewline
        Write-Fix "8" "Added imanim source/header files to imgui CMakeLists"
    } else {
        Write-Skip "8" "imgui already has imanim sources"
    }
} else {
    Write-Skip "8" "imgui CMakeLists not found"
}

# --- #18: eqlib emu — GameFace.h missing (live-only header) ---
$eqlibCMake = Join-Path $MQClone "src\eqlib\CMakeLists.txt"
$gameFaceH = Join-Path $MQClone "src\eqlib\include\eqlib\game\GameFace.h"
if ((Test-Path $eqlibCMake) -and -not (Test-Path $gameFaceH)) {
    $content = Get-Content $eqlibCMake -Raw
    if ($content -match '"include/eqlib/game/GameFace\.h"') {
        $content = $content -replace '\s*"include/eqlib/game/GameFace\.h"\r?\n', "`n"
        Set-Content $eqlibCMake $content -NoNewline
        Write-Fix "18" "Removed GameFace.h from eqlib (file missing on emu branch)"
    } else {
        Write-Skip "18" "GameFace.h line already removed or not present"
    }
} else {
    Write-Skip "18" "eqlib CMakeLists not found or GameFace.h exists (main branch)"
}

# --- #18b: eqlib emu — eqstd/mutex.h missing ---
$eqstdMutexH = Join-Path $MQClone "src\eqlib\include\eqstd\mutex.h"
if ((Test-Path $eqlibCMake) -and -not (Test-Path $eqstdMutexH)) {
    $content = Get-Content $eqlibCMake -Raw
    if ($content -match '"include/eqstd/mutex\.h"') {
        $content = $content -replace '\s*"include/eqstd/mutex\.h"\r?\n', "`n"
        Set-Content $eqlibCMake $content -NoNewline
        Write-Fix "18b" "Removed eqstd/mutex.h from eqlib (file missing on emu branch)"
    } else {
        Write-Skip "18b" "eqstd/mutex.h line already removed or not present"
    }
} else {
    Write-Skip "18b" "eqlib CMakeLists not found or eqstd/mutex.h exists"
}

# --- #20: Achievements.h missing eqstd/unordered_map include ---
$achievementsH = Join-Path $MQClone "src\eqlib\include\eqlib\game\Achievements.h"
if (Test-Path $achievementsH) {
    $content = Get-Content $achievementsH -Raw
    if ($content -match "eqstd::unordered_map" -and $content -notmatch "eqstd/unordered_map\.h") {
        $content = $content -replace '(#include\s+"eqlib/game/Types\.h")', "`$1`n#include `"eqstd/unordered_map.h`""
        Set-Content $achievementsH $content -NoNewline
        Write-Fix "20" "Added missing #include <eqstd/unordered_map.h> to Achievements.h"
    } else {
        Write-Skip "20" "Achievements.h include already present or not needed"
    }
} else {
    Write-Skip "20" "Achievements.h not found"
}

# --- #9: Loader linker libraries ---
if (Test-Path $loaderCMake) {
    $content = Get-Content $loaderCMake -Raw
    if ($content -notmatch "target_link_libraries\((loader|MacroQuest)\s+PRIVATE\s+d3d11") {
        $content += "`ntarget_link_libraries(MacroQuest PRIVATE d3d11 version Setupapi imm32 Ws2_32 Wldap32)`n"
        Set-Content $loaderCMake $content -NoNewline
        Write-Fix "9" "Added missing Windows link libraries to loader"
    } else {
        Write-Skip "9" "Loader already has link libraries"
    }
} else {
    Write-Skip "9" "Loader CMakeLists not found"
}

# --- #11: detect_custom_plugins quote fix ---
$rootCMake = Join-Path $MQClone "CMakeLists.txt"
if (Replace-InFile $rootCMake 'detect_custom_plugins(MQ_CUSTOM_PLUGIN_SUBDIRS ${MQ_CUSTOM_PLUGINS_FILE})' 'detect_custom_plugins(MQ_CUSTOM_PLUGIN_SUBDIRS "${MQ_CUSTOM_PLUGINS_FILE}")' "11") {
    Write-Fix "11" "Quoted detect_custom_plugins second argument"
}

# --- #12: Network.cpp .contains() -> .find() ---
$networkCpp = Join-Path $MQClone "src\routing\Network.cpp"
if (Replace-InFile $networkCpp '!m_selfHosts.contains(address)' 'm_selfHosts.find(address) == m_selfHosts.end()' "12") {
    Write-Fix "12" "Replaced .contains() with .find() in Network.cpp"
}

# --- #16: MQ2Mono std::array include ---
$mq2MonoSharedH = Join-Path $MQClone "plugins\MQ2Mono\MQ2MonoShared.h"
if (Test-Path $mq2MonoSharedH) {
    $content = Get-Content $mq2MonoSharedH -Raw
    if ($content -notmatch "#include\s*<array>") {
        # Insert after first #include (PS5.1-safe; -replace with 3rd arg is PS6+ only).
        $firstInclude = [regex]::Match($content, '#include\s*<[^>]+>')
        if ($firstInclude.Success) {
            $content = $content.Insert($firstInclude.Index + $firstInclude.Length, "`n#include <array>")
        }
        Set-Content $mq2MonoSharedH $content -NoNewline
        Write-Fix "16a" "Added #include <array> to MQ2MonoShared.h"
    } else {
        Write-Skip "16a" "MQ2MonoShared.h already includes <array>"
    }
} else {
    Write-Skip "16a" "MQ2MonoShared.h not found (MQ2Mono not cloned yet?)"
}

# --- #16: MQ2Mono labelPtr -> labelStr fix ---
$mq2MonoImGui = Join-Path $MQClone "plugins\MQ2Mono\MQ2MonoImGui.cpp"
if (Test-Path $mq2MonoImGui) {
    $content = Get-Content $mq2MonoImGui -Raw
    if ($content -match "find\(labelPtr\)" -and $content -notmatch "find\(labelStr\)") {
        $content = $content -replace "find\(labelPtr\)", "find(labelStr)"
        Set-Content $mq2MonoImGui $content -NoNewline
        Write-Fix "16b" "Fixed labelPtr -> labelStr in MQ2MonoImGui.cpp"
    } else {
        Write-Skip "16b" "MQ2MonoImGui labelPtr fix already applied or not needed"
    }
} else {
    Write-Skip "16b" "MQ2MonoImGui.cpp not found (MQ2Mono not cloned yet?)"
}

# --- #19b: MQ2Mono ColorPicker4 — re-find iterator after insert (fixes use of end() iterator) ---
$mq2MonoImGuiCpp = Join-Path $MQClone "plugins\MQ2Mono\MQ2MonoImGui.cpp"
if (Test-Path $mq2MonoImGuiCpp) {
    $content = Get-Content $mq2MonoImGuiCpp -Raw
    $pat1 = 'm_IMGUI_InputColorValues\[labelStr\]=\{[^}]+\}\s*;\s*\r?\n\s*\r?\n\s*\}\s*\r?\n\s*return ImGui::ColorPicker4'
    $rep1 = "m_IMGUI_InputColorValues[labelStr]={static_cast<float>(r)/255,static_cast<float>(g)/255,static_cast<float>(b)/255,static_cast<float>(a)/255 };`n		it = domainInfo.m_IMGUI_InputColorValues.find(labelStr);`n	}`n	return ImGui::ColorPicker4"
    if ($content -match $pat1 -and $content -notmatch "it = domainInfo.m_IMGUI_InputColorValues.find\(labelStr\)") {
        $content = $content -replace $pat1, $rep1
        $pat2 = 'm_IMGUI_InputColorValues\[labelStr\] = \{ r,g,b,a \}\s*;\s*\r?\n\s*\}\s*\r?\n\s*return ImGui::ColorPicker4'
        $rep2 = "m_IMGUI_InputColorValues[labelStr] = { r, g, b, a };`n		it = domainInfo.m_IMGUI_InputColorValues.find(labelStr);`n	}`n	return ImGui::ColorPicker4"
        $content = $content -replace $pat2, $rep2
        Set-Content $mq2MonoImGuiCpp $content -NoNewline
        Write-Fix "19b" "MQ2Mono ColorPicker4: re-find iterator after insert"
    } else {
        Write-Skip "19b" "MQ2MonoImGui ColorPicker4 iterator fix already applied or pattern not found"
    }
} else {
    Write-Skip "19b" "MQ2MonoImGui.cpp not found"
}

# --- #19: MQ2Mono CMake — Mono SDK include path (vcxproj conversion omits it) ---
# Headers live in source at plugins/MQ2Mono/Mono/include/mono-2.0 (RekkasGit/MQ2Mono repo).
# CMakeLists.txt may be in source or generated in build tree; use CMAKE_SOURCE_DIR so path works for both.
$monoIncludeDir = Join-Path $MQClone "plugins\MQ2Mono\Mono\include\mono-2.0"
$monoIncludeLine = "target_include_directories(MQ2Mono PRIVATE `"`${CMAKE_SOURCE_DIR}/plugins/MQ2Mono/Mono/include/mono-2.0`")"
$fix19Applied = $false
if (Test-Path $monoIncludeDir) {
    $candidates = @(Join-Path $MQClone "plugins\MQ2Mono\CMakeLists.txt")
    if ($MQBuildDir) {
        $candidates += Join-Path $MQBuildDir "plugins\MQ2Mono\CMakeLists.txt"
    }
    foreach ($mq2MonoCMake in $candidates) {
        if (-not (Test-Path $mq2MonoCMake)) { continue }
        $content = Get-Content $mq2MonoCMake -Raw
        if ($content -match "Mono/include/mono-2.0") {
            Write-Skip "19" "MQ2Mono already has Mono include path"
            $fix19Applied = $true
            break
        }
        if ($content -match "target_Plugin_props\(MQ2Mono\)") {
            $content = $content -replace "(target_Plugin_props\(MQ2Mono\))", "`$1`n`n# Mono SDK headers (RekkasGit/MQ2Mono)`n$monoIncludeLine"
            Set-Content $mq2MonoCMake $content -NoNewline
            Write-Fix "19" "Added Mono include path to MQ2Mono CMakeLists.txt"
            $fix19Applied = $true
            break
        }
    }
    if (-not $fix19Applied) {
        Write-Skip "19" "MQ2Mono CMakeLists or target_Plugin_props(MQ2Mono) not found (run gotchas after cmake configure with -MQBuildDir for full build)"
    }
} else {
    Write-Skip "19" "MQ2Mono Mono/include/mono-2.0 not found in clone (ensure RekkasGit/MQ2Mono cloned with Mono tree)"
}

# --- #19c: MQ2Mono generated vcxproj — add Mono include when CMake-generated project omits it (full build) ---
if ($MQBuildDir -and (Test-Path $monoIncludeDir)) {
    $mq2MonoVcxproj = Join-Path $MQBuildDir "plugins\MQ2Mono\MQ2Mono.vcxproj"
    if (Test-Path $mq2MonoVcxproj) {
        $content = Get-Content $mq2MonoVcxproj -Raw
        $monoIncludeEscaped = $monoIncludeDir -replace '\\', '\\'
        if ($content -notmatch [regex]::Escape($monoIncludeEscaped) -and $content -match '<AdditionalIncludeDirectories>([^<]*)</AdditionalIncludeDirectories>') {
            $content = $content -replace '(<AdditionalIncludeDirectories>)([^<]*)(</AdditionalIncludeDirectories>)', "`$1`$2;$monoIncludeDir`$3"
            Set-Content $mq2MonoVcxproj $content -NoNewline
            Write-Fix "19c" "Added Mono include path to generated MQ2Mono.vcxproj"
        } elseif ($content -match [regex]::Escape($monoIncludeDir)) {
            Write-Skip "19c" "MQ2Mono.vcxproj already has Mono include path"
        } else {
            Write-Skip "19c" "MQ2Mono.vcxproj AdditionalIncludeDirectories pattern not found"
        }
    } else {
        Write-Skip "19c" "Generated MQ2Mono.vcxproj not found (run with -MQBuildDir after cmake configure)"
    }
}

# --- #15: Remove stale build/solution if it exists (from cmake 4.x) ---
$staleBuild = Join-Path $MQClone "build\solution"
if (Test-Path $staleBuild) {
    $staleMarkers = @(
        (Join-Path $staleBuild "CMakeCache.txt")
    )
    foreach ($marker in $staleMarkers) {
        if (Test-Path $marker) {
            $cache = Get-Content $marker -Raw -ErrorAction SilentlyContinue
            if ($cache -match "CMAKE_COMMAND.*cmake.*4\." -or $cache -match "CMAKE_VERSION.*4\.") {
                Remove-Item $staleBuild -Recurse -Force
                Write-Fix "15" "Removed stale build/solution from cmake 4.x"
                break
            }
        }
    }
    if (Test-Path $staleBuild) {
        Write-Skip "15" "build/solution exists but appears to be from cmake 3.x"
    }
} else {
    Write-Skip "15" "No build/solution directory"
}

# --- #21: src/main/CMakeLists.txt references ImGuiAlphaMask.h that isn't tracked at HEAD ---
# Upstream regression: a recent commit deleted the INTERNAL src/main/ImGuiAlphaMask.h header
# but left the reference in CMakeLists.txt. CMake errors at configure time with
# "Cannot find source file: ImGuiAlphaMask.h" because the file no longer exists on disk.
#
# IMPORTANT: only drop the .h reference. KEEP ImGuiAlphaMask.cpp — it doesn't include the
# deleted internal header (it includes the public include/mq/imgui/AlphaMask.h which still
# exists), and it defines mq::imgui::CreateMaskLayer / BeginMaskedDraw / EndMaskedDraw etc.
# that MQ2Lua imports from MQ2Main.dll. Earlier versions of this patch dropped the .cpp too,
# which compiled MQ2Main fine but left MQ2Lua with LNK2019 unresolved externals.
$mainCMake = Join-Path $MQClone "src\main\CMakeLists.txt"
$alphaMaskH = Join-Path $MQClone "src\main\ImGuiAlphaMask.h"
$alphaMaskCpp = Join-Path $MQClone "src\main\ImGuiAlphaMask.cpp"
if ((Test-Path $mainCMake) -and -not (Test-Path $alphaMaskH) -and (Test-Path $alphaMaskCpp)) {
    $content = Get-Content $mainCMake -Raw
    $orig = $content
    # Drop ONLY the .h listing. If a previous patch run dropped the .cpp too, restore it by
    # re-inserting the .cpp line right after the (now-removed) .h would have been.
    $content = $content -replace '(?m)^\s*"ImGuiAlphaMask\.h"\s*\r?\n', ''
    if ($content -notmatch '"ImGuiAlphaMask\.cpp"') {
        # Earlier patch dropped the .cpp incorrectly — restore it. Insert alphabetically
        # before ImGuiBackendDX11.cpp (the next ImGui*.cpp in the SOURCES list).
        if ($content -match '(?m)(^(\s*)"ImGuiBackendDX11\.cpp"\s*\r?\n)') {
            $anchor = $matches[1]
            $indent = $matches[2]
            $content = $content -replace [regex]::Escape($anchor), ("$indent`"ImGuiAlphaMask.cpp`"`r`n" + $anchor)
        }
    }
    if ($content -ne $orig) {
        Set-Content $mainCMake $content -NoNewline
        Write-Fix "21" "Dropped ImGuiAlphaMask.h listing (kept .cpp — defines MQ2Lua-imported symbols)"
    } else {
        Write-Skip "21" "src/main/CMakeLists.txt already correctly patched"
    }
} elseif (Test-Path $alphaMaskH) {
    Write-Skip "21" "ImGuiAlphaMask.h is present (upstream restored it); no patch needed"
} elseif (-not (Test-Path $alphaMaskCpp)) {
    Write-Skip "21" "ImGuiAlphaMask.cpp also missing — upstream may have removed the feature entirely"
} else {
    Write-Skip "21" "src/main/CMakeLists.txt not found"
}

# --- #22: src/loader/CMakeLists.txt — find_package(curl) -> find_package(CURL) on master ---
# Upstream regression on master: vcpkg's curl exposes targets via the standard FindCURL module,
# so find_package(curl REQUIRED) doesn't produce a curl::curl target. Use the standard CMake
# CURL::libcurl target instead. (Existing fix #5 handles the curl-84 variant on the emu branch.)
if (Test-Path $loaderCMake) {
    $content = Get-Content $loaderCMake -Raw
    $orig = $content
    $content = $content -replace 'find_package\(curl\s+REQUIRED\)', 'find_package(CURL REQUIRED)'
    # Replace bare curl::curl, but not curl-84::curl-84 (handled by #5)
    $content = $content -replace '(?<!-84::)\bcurl::curl\b', 'CURL::libcurl'
    if ($content -ne $orig) {
        Set-Content $loaderCMake $content -NoNewline
        Write-Fix "22" "Replaced find_package(curl)/curl::curl with CURL/CURL::libcurl in loader (master branch)"
    } else {
        Write-Skip "22" "loader CMakeLists already on CURL/CURL::libcurl (or curl-84 variant handled by #5)"
    }
} else {
    Write-Skip "22" "Loader CMakeLists not found"
}

# --- #23: src/main/emu/EmuExtensions.cpp — neuter FindValidEffect (CEffect class is closed-source) ---
# Upstream regression in commit 1860aada (2026-04-18, "emu-rof2: Implement fix for D3DXEffects::CEffect::FindValue crash").
# The function dereferences eqlib::CEffect's pD3DXEffect member, but CEffect has NO full class
# definition anywhere in the public eqlib source — only forward declarations in GraphicsEngine.h
# (line 267) and Render.h (line 31). The author presumably has a private/closed header.
# Without it, FindValidEffect() can't compile. Replace the body with `return nullptr;` so MQ2Main
# builds. Cost: the rof2-specific D3DXEffects::CEffect::FindValue crash workaround is disabled —
# fine for non-rof2 EMU servers; the macro hook remains active and harmless when no effect found.
$emuExtCpp = Join-Path $MQClone "src\main\emu\EmuExtensions.cpp"
if (Test-Path $emuExtCpp) {
    $content = Get-Content $emuExtCpp -Raw
    # Match the function body if it still has the CEffect-using loop
    $pat = '(?ms)(static ID3DXEffect\* FindValidEffect\(\)\s*\{\s*)' +
           '(if\s*\(!pGraphicsEngine\s*\|\|\s*!pGraphicsEngine->pRender\)\s*return nullptr;\s*\r?\n)' +
           '(\s*CRender\* pRender = pGraphicsEngine->pRender;[\s\S]*?return nullptr;\s*\r?\n\})'
    if ($content -match $pat) {
        $rep = "`$1`$2`r`n`t// CoOpt UI patch: CEffect class definition is not available in public eqlib source; original" +
               "`r`n`t// CEffect-walking loop disabled. Effective on non-rof2 EMU servers where this hook isn't critical." +
               "`r`n`treturn nullptr;`r`n}"
        $content = $content -replace $pat, $rep
        Set-Content $emuExtCpp $content -NoNewline
        Write-Fix "23" "Neutered FindValidEffect in EmuExtensions.cpp (closed-source CEffect)"
    } elseif ($content -match 'CoOpt UI patch: CEffect class definition is not available') {
        Write-Skip "23" "FindValidEffect already neutered"
    } else {
        Write-Skip "23" "FindValidEffect pattern not found (upstream may have restored CEffect definition)"
    }
} else {
    Write-Skip "23" "EmuExtensions.cpp not found"
}

# --- #24: src/main/MQ2DeveloperTools.cpp — replace std::erase (C++20) with C++17 erase-remove idiom ---
# Upstream regression in commit d884ffd88 (2026-03-28). MQ2Main.vcxproj is generated with
# LanguageStandard=stdcpp17 even though root CMakeLists sets CXX_STANDARD 20 — there's a
# target_Common_props() helper that pins stdcpp17. std::erase free function is C++20 only,
# so the call fails to compile. The erase-remove idiom is C++17-compatible and equivalent.
$devTools = Join-Path $MQClone "src\main\MQ2DeveloperTools.cpp"
if (Test-Path $devTools) {
    $content = Get-Content $devTools -Raw
    if ($content -match 'std::erase\s*\(\s*s_imguiBaseWindows\s*,\s*this\s*\)') {
        $content = $content -replace 'std::erase\s*\(\s*s_imguiBaseWindows\s*,\s*this\s*\)',
            's_imguiBaseWindows.erase(std::remove(s_imguiBaseWindows.begin(), s_imguiBaseWindows.end(), this), s_imguiBaseWindows.end())'
        Set-Content $devTools $content -NoNewline
        Write-Fix "24" "Replaced std::erase with C++17 erase-remove idiom in MQ2DeveloperTools.cpp"
    } else {
        Write-Skip "24" "MQ2DeveloperTools.cpp already on erase-remove idiom (or pattern moved)"
    }
} else {
    Write-Skip "24" "MQ2DeveloperTools.cpp not found"
}

# --- #25: vcpkg_mq.txt — add abseil dep where crashpad is used (loader + main) ---
# crashpad's base.lib has /DEFAULTLIB:absl_base.lib baked into its object directives, but vcpkg
# doesn't pull abseil transitively. Adding abseil to the loader/main vcpkg_mq.txt files installs
# absl_base.lib so the linker resolves the /DEFAULTLIB request.
#
# Note: src/<project>/vcpkg.json is auto-REGENERATED on every cmake configure from
# <project>/vcpkg_mq.txt (see cmake/vcpkg_manifest.cmake parse_vcpkg_mq_files). Editing the
# .json directly is futile — it gets overwritten. The .txt is the source of truth.
function Add-VcpkgMqDep {
    param([string]$MqTxtPath, [string]$DepName, [string]$FixId)
    if (-not (Test-Path $MqTxtPath)) {
        Write-Skip $FixId "$MqTxtPath not found"
        return $false
    }
    # Read raw bytes/text and split on any line ending. Then check for the dep AND any corruption
    # (e.g. previous Add-Content glued the dep onto a prior line because the file had no trailing
    # newline). Rewrite cleanly with platform-appropriate line endings.
    $raw = [System.IO.File]::ReadAllText($MqTxtPath)
    $lines = @($raw -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    $portName = [System.IO.Path]::GetFileName((Split-Path $MqTxtPath -Parent))
    $alreadyHas = $false
    $cleanedLines = @()
    foreach ($line in $lines) {
        # Detect a corrupted glued-on entry like "protobufabseil" — split it back out.
        if ($line -match "^([a-z][a-z0-9_-]*)$DepName$") {
            $cleanedLines += $matches[1]
            $alreadyHas = $true   # we'll re-add the dep cleanly below
            continue
        }
        # Match the dep name on its own (possibly with [features] or :triplet)
        if ($line -match "^${DepName}(\[|:|$)") { $alreadyHas = $true; continue }
        $cleanedLines += $line
    }
    $cleanedLines += $DepName
    $newContent = ($cleanedLines -join "`r`n") + "`r`n"
    $needsWrite = ($newContent -ne $raw)
    if (-not $needsWrite) {
        Write-Skip $FixId "$portName/vcpkg_mq.txt already lists $DepName cleanly"
        return $false
    }
    [System.IO.File]::WriteAllText($MqTxtPath, $newContent, [System.Text.UTF8Encoding]::new($false))
    if ($alreadyHas) {
        Write-Fix $FixId "Cleaned + re-added '$DepName' in $portName/vcpkg_mq.txt"
    } else {
        Write-Fix $FixId "Added '$DepName' to $portName/vcpkg_mq.txt"
    }
    return $true
}
$loaderTxt = Join-Path $MQClone "src\loader\vcpkg_mq.txt"
$mainTxt = Join-Path $MQClone "src\main\vcpkg_mq.txt"
$loaderChanged = Add-VcpkgMqDep -MqTxtPath $loaderTxt -DepName 'abseil' -FixId '25a'
$mainChanged = Add-VcpkgMqDep -MqTxtPath $mainTxt -DepName 'abseil' -FixId '25b'

# vcpkg.json files are AUTO-GENERATED from vcpkg_mq.txt by cmake/vcpkg_manifest.cmake, but only
# when the .json doesn't exist (the parse_vcpkg_mq_files function gates regen on `NOT EXISTS`).
# Once vcpkg.json exists, edits to vcpkg_mq.txt are invisible. Delete the .json files we modified
# so cmake's next configure regenerates them with the new abseil dep.
$portsToRefresh = @()
if ($loaderChanged) { $portsToRefresh += @{Port='loader'; Json=Join-Path $MQClone 'src\loader\vcpkg.json'} }
if ($mainChanged)   { $portsToRefresh += @{Port='main';   Json=Join-Path $MQClone 'src\main\vcpkg.json'} }
# Also detect the case where the .txt is correct (abseil present) but the .json is stale (no abseil)
# from a previous run. This is the most common state after we revised fix #25 from JSON-edit to
# txt-edit — the .txt has abseil, the .json doesn't, and cmake never refreshes it.
if (-not $loaderChanged -and (Test-Path $loaderTxt)) {
    $loaderJson = Join-Path $MQClone 'src\loader\vcpkg.json'
    if ((Select-String -Path $loaderTxt -Pattern '^abseil$' -Quiet) -and
        (Test-Path $loaderJson) -and
        -not (Select-String -Path $loaderJson -Pattern '"abseil"' -Quiet)) {
        $portsToRefresh += @{Port='loader (stale json)'; Json=$loaderJson}
    }
}
if (-not $mainChanged -and (Test-Path $mainTxt)) {
    $mainJson = Join-Path $MQClone 'src\main\vcpkg.json'
    if ((Select-String -Path $mainTxt -Pattern '^abseil$' -Quiet) -and
        (Test-Path $mainJson) -and
        -not (Select-String -Path $mainJson -Pattern '"abseil"' -Quiet)) {
        $portsToRefresh += @{Port='main (stale json)'; Json=$mainJson}
    }
}
foreach ($r in $portsToRefresh) {
    if (Test-Path $r.Json) {
        Remove-Item $r.Json -Force -EA SilentlyContinue
        Write-Fix "25d" "Deleted $($r.Port) vcpkg.json so cmake regenerates from updated vcpkg_mq.txt"
    }
}
# Force CMake to reconfigure so vcpkg manifest install re-runs and picks up abseil.
# cmake/vcpkg_manifest.cmake reads vcpkg_mq.txt via file(GLOB) WITHOUT CONFIGURE_DEPENDS, so
# changes to vcpkg_mq.txt do NOT auto-trigger a reconfigure — msbuild would otherwise go
# straight to link using the stale install set.
#
# Idempotency: trigger this whenever the abseil dep is declared in vcpkg_mq.txt but
# absl_base.lib hasn't been installed yet, regardless of whether THIS run edited the file.
# This handles the case where a previous run added the dep but cmake never saw it.
if ($MQBuildDir) {
    $loaderHasAbseil = (Test-Path $loaderTxt) -and (Select-String -Path $loaderTxt -Pattern '^abseil$' -Quiet)
    $mainHasAbseil = (Test-Path $mainTxt) -and (Select-String -Path $mainTxt -Pattern '^abseil$' -Quiet)
    $absLib = Join-Path $MQBuildDir "vcpkg_installed\x86-windows-static\lib\absl_base.lib"
    $needsReconfigure = ($loaderHasAbseil -or $mainHasAbseil) -and -not (Test-Path $absLib)
    if ($needsReconfigure) {
        # Just delete CMakeCache.txt — cmake's regen of vcpkg.json (via fix #25d) plus a fresh
        # configure pass will let vcpkg re-resolve and install abseil. Earlier versions of this
        # fix also deleted the loader/main install markers, but that broke vcpkg's manifest
        # install (it tries to read loader_*.list during main's reinstall and errors when the
        # file is gone). vcpkg will rebuild loader/main on its own when their declared deps
        # changed in vcpkg.json.
        $cmakeCache = Join-Path $MQBuildDir "CMakeCache.txt"
        if (Test-Path $cmakeCache) {
            Remove-Item $cmakeCache -Force -EA SilentlyContinue
            Write-Fix "25c" "Deleted CMakeCache.txt to force vcpkg manifest re-resolve (abseil not yet installed)"
        }
    } elseif (Test-Path $absLib) {
        Write-Skip "25c" "absl_base.lib already installed by vcpkg"
    }
}

# --- #26: src/main/CMakeLists.txt — add vcpkg lib dir to MQ2Main link path ---
# crashpad's base.lib has /DEFAULTLIB:absl_base.lib baked in. After fix #25 installs abseil,
# absl_base.lib is in vcpkg_installed/.../lib but that dir isn't in MQ2Main's link search path
# (vcxproj's <AdditionalLibraryDirectories>). Add target_link_directories so the linker can
# resolve /DEFAULTLIB directives without us having to enumerate every transitive absl lib.
$mainCmake = Join-Path $MQClone "src\main\CMakeLists.txt"
if (Test-Path $mainCmake) {
    $content = Get-Content $mainCmake -Raw
    if ($content -notmatch 'CoOpt UI patch: vcpkg lib dir') {
        $marker = "target_link_libraries(MQ2Main PRIVATE zep eqlib imgui routing)"
        if ($content -match [regex]::Escape($marker)) {
            $insertion = "$marker`r`n`r`n# CoOpt UI patch: vcpkg lib dir for /DEFAULTLIB directives baked into crashpad base.lib`r`ntarget_link_directories(MQ2Main PRIVATE`r`n    `"`${CMAKE_BINARY_DIR}/vcpkg_installed/`${VCPKG_TARGET_TRIPLET}/lib`"`r`n)"
            $content = $content -replace [regex]::Escape($marker), $insertion
            Set-Content $mainCmake $content -NoNewline
            Write-Fix "26" "Added vcpkg lib dir to MQ2Main link path (resolves /DEFAULTLIB:absl_base.lib)"
            $cmakeDirty = $true
        } else {
            Write-Skip "26" "src/main/CMakeLists.txt anchor (target_link_libraries zep eqlib imgui routing) not found"
        }
    } else {
        Write-Skip "26" "src/main/CMakeLists.txt already has vcpkg lib dir patch"
    }
} else {
    Write-Skip "26" "src/main/CMakeLists.txt not found"
}

# --- #27: src/loader/CMakeLists.txt — add vcpkg lib dir to MacroQuest link path ---
# Same /DEFAULTLIB:absl_base.lib issue from crashpad in the loader EXE.
$loaderCmake2 = Join-Path $MQClone "src\loader\CMakeLists.txt"
if (Test-Path $loaderCmake2) {
    $content = Get-Content $loaderCmake2 -Raw
    if ($content -notmatch 'CoOpt UI patch: vcpkg lib dir') {
        $marker = "target_link_libraries(MacroQuest PRIVATE imgui login routing)"
        if ($content -match [regex]::Escape($marker)) {
            $insertion = "$marker`r`n`r`n# CoOpt UI patch: vcpkg lib dir for /DEFAULTLIB directives baked into crashpad base.lib`r`ntarget_link_directories(MacroQuest PRIVATE`r`n    `"`${CMAKE_BINARY_DIR}/vcpkg_installed/`${VCPKG_TARGET_TRIPLET}/lib`"`r`n)"
            $content = $content -replace [regex]::Escape($marker), $insertion
            Set-Content $loaderCmake2 $content -NoNewline
            Write-Fix "27" "Added vcpkg lib dir to MacroQuest link path (resolves /DEFAULTLIB:absl_base.lib)"
            $cmakeDirty = $true
        } else {
            Write-Skip "27" "src/loader/CMakeLists.txt anchor (target_link_libraries MacroQuest imgui login routing) not found"
        }
    } else {
        Write-Skip "27" "src/loader/CMakeLists.txt already has vcpkg lib dir patch"
    }
} else {
    Write-Skip "27" "src/loader/CMakeLists.txt not found"
}

# --- #29: AutoLogin and Lua plugin CMakeLists — same vcpkg lib dir patch as #26/#27 ---
# These plugins also link crashpad transitively (via MQ2Main) and hit the same
# /DEFAULTLIB:absl_base.lib LNK1104. Apply the same target_link_directories pattern.
$pluginPatches = @(
    @{
        File = Join-Path $MQClone "src\plugins\autologin\CMakeLists.txt"
        Target = "MQ2AutoLogin"
        Anchor = "target_link_libraries(MQ2AutoLogin PRIVATE login MQ2Main)"
        FixId = "29a"
    }
    @{
        File = Join-Path $MQClone "src\plugins\lua\CMakeLists.txt"
        Target = "MQ2Lua"
        Anchor = "target_link_libraries(MQ2Lua PRIVATE MQ2Main imgui)"
        FixId = "29b"
    }
)
foreach ($p in $pluginPatches) {
    if (-not (Test-Path $p.File)) {
        Write-Skip $p.FixId "$($p.File) not found"
        continue
    }
    $content = Get-Content $p.File -Raw
    if ($content -match 'CoOpt UI patch: vcpkg lib dir') {
        Write-Skip $p.FixId "$($p.Target) CMakeLists already has vcpkg lib dir patch"
        continue
    }
    if ($content -match [regex]::Escape($p.Anchor)) {
        $insertion = "$($p.Anchor)`r`n`r`n# CoOpt UI patch: vcpkg lib dir for /DEFAULTLIB directives baked into crashpad base.lib`r`ntarget_link_directories($($p.Target) PRIVATE`r`n    `"`${CMAKE_BINARY_DIR}/vcpkg_installed/`${VCPKG_TARGET_TRIPLET}/lib`"`r`n)"
        $content = $content -replace [regex]::Escape($p.Anchor), $insertion
        Set-Content $p.File $content -NoNewline
        Write-Fix $p.FixId "Added vcpkg lib dir to $($p.Target) link path"
        $cmakeDirty = $true
    } else {
        Write-Skip $p.FixId "$($p.Target) CMakeLists anchor not found"
    }
}

# If we modified ANY CMakeLists.txt AND vcxprojs already exist, force a reconfigure so they
# get regenerated with the new target_link_directories.
if ($cmakeDirty -and $MQBuildDir -and (Test-Path (Join-Path $MQBuildDir 'CMakeCache.txt'))) {
    $mainVcxproj = Join-Path $MQBuildDir "src\main\MQ2Main.vcxproj"
    if (Test-Path $mainVcxproj) {
        $mainAge = (Get-Item $mainVcxproj).LastWriteTime
        $cmakeAge = (Get-Item $mainCmake).LastWriteTime
        if ($cmakeAge -gt $mainAge) {
            Remove-Item (Join-Path $MQBuildDir 'CMakeCache.txt') -Force -EA SilentlyContinue
            Write-Fix "27b" "CMakeLists.txt newer than .vcxproj — deleted CMakeCache.txt to force regenerate"
        }
    }
}

# --- #28: include/mq/contrib/protobuf/ProtobufLibs.h — comment out absl pragmas for missing libs ---
# ProtobufLibs.h has hand-written `#pragma comment(lib, "absl_<name>")` directives covering ALL
# the abseil libs the upstream author's newer abseil install produces (~91 libs). Our installed
# abseil@20240116.2 only ships ~80 of those — 11 are absent (newer abseil split internal pieces
# out into separate libs: borrowed_fixup_buffer, decode_rust_punycode, demangle_rust,
# generic_printer_internal, hashtable_profiler, log_internal_structured_proto, poison,
# profile_builder, random_internal_entropy_pool, tracing_internal, utf8_for_code_point).
# Comment out pragmas for libs that don't actually exist on disk so LNK1104 stops firing.
if ($MQBuildDir) {
    $protobufLibsH = Join-Path $MQClone "include\mq\contrib\protobuf\ProtobufLibs.h"
    $vcpkgLibDir = Join-Path $MQBuildDir "vcpkg_installed\x86-windows-static\lib"
    if ((Test-Path $protobufLibsH) -and (Test-Path $vcpkgLibDir)) {
        $content = Get-Content $protobufLibsH -Raw
        $orig = $content
        $missing = @()
        $kept = 0
        # Match any uncommented `#pragma comment(lib, "absl_...")` line
        $lines = $content -split "\r?\n"
        $newLines = @()
        foreach ($line in $lines) {
            # Match any uncommented `#pragma comment(lib, "<name>")` (covers absl_*, utf8_*, etc.).
            # Skip if the lib doesn't exist in vcpkg_installed/lib (release variant).
            if ($line -match '^\s*#pragma\s+comment\s*\(\s*lib\s*,\s*"([A-Za-z][A-Za-z0-9_]+)"\s*\)') {
                $libName = $matches[1]
                $libFile = Join-Path $vcpkgLibDir "$libName.lib"
                if (-not (Test-Path $libFile)) {
                    $missing += $libName
                    $newLines += "// $line  // CoOpt UI patch: $libName.lib not present in installed vcpkg packages"
                    continue
                }
                $kept++
            }
            $newLines += $line
        }
        if ($missing.Count -gt 0) {
            $content = $newLines -join "`r`n"
            [System.IO.File]::WriteAllText($protobufLibsH, $content, [System.Text.UTF8Encoding]::new($false))
            Write-Fix "28" "Commented out $($missing.Count) pragma(s) for libs not in install: $($missing -join ', ')"
            # Force vcxproj rebuild — .obj files need to re-emit /DEFAULTLIB directives.
            # Touch the source files that include ProtobufLibs.h so msbuild recompiles them.
            foreach ($srcFile in @('MQ2Pulse.cpp','MQActorAPI.cpp','MQCommands.cpp','MQPostOffice.cpp')) {
                $p = Join-Path $MQClone "src\main\$srcFile"
                if (Test-Path $p) { (Get-Item $p).LastWriteTime = Get-Date }
            }
            Write-Info "  Touched MQ2Pulse/MQActorAPI/MQCommands/MQPostOffice .cpp to trigger recompile"
        } else {
            Write-Skip "28" "ProtobufLibs.h: all $kept pragmas resolve to installed libs"
        }
    } else {
        Write-Skip "28" "ProtobufLibs.h or vcpkg_installed/lib not found yet"
    }
}

# --- #30: src/main/CMakeLists.txt — force MQ2Main to C++20 ---
# Root CMakeLists.txt sets CMAKE_CXX_STANDARD 20, but the helper target_Common_props() (called
# at line 377 for MQ2Main) explicitly pins LanguageStandard=stdcpp17 in the generated vcxproj.
# That breaks two things:
#   - MQ2DeveloperTools.cpp uses std::erase free function (C++20) — fix #24 worked around by
#     replacing with the C++17 erase-remove idiom.
#   - ImGuiAlphaMask.cpp uses designated initializers `{ .field = value }` (C++20) — can't be
#     trivially rewritten without altering the upstream code's intent.
# Cleaner: explicitly set MQ2Main to C++20 after target_Common_props runs. Mirrors existing
# fix #7 for MQ2Lua, which solved the same problem there.
$mainCmake = Join-Path $MQClone "src\main\CMakeLists.txt"
if (Test-Path $mainCmake) {
    $content = Get-Content $mainCmake -Raw
    if ($content -notmatch 'CoOpt UI patch: force MQ2Main to C\+\+20') {
        $marker = "target_Common_props(MQ2Main)"
        if ($content -match [regex]::Escape($marker)) {
            $insertion = "$marker`r`n`r`n# CoOpt UI patch: force MQ2Main to C++20 — overrides target_Common_props's stdcpp17 pin so`r`n# C++20 features (std::erase, designated initializers in ImGuiAlphaMask.cpp) compile.`r`nset_target_properties(MQ2Main PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED YES)`r`ntarget_compile_options(MQ2Main PRIVATE `"/std:c++20`")"
            $content = $content -replace [regex]::Escape($marker), $insertion
            Set-Content $mainCmake $content -NoNewline
            Write-Fix "30" "Forced MQ2Main to C++20 (overrides target_Common_props stdcpp17)"
            $cmakeDirty = $true
        } else {
            Write-Skip "30" "src/main/CMakeLists.txt anchor (target_Common_props(MQ2Main)) not found"
        }
    } else {
        Write-Skip "30" "src/main/CMakeLists.txt already has C++20 force patch"
    }
}

# Trigger reconfigure if any CMakeLists.txt was modified above (catches #30 too)
if ($cmakeDirty -and $MQBuildDir -and (Test-Path (Join-Path $MQBuildDir 'CMakeCache.txt'))) {
    $mainVcxproj = Join-Path $MQBuildDir "src\main\MQ2Main.vcxproj"
    if (Test-Path $mainVcxproj) {
        $vcxAge = (Get-Item $mainVcxproj).LastWriteTime
        $cmakeAge = (Get-Item $mainCmake).LastWriteTime
        if ($cmakeAge -gt $vcxAge) {
            Remove-Item (Join-Path $MQBuildDir 'CMakeCache.txt') -Force -EA SilentlyContinue
            Write-Fix "30b" "Deleted CMakeCache.txt — CMakeLists.txt newer than .vcxproj"
        }
    }
}

Write-Host ""
Write-Host "Done. Applied: $applied fix(es), Skipped: $skipped (already applied or N/A)." -ForegroundColor Cyan
exit 0
