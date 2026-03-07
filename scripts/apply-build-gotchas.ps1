# Apply known build fixes to an MQ clone so it builds cleanly with CMake 3.30 + VS 2022.
# Reference: .cursor/rules/mq-plugin-build-gotchas.mdc
# All patches are idempotent (safe to run multiple times).
#
# Usage: .\scripts\apply-build-gotchas.ps1 -MQClone "C:\MQ-EMU-Dev\macroquest"

param(
    [Parameter(Mandatory)][string]$MQClone,
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

# --- #4: Crashpad duplicate target guard ---
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
        $content = $content -replace "(#include\s*<[^>]+>)", "`$1`n#include <array>", 1
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
$mq2MonoCMake = Join-Path $MQClone "plugins\MQ2Mono\CMakeLists.txt"
$monoIncludeDir = Join-Path $MQClone "plugins\MQ2Mono\Mono\include\mono-2.0"
if ((Test-Path $mq2MonoCMake) -and (Test-Path $monoIncludeDir)) {
    $content = Get-Content $mq2MonoCMake -Raw
    if ($content -notmatch "Mono/include/mono-2.0") {
        $content = $content -replace "(target_Plugin_props\(MQ2Mono\))", "`$1`n`n# Mono SDK headers (bundled in MQ2Mono repo)`ntarget_include_directories(MQ2Mono PRIVATE `"`${CMAKE_CURRENT_LIST_DIR}/Mono/include/mono-2.0`")"
        Set-Content $mq2MonoCMake $content -NoNewline
        Write-Fix "19" "Added Mono include path to MQ2Mono CMakeLists.txt"
    } else {
        Write-Skip "19" "MQ2Mono already has Mono include path"
    }
} else {
    Write-Skip "19" "MQ2Mono CMakeLists or Mono include dir not found"
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

Write-Host ""
Write-Host "Done. Applied: $applied fix(es), Skipped: $skipped (already applied or N/A)." -ForegroundColor Cyan
