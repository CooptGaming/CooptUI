# Build MacroQuest (with MQ2Mono + MQ2CoOptUI) and E3Next, then deploy everything
# to a target folder with the full CoOpt UI layout.
#
# Prerequisite: run setup-source-env.ps1 first to assemble the source tree.
#
# Usage:
#   .\scripts\build-and-deploy.ps1 -SourceRoot "C:\MQ-EMU-Dev" -DeployPath "C:\MQ\Deploy"
#   .\scripts\build-and-deploy.ps1 -SourceRoot "C:\MQ-EMU-Dev" -DeployPath "C:\MQ\Deploy" -CreateZip
#   .\scripts\build-and-deploy.ps1 -SourceRoot "C:\MQ-EMU-Dev" -DeployPath "C:\MQ\Deploy" -SkipBuild
#   .\scripts\build-and-deploy.ps1 -SourceRoot "C:\MQ-EMU-Dev" -DeployPath "C:\MQ\Deploy" -PluginOnly
#
# -ReferencePath: Local CoOptUI3 (or similar) reference install. Used when -UsePrebuildDownload
#   is false or when the prebuild download fails. When provided, copies its full layout.
# -PluginOnly: Build ONLY the MQ2CoOptUI target and deploy just the DLL + Lua/macros/resources.
#   Skips E3Next build, reference copy, config, mono, README, and zip. ~10s vs full build.
# -UsePrebuiltMQCore: When true (default), use MQ core (MQ2Main, MQ2Mono, etc.) from reference;
#   only MQ2CoOptUI.dll comes from build. Ensures MQ2Mono/E3 work (ABI match). Use -UsePrebuiltMQCore:$false
#   to overlay full MQ build (may break MQ2Mono if source differs from prebuilt).
# -UsePrebuildDownload: When true (default), download E3NextAndMQNextBinary prebuild from
#   -PrebuildDownloadUrl and use it as the reference base. Ensures ALL files (plugins, lua,
#   macros, mono, modules, resources, utilities) are included in Compile Test and the zip.
# -PrebuildDownloadUrl: URL for the prebuild zip. Default: RekkasGit E3NextAndMQNextBinary main.

param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$DeployPath,
    [string]$CMakePath = "C:\MIS\CMake-3.30",
    [string]$Generator = "Visual Studio 17 2022",
    [string]$Configuration = "Release",
    [string]$CoOptUIRepo = "",
    [string]$ReferencePath = "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI3",
    [string]$PrebuildDownloadUrl = "https://github.com/RekkasGit/E3NextAndMQNextBinary/archive/refs/heads/main.zip",
    [switch]$UsePrebuildDownload = $true,
    [string]$E3NextBinaryPath = "",
    [string]$MonoFrameworkPath = "",
    [switch]$SkipBuild,
    [switch]$SkipE3Next,
    [switch]$SkipMQBuild,
    [switch]$PluginOnly,
    [switch]$CreateZip,
    [string]$ZipVersion = "",
    [switch]$SkipClean,
    [switch]$UsePrebuiltMQCore = $true
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
$RepoRoot = Split-Path $ScriptDir -Parent

if (-not $CoOptUIRepo) { $CoOptUIRepo = $RepoRoot }

$MQClone = Join-Path $SourceRoot "macroquest"
$E3NextDir = Join-Path $SourceRoot "E3Next"
$MQBuildDir = Join-Path $MQClone "build\solution"
$MQBinDir = Join-Path $MQBuildDir "bin\$($Configuration.ToLower())"

# --- Validate ---

if (-not (Test-Path $MQClone)) {
    Write-Error "MQ clone not found at: $MQClone`nRun setup-source-env.ps1 first."
}

$cmakeExe = Join-Path $CMakePath "bin\cmake.exe"
if (-not $SkipBuild -and -not $SkipMQBuild -and -not (Test-Path $cmakeExe)) {
    Write-Error "CMake 3.30 not found at $cmakeExe. Install it or use -SkipBuild."
}

# --- Pre-flight: common build gotchas (see .cursor/rules/mq-plugin-build-gotchas.mdc) ---
if (-not $SkipBuild -and -not $SkipMQBuild) {
    $vcpkgExe = Join-Path $MQClone "contrib\vcpkg\vcpkg.exe"
    if (-not (Test-Path $vcpkgExe)) {
        Write-Warning "vcpkg not bootstrapped at $MQClone\contrib\vcpkg. Run: .\contrib\vcpkg\bootstrap-vcpkg.bat"
    }
    $pluginLink = Join-Path $MQClone "plugins\MQ2CoOptUI"
    $pluginSrc = Join-Path $RepoRoot "plugin\MQ2CoOptUI"
    if (-not (Test-Path $pluginLink)) {
        Write-Warning "MQ2CoOptUI plugin not found at $pluginLink. Create symlink (elevated or dev prompt):"
        Write-Host "  New-Item -ItemType SymbolicLink -Path `"$pluginLink`" -Target `"$pluginSrc`"" -ForegroundColor Yellow
    } elseif (-not (Test-Path (Join-Path $pluginLink "CMakeLists.txt"))) {
        Write-Warning "MQ2CoOptUI at $pluginLink does not contain CMakeLists.txt (broken symlink or wrong target?)."
    }
    if ((Test-Path $cmakeExe)) {
        $cmakeVer = & $cmakeExe --version 2>$null | Select-Object -First 1
        if ($cmakeVer -match "4\.\d+") {
            Write-Warning "CMake 4.x detected. Use CMake 3.30 (gotchas: bzip2, vcpkg). Put CMake 3.30 first on PATH."
        }
    }
}

Write-Host "=== CoOpt UI Build & Deploy ===" -ForegroundColor Cyan
Write-Host "  Source root:   $SourceRoot"
Write-Host "  MQ clone:      $MQClone"
Write-Host "  Deploy path:   $DeployPath"
Write-Host "  CMake:         $CMakePath (used for configure and build)"
Write-Host "  Generator:     $Generator"
Write-Host "  Configuration: $Configuration"
Write-Host "  CoOpt UI repo: $CoOptUIRepo"
Write-Host "  Reference:    $ReferencePath"
Write-Host "  Prebuild:     $(if ($UsePrebuildDownload) { 'download from ' + $PrebuildDownloadUrl } else { 'skip (use -ReferencePath)' })"
Write-Host "  MQ core:      $(if ($UsePrebuiltMQCore) { 'prebuilt from reference (only MQ2CoOptUI from build)' } else { 'full from build' })"
Write-Host ""

# ======================================================================
# Stage 1: Build MacroQuest (C++)
# ======================================================================

if (-not $SkipBuild -and -not $SkipMQBuild) {
    Write-Host "--- Stage 1: Build MacroQuest ---" -ForegroundColor Yellow

    # Apply build gotchas to MQ clone so Fix 19 (Mono include), Fix 3 (loader portfile), etc. are present.
    $gotchasScript = Join-Path $RepoRoot "scripts\apply-build-gotchas.ps1"
    if (Test-Path $gotchasScript) {
        Write-Host "  Applying build gotchas to MQ clone..."
        & $gotchasScript -MQClone $MQClone
        if ($LASTEXITCODE -ne 0) { Write-Error "apply-build-gotchas.ps1 failed" }
    }

    $origPath = $env:Path
    $env:Path = "$CMakePath\bin;" + $env:Path
    $env:VCPKG_ROOT = Join-Path $MQClone "contrib\vcpkg"

    Write-Host "  CMake path:  $cmakeExe"
    Write-Host "  CMake:      $(& $cmakeExe --version | Select-Object -First 1)"
    Write-Host "  VCPKG_ROOT: $env:VCPKG_ROOT"

    # Force Win32 triplet and release-only so vcpkg does not install Debug libs (avoids
    # __malloc_dbg/__CrtDbgReport linker errors when linking MQ2Main to crashpad).
    $env:VCPKG_TARGET_TRIPLET = "x86-windows-static"
    $env:VCPKG_BUILD_TYPE = "release"

    # Configure (remove existing build dir to avoid wrong-arch cache unless SkipClean)
    if ((Test-Path $MQBuildDir) -and -not $SkipClean) {
        Write-Host "  Removing existing build/solution for clean configure..."
        Remove-Item $MQBuildDir -Recurse -Force
    }
    Write-Host "  Configuring (Generator: $Generator)..."
    & $cmakeExe -B $MQBuildDir -S $MQClone `
        -G $Generator -A Win32 `
        -DVCPKG_TARGET_TRIPLET=x86-windows-static `
        -DVCPKG_BUILD_TYPE=release `
        -DMQ_BUILD_CUSTOM_PLUGINS=ON `
        -DMQ_BUILD_LAUNCHER=ON `
        -DMQ_REGENERATE_SOLUTION=OFF

    # Apply all post-configure patches, then re-run configure once instead of once per patch.
    # On a fresh build the crashpad patches are always needed; $needReconfigure covers the
    # gotchas Fix 19 too since both are "fresh build only" changes.
    $needReconfigure = $false
    $crashpadConfig = Join-Path $MQBuildDir "vcpkg_installed\x86-windows-static\share\crashpad\crashpadConfig.cmake"

    # Patch 1: crashpad duplicate target guard (registry port missing if(NOT TARGET) guard)
    if (Test-Path $crashpadConfig) {
        $content = Get-Content $crashpadConfig -Raw
        if ($content -match "add_library\(crashpad INTERFACE\)" -and $content -notmatch "if\s*\(\s*NOT\s+TARGET\s+crashpad\s*\)") {
            $content = $content -replace "add_library\(crashpad INTERFACE\)", "if(NOT TARGET crashpad)`nadd_library(crashpad INTERFACE)"
            $content = $content.TrimEnd() + "`nendif()`n"
            Set-Content $crashpadConfig $content -NoNewline
            Write-Host "  Patched crashpad config (duplicate target guard)"
            $needReconfigure = $true
        }
    }

    # Patch 2: crashpad release libs only (re-read in case patch 1 modified the file)
    if (($Configuration -eq "Release") -and (Test-Path $crashpadConfig)) {
        $content = Get-Content $crashpadConfig -Raw
        if ($content -match "find_library\(_LIB \$\{LIB_NAME\}\)" -and $content -notmatch "PATHS.*_IMPORT_PREFIX.*/lib") {
            $content = $content -replace 'find_library\(_LIB \$\{LIB_NAME\}\)', 'find_library(_LIB ${LIB_NAME} PATHS "${_IMPORT_PREFIX}/lib" NO_DEFAULT_PATH)'
            Set-Content $crashpadConfig $content -NoNewline
            Write-Host "  Patched crashpad to use release libs only"
            $needReconfigure = $true
        }
    }

    # Gotchas with build dir (Fix 19/19c - patches generated MQ2Mono CMakeLists/vcxproj).
    # On a fresh build $needReconfigure is already true from the crashpad patches above,
    # so Fix 19 changes are picked up in the same single re-configure pass below.
    if (Test-Path $gotchasScript) {
        & $gotchasScript -MQClone $MQClone -MQBuildDir $MQBuildDir
    }

    # Single re-configure picks up all patches at once (previously 2 extra passes).
    if ($needReconfigure) {
        Write-Host "  Re-configuring to apply all patches (single pass)..."
        & $cmakeExe -B $MQBuildDir -S $MQClone `
            -G $Generator -A Win32 `
            -DVCPKG_TARGET_TRIPLET=x86-windows-static `
            -DVCPKG_BUILD_TYPE=release `
            -DMQ_BUILD_CUSTOM_PLUGINS=ON `
            -DMQ_BUILD_LAUNCHER=ON `
            -DMQ_REGENERATE_SOLUTION=OFF
    }
    if ($LASTEXITCODE -ne 0) { Write-Error "CMake configure failed" }

    # Build
    # When using prebuilt MQ core we only need MQ2CoOptUI from build; building everything would
    # require MQ2Mono (Mono SDK headers) and can fail. So build only the plugin target.
    if ($PluginOnly -or $UsePrebuiltMQCore) {
        Write-Host "  Building MQ2CoOptUI only ($Configuration)..."
        # /p:ContinueOnError=true lets MQ2Main.vcxproj fail (pre-existing crashpad linker issue)
        # while still building MQ2CoOptUI, which has no link dependency on MQ2Main.
        & $cmakeExe --build $MQBuildDir --config $Configuration --target MQ2CoOptUI --parallel -- /p:ContinueOnError=true
        # Validate by checking the DLL on disk rather than the composite exit code.
        $pluginDllPath = Join-Path $MQBinDir "plugins\MQ2CoOptUI.dll"
        if (-not (Test-Path $pluginDllPath)) {
            Write-Error "MQ2CoOptUI.dll not found at $pluginDllPath — build failed"
        }
    } else {
        Write-Host "  Building ($Configuration)..."
        & $cmakeExe --build $MQBuildDir --config $Configuration --parallel
        if ($LASTEXITCODE -ne 0) { Write-Error "CMake build failed" }
    }

    $env:Path = $origPath
    Write-Host "  MQ build complete. Output: $MQBinDir" -ForegroundColor Green
} else {
    Write-Host "--- Stage 1: MQ Build skipped ---" -ForegroundColor Yellow
}

# ======================================================================
# Stage 2: Build E3Next (C#)
# ======================================================================

if (-not $SkipBuild -and -not $SkipE3Next -and -not $PluginOnly) {
    Write-Host ""
    Write-Host "--- Stage 2: Build E3Next ---" -ForegroundColor Yellow

    if ($E3NextBinaryPath -and (Test-Path $E3NextBinaryPath)) {
        Write-Host "  Using pre-built E3Next from: $E3NextBinaryPath"
    } elseif (Test-Path $E3NextDir) {
        $slnFiles = Get-ChildItem $E3NextDir -Filter "*.sln" -Recurse -Depth 2 | Select-Object -First 1
        if ($slnFiles) {
            Write-Host "  Building E3Next solution: $($slnFiles.FullName)"
            $msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" `
                -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1

            if (-not $msbuild) {
                $msbuild = & "${env:ProgramFiles}\Microsoft Visual Studio\Installer\vswhere.exe" `
                    -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
            }

            if ($msbuild) {
                # Restore NuGet packages (E3Next uses packages.config, not PackageReference)
                $nugetExe = "C:\MIS\tools\nuget.exe"
                if (Test-Path $nugetExe) {
                    Write-Host "  Restoring NuGet packages..."
                    & $nugetExe restore $slnFiles.FullName -NonInteractive -Verbosity quiet
                } else {
                    Write-Warning "nuget.exe not found at $nugetExe - NuGet restore skipped. Download from https://www.nuget.org/downloads"
                }
                & $msbuild $slnFiles.FullName /p:Configuration=$Configuration /p:Platform="Any CPU" /v:minimal
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "E3Next build failed. You may need .NET Framework 4.8 Developer Pack."
                    Write-Warning "Download: https://dotnet.microsoft.com/download/dotnet-framework/net48"
                }
            } else {
                Write-Warning "MSBuild not found. Install VS 2022 with .NET desktop workload, or use -E3NextBinaryPath."
            }
        } else {
            Write-Warning "No .sln file found in $E3NextDir"
        }
    } else {
        Write-Host "  E3Next source not found at $E3NextDir; skipping."
        Write-Host "  Use -E3NextBinaryPath to provide pre-built binaries."
    }
} else {
    Write-Host ""
    Write-Host "--- Stage 2: E3Next build skipped ---" -ForegroundColor Yellow
}

# ======================================================================
# Stage 3: Deploy
# ======================================================================

Write-Host ""
Write-Host "--- Stage 3: Deploy ---" -ForegroundColor Yellow

if (-not (Test-Path $DeployPath)) {
    New-Item -ItemType Directory -Path $DeployPath -Force | Out-Null
}

# --- 3prebuild: Download E3NextAndMQNextBinary prebuild (all files for CoOptUI3 layout) ---
# Cached in SourceRoot\downloads so it's part of the compile test environment.
$effectiveRefPath = $null
if ($PluginOnly) {
    Write-Host "  3prebuild/3ref: Skipped (PluginOnly mode)" -ForegroundColor DarkGray
} elseif ($UsePrebuildDownload -and $PrebuildDownloadUrl) {
    $downloadsDir = Join-Path $SourceRoot "downloads"
    $prebuildZip = Join-Path $downloadsDir "E3NextAndMQNextBinary-main.zip"
    $prebuildExtractRoot = $downloadsDir
    $prebuildContent = Join-Path $downloadsDir "E3NextAndMQNextBinary-main"

    if (-not (Test-Path $downloadsDir)) { New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null }

    $needDownload = $true
    if ((Test-Path $prebuildZip) -and (Test-Path $prebuildContent)) {
        $zipAge = (Get-Item $prebuildZip).LastWriteTime
        if ((Get-Date) - $zipAge -lt [TimeSpan]::FromHours(24)) {
            $needDownload = $false
            Write-Host "  3prebuild: Using cached prebuild (downloaded within 24h)"
        }
    }

    if ($needDownload) {
        Write-Host "  3prebuild: Downloading E3NextAndMQNextBinary prebuild..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $PrebuildDownloadUrl -OutFile $prebuildZip -UseBasicParsing
            if (Test-Path $prebuildContent) { Remove-Item $prebuildContent -Recurse -Force }
            Expand-Archive -Path $prebuildZip -DestinationPath $prebuildExtractRoot -Force
            Write-Host "    Downloaded and extracted to $prebuildContent" -ForegroundColor Green
        } catch {
            Write-Warning "  Prebuild download failed: $_"
            Write-Warning "  Falling back to -ReferencePath if available."
        }
    }

    if (Test-Path $prebuildContent) {
        $effectiveRefPath = $prebuildContent
    }
}

if (-not $PluginOnly) {
    if (-not $effectiveRefPath -and $ReferencePath -and (Test-Path $ReferencePath)) {
        $effectiveRefPath = $ReferencePath
    }

    # --- 3ref: Reference base - copy first so our build overwrites ---
    if ($effectiveRefPath) {
        Write-Host "  3ref: Reference base from $effectiveRefPath..."
        $refItems = Get-ChildItem $effectiveRefPath -Force -ErrorAction SilentlyContinue
        foreach ($item in $refItems) {
            $dst = Join-Path $DeployPath $item.Name
            try {
                if ($item.PSIsContainer) {
                    if (-not (Test-Path $dst)) { Copy-Item $item.FullName -Destination $dst -Recurse -Force }
                    else { Copy-Item "$($item.FullName)\*" -Destination $dst -Recurse -Force }
                } else {
                    Copy-Item $item.FullName -Destination $dst -Force
                }
            } catch {
                if ($_.Exception.Message -match "user-mapped section|being used by another process|cannot be accessed") {
                    Write-Warning "  A file in the deploy folder is locked (likely MacroQuest or EverQuest is running from $DeployPath)."
                    Write-Warning "  Close MacroQuest and EverQuest, then re-run this script (use -SkipBuild to deploy only)."
                }
                throw
            }
        }
        Write-Host "    Copied reference base (plugins, lua, macros, mono, modules, resources, etc.)" -ForegroundColor Green
    } else {
        Write-Host "  3ref: No reference (skip). Use -UsePrebuildDownload or -ReferencePath for full layout." -ForegroundColor Yellow
    }
}

# --- 3a: MQ build output ---
# UsePrebuiltMQCore + reference: only overlay MQ2CoOptUI.dll (keeps prebuilt MQ2Main/MQ2Mono ABI match).
# Otherwise: full MQ build overlay.

if ($PluginOnly) {
    Write-Host "  3a: MQ2CoOptUI plugin DLL only (PluginOnly mode)..."
    $srcPluginDll = Join-Path $MQBinDir "plugins\MQ2CoOptUI.dll"
    if (Test-Path $srcPluginDll) {
        $dstPlugins = Join-Path $DeployPath "plugins"
        if (-not (Test-Path $dstPlugins)) { New-Item -ItemType Directory -Path $dstPlugins -Force | Out-Null }
        Copy-Item $srcPluginDll -Destination $dstPlugins -Force
        Write-Host "    Copied MQ2CoOptUI.dll to plugins\" -ForegroundColor Green
    } else {
        Write-Warning "  MQ2CoOptUI.dll not found at $srcPluginDll. Build may have failed."
    }
} elseif ($UsePrebuiltMQCore -and $effectiveRefPath) {
    Write-Host "  3a: MQ2CoOptUI only (prebuilt MQ core from reference)..."
    $srcPluginDll = Join-Path $MQBinDir "plugins\MQ2CoOptUI.dll"
    if (Test-Path $srcPluginDll) {
        $dstPlugins = Join-Path $DeployPath "plugins"
        if (-not (Test-Path $dstPlugins)) { New-Item -ItemType Directory -Path $dstPlugins -Force | Out-Null }
        Copy-Item $srcPluginDll -Destination $dstPlugins -Force
        Write-Host "    Copied MQ2CoOptUI.dll (MQ2Main, MQ2Mono, etc. from reference)" -ForegroundColor Green
    } else {
        Write-Warning "  MQ2CoOptUI.dll not found at $srcPluginDll. Build may have failed."
    }
} else {
    Write-Host "  3a: MQ binaries (full from build)..."
    if (Test-Path $MQBinDir) {
        Get-ChildItem $MQBinDir -File | ForEach-Object {
            Copy-Item $_.FullName -Destination $DeployPath -Force
        }

        $srcPlugins = Join-Path $MQBinDir "plugins"
        if (Test-Path $srcPlugins) {
            $dstPlugins = Join-Path $DeployPath "plugins"
            if (-not (Test-Path $dstPlugins)) { New-Item -ItemType Directory -Path $dstPlugins -Force | Out-Null }
            Copy-Item "$srcPlugins\*" -Destination $dstPlugins -Recurse -Force
            # Trim .pdb (debug symbols) from player deploy
            Get-ChildItem $dstPlugins -Filter "*.pdb" -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
        }

        # Copy any resources from build output
        $srcRes = Join-Path $MQBinDir "resources"
        if (Test-Path $srcRes) {
            $dstRes = Join-Path $DeployPath "resources"
            if (-not (Test-Path $dstRes)) { New-Item -ItemType Directory -Path $dstRes -Force | Out-Null }
            Copy-Item "$srcRes\*" -Destination $dstRes -Recurse -Force
        }

        Write-Host "    Copied MQ build output from $MQBinDir" -ForegroundColor Green
    } else {
        Write-Warning "  MQ build output not found at $MQBinDir. Run without -SkipBuild or -SkipMQBuild."
    }
}

# --- 3b: Config (MacroQuest.ini + MQ2CustomBinds.txt) ---

if ($PluginOnly) {
    Write-Host "  3b-3d, 3f: Skipped (PluginOnly mode)" -ForegroundColor DarkGray
} else {

Write-Host "  3b: Config..."
$configDst = Join-Path $DeployPath "config"
if (-not (Test-Path $configDst)) { New-Item -ItemType Directory -Path $configDst -Force | Out-Null }

$mqIniSrc = Join-Path $CoOptUIRepo "config\MacroQuest.ini"
$mqIniDst = Join-Path $configDst "MacroQuest.ini"
if (Test-Path $mqIniSrc) {
    if (-not (Test-Path $mqIniDst)) {
        Copy-Item $mqIniSrc -Destination $mqIniDst -Force
        Write-Host "    Copied MacroQuest.ini"
    } else {
        Write-Host "    MacroQuest.ini already exists (not overwriting)"
    }
} else {
    # Create a minimal MacroQuest.ini with required plugins
    if (-not (Test-Path $mqIniDst)) {
        $minimalIni = @"
[MacroQuest]
MacroQuestWinClassName=__MacroQuestTray
MacroQuestWinName=MacroQuest
ShowLoaderConsole=0
ShowMacroQuestConsole=1

[Plugins]
mq2lua=1
mq2mono=1
MQ2CoOptUI=1
mq2chatwnd=1
mq2custombinds=1
mq2itemdisplay=1
mq2map=1
mq2nav=1
mq2dannet=1
"@
        Set-Content $mqIniDst $minimalIni
        Write-Host "    Created minimal MacroQuest.ini"
    }
}

# Ensure mq2mono, MQ2CoOptUI, and mq2custombinds are enabled (keybinding needs MQ2CustomBinds)
if (Test-Path $mqIniDst) {
    $iniContent = Get-Content $mqIniDst -Raw
    $modified = $false
    if ($iniContent -notmatch "mq2mono\s*=\s*1") {
        $iniContent = $iniContent -replace "(\[Plugins\])", "`$1`r`nmq2mono=1"
        $modified = $true
    }
    if ($iniContent -notmatch "MQ2CoOptUI\s*=\s*1") {
        $iniContent = $iniContent -replace "(\[Plugins\])", "`$1`r`nMQ2CoOptUI=1"
        $modified = $true
    }
    if ($iniContent -notmatch "mq2custombinds\s*=\s*1") {
        $iniContent = $iniContent -replace "(\[Plugins\])", "`$1`r`nmq2custombinds=1"
        $modified = $true
    }
    if ($modified) {
        Set-Content $mqIniDst $iniContent -NoNewline
        Write-Host "    Ensured mq2mono=1, MQ2CoOptUI=1, mq2custombinds=1 in MacroQuest.ini"
    }
}

$bindsSrc = Join-Path $CoOptUIRepo "config\MQ2CustomBinds.txt"
$bindsDst = Join-Path $configDst "MQ2CustomBinds.txt"
if (Test-Path $bindsSrc) {
    Copy-Item $bindsSrc -Destination $bindsDst -Force
    Write-Host "    Copied MQ2CustomBinds.txt (ItemUI keybind)"
}

# Remove AutoExec.cfg if present (from reference); E3 loads via /mono load e3 when user chooses
$autoexecCfg = Join-Path $configDst "Autoexec\AutoExec.cfg"
if (Test-Path $autoexecCfg) {
    Remove-Item $autoexecCfg -Force
    Write-Host "    Removed config\Autoexec\AutoExec.cfg (E3 loads with /mono load e3)"
}

# --- 3c: Mono runtime ---

Write-Host "  3c: Mono runtime..."
if (-not $MonoFrameworkPath) {
    $framework32 = Join-Path $SourceRoot "MQ2Mono-Framework32"
    $mq2monoRoot = Join-Path $MQClone "plugins\MQ2Mono"
    if ((Test-Path $framework32) -and (Test-Path (Join-Path $framework32 "mono-2.0-sgen.dll"))) {
        $MonoFrameworkPath = $framework32
        Write-Host "    Auto-detected Mono framework: $MonoFrameworkPath"
    } elseif ((Test-Path $mq2monoRoot) -and (Test-Path (Join-Path $mq2monoRoot "mono-2.0-sgen.dll"))) {
        $MonoFrameworkPath = $mq2monoRoot
        Write-Host "    Using mono-2.0-sgen.dll from MQ2Mono plugin"
    }
}
if ($MonoFrameworkPath -and (Test-Path $MonoFrameworkPath)) {
    $monoSgen = Join-Path $MonoFrameworkPath "mono-2.0-sgen.dll"
    if (Test-Path $monoSgen) {
        Copy-Item $monoSgen -Destination $DeployPath -Force
        Write-Host "    Copied mono-2.0-sgen.dll"
    }
    # MQ2Mono requires resources\mono\32bit (lib, etc) for mono_set_dirs - copy from MQ2Mono-Framework32
    $mono32Src = Join-Path $MonoFrameworkPath "resources\Mono\32bit"
    if (Test-Path $mono32Src) {
        $mono32Dst = Join-Path $DeployPath "resources\mono\32bit"
        if (Test-Path $mono32Dst) { Remove-Item $mono32Dst -Recurse -Force }
        New-Item -ItemType Directory -Path $mono32Dst -Force | Out-Null
        Copy-Item "$mono32Src\*" -Destination $mono32Dst -Recurse -Force
        Write-Host "    Copied resources\mono\32bit (Mono runtime for /mono load)"
    }
    # Copy BCL if present (legacy; resources\mono\32bit\lib usually has it)
    $monoBCL = Join-Path $MonoFrameworkPath "lib\mono"
    if (Test-Path $monoBCL) {
        $dstBCL = Join-Path $DeployPath "lib\mono"
        if (-not (Test-Path $dstBCL)) { New-Item -ItemType Directory -Path $dstBCL -Force | Out-Null }
        Copy-Item "$monoBCL\*" -Destination $dstBCL -Recurse -Force
        Write-Host "    Copied Mono BCL"
    }
} else {
    $existingMono = Join-Path $DeployPath "mono-2.0-sgen.dll"
    if (-not (Test-Path $existingMono)) {
        Write-Warning "  Mono runtime not found. Provide -MonoFrameworkPath pointing to MQ2Mono-Framework32."
        Write-Warning "  MQ2Mono will not load without mono-2.0-sgen.dll in the deploy folder."
    } else {
        Write-Host "    mono-2.0-sgen.dll already present"
    }
}

# --- 3d: E3Next output (mono\macros\e3 to match reference layout) ---

Write-Host "  3d: E3Next..."
$e3DeployDir = Join-Path $DeployPath "mono\macros\e3"
if (-not (Test-Path $e3DeployDir)) { New-Item -ItemType Directory -Path $e3DeployDir -Force | Out-Null }

$e3BinResolved = $null
if ($E3NextBinaryPath -and (Test-Path $E3NextBinaryPath)) {
    $e3BinResolved = $E3NextBinaryPath
} elseif (Test-Path $E3NextDir) {
    $candidates = @(
        (Join-Path $E3NextDir "E3Next\bin\$Configuration")
        (Join-Path $E3NextDir "bin\$Configuration")
        (Join-Path $E3NextDir "E3Next\bin\Release")
    )
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and ((Get-ChildItem $c -Filter "E3Next.dll" -ErrorAction SilentlyContinue) -or (Get-ChildItem $c -Filter "E3.dll" -ErrorAction SilentlyContinue))) {
            $e3BinResolved = $c
            break
        }
    }
    if (-not $e3BinResolved) {
        $e3Dll = Get-ChildItem $E3NextDir -Filter "E3.dll" -Recurse -Depth 5 | Select-Object -First 1
        if (-not $e3Dll) { $e3Dll = Get-ChildItem $E3NextDir -Filter "E3Next.dll" -Recurse -Depth 5 | Select-Object -First 1 }
        if ($e3Dll) { $e3BinResolved = $e3Dll.DirectoryName }
    }
}

if ($e3BinResolved) {
    Copy-Item "$e3BinResolved\*" -Destination $e3DeployDir -Recurse -Force
    # E3 expects mono\libs\32bit (and 64bit) for native libs (SQLite.Interop.dll) - copy before removing x86/x64
    $monoLibs32 = Join-Path $DeployPath "mono\libs\32bit"
    $monoLibs64 = Join-Path $DeployPath "mono\libs\64bit"
    $e3x86 = Join-Path $e3DeployDir "x86"
    $e3x64 = Join-Path $e3DeployDir "x64"
    if (Test-Path $e3x86) {
        New-Item -ItemType Directory -Path $monoLibs32 -Force | Out-Null
        Copy-Item (Join-Path $e3x86 "SQLite.Interop.dll") -Destination $monoLibs32 -Force -ErrorAction SilentlyContinue
        Write-Host "    Copied SQLite.Interop.dll to mono\libs\32bit"
    }
    if (Test-Path $e3x64) {
        New-Item -ItemType Directory -Path $monoLibs64 -Force | Out-Null
        Copy-Item (Join-Path $e3x64 "SQLite.Interop.dll") -Destination $monoLibs64 -Force -ErrorAction SilentlyContinue
        Write-Host "    Copied SQLite.Interop.dll to mono\libs\64bit"
    }
    # Trim dev/build artifacts (match CoOptUI3 layout - no x64/x86 in e3, no .pdb/.xml)
    Remove-Item $e3x64 -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $e3x86 -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $e3DeployDir -Filter "*.pdb" -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem $e3DeployDir -Filter "*.xml" -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "    Copied E3Next from $e3BinResolved (trimmed .pdb, .xml, x64, x86)" -ForegroundColor Green
} else {
    Write-Host "    E3Next binaries not found; deploy folder will need E3Next added manually."
    Write-Host "    Use -E3NextBinaryPath or build E3Next first."
}

# E3 Bot Inis / E3 Macro Inis (inside config, to match reference CoOptUI3 layout)
$e3BotInisDir = Join-Path $configDst "e3 Bot Inis"
$e3MacroInisDir = Join-Path $configDst "e3 Macro Inis"
if (-not (Test-Path $e3BotInisDir)) {
    New-Item -ItemType Directory -Path $e3BotInisDir -Force | Out-Null
    Set-Content (Join-Path $e3BotInisDir "README.txt") @"
Place E3Next bot INI files here.
Filename format: CharacterName_ServerShortName.ini
See: https://github.com/RekkasGit/E3Next/wiki
"@
    Write-Host "    Created config\e3 Bot Inis placeholder"
}
if (-not (Test-Path $e3MacroInisDir)) {
    New-Item -ItemType Directory -Path $e3MacroInisDir -Force | Out-Null
    Write-Host "    Created config\e3 Macro Inis placeholder"
}

} # end of -not $PluginOnly block (3b-3d)

# --- 3e: CoOpt UI files (Lua, Macros, resources, configs) ---

Write-Host "  3e: CoOpt UI files..."

# Lua
$luaDst = Join-Path $DeployPath "lua"
if (-not (Test-Path $luaDst)) { New-Item -ItemType Directory -Path $luaDst -Force | Out-Null }

$luaSources = @(
    @{ Src = "lua\itemui";       Dst = "lua\itemui" }
    @{ Src = "lua\coopui";       Dst = "lua\coopui" }
    @{ Src = "lua\scripttracker"; Dst = "lua\scripttracker" }
)
foreach ($ls in $luaSources) {
    $src = Join-Path $CoOptUIRepo $ls.Src
    $dst = Join-Path $DeployPath $ls.Dst
    if (Test-Path $src) {
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $src -Destination $dst -Recurse -Force
        # Remove dev-only files
        Remove-Item (Join-Path $dst "docs") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $dst "upvalue_check.lua") -Force -ErrorAction SilentlyContinue
    }
}

$mqLuaSrc = Join-Path $CoOptUIRepo "lua\mq\ItemUtils.lua"
$mqLuaDst = Join-Path $DeployPath "lua\mq"
if (Test-Path $mqLuaSrc) {
    if (-not (Test-Path $mqLuaDst)) { New-Item -ItemType Directory -Path $mqLuaDst -Force | Out-Null }
    Copy-Item $mqLuaSrc -Destination (Join-Path $mqLuaDst "ItemUtils.lua") -Force
}
Write-Host "    Copied Lua modules (itemui, coopui, scripttracker, mq/ItemUtils)"

# Macros
$macrosDst = Join-Path $DeployPath "Macros"
if (-not (Test-Path $macrosDst)) { New-Item -ItemType Directory -Path $macrosDst -Force | Out-Null }

$sellMac = Join-Path $CoOptUIRepo "Macros\sell.mac"
$lootMac = Join-Path $CoOptUIRepo "Macros\loot.mac"
if (Test-Path $sellMac) { Copy-Item $sellMac -Destination $macrosDst -Force }
if (Test-Path $lootMac) { Copy-Item $lootMac -Destination $macrosDst -Force }

# shared_config/*.mac files
$sharedMacSrc = Join-Path $CoOptUIRepo "Macros\shared_config"
$sharedMacDst = Join-Path $macrosDst "shared_config"
if (-not (Test-Path $sharedMacDst)) { New-Item -ItemType Directory -Path $sharedMacDst -Force | Out-Null }
if (Test-Path $sharedMacSrc) {
    Get-ChildItem $sharedMacSrc -Filter "*.mac" | Copy-Item -Destination $sharedMacDst -Force
}
Write-Host "    Copied Macros (sell.mac, loot.mac, shared_config/*.mac)"

# Config templates -> Macros subdirs (create-if-missing, don't overwrite user configs)
$configManifest = Join-Path $CoOptUIRepo "default_config_manifest.json"
if (Test-Path $configManifest) {
    $manifest = Get-Content $configManifest -Raw | ConvertFrom-Json
    $configCount = 0
    foreach ($entry in $manifest.files) {
        $repoPath = $entry.repoPath -replace "/", [System.IO.Path]::DirectorySeparatorChar
        $installPath = $entry.installPath -replace "/", [System.IO.Path]::DirectorySeparatorChar
        $src = Join-Path $CoOptUIRepo $repoPath
        $dst = Join-Path $DeployPath $installPath
        if (Test-Path $src) {
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            if (-not (Test-Path $dst)) {
                Copy-Item $src -Destination $dst -Force
                $configCount++
            }
        }
    }
    Write-Host "    Deployed $configCount config template(s) (create-if-missing)"
} else {
    Write-Warning "  default_config_manifest.json not found; config templates not deployed."
}

# Resources (UIFiles)
$resSrc = Join-Path $CoOptUIRepo "resources\UIFiles"
$resDst = Join-Path $DeployPath "resources\UIFiles"
if (Test-Path $resSrc) {
    if (-not (Test-Path $resDst)) { New-Item -ItemType Directory -Path $resDst -Force | Out-Null }
    Copy-Item "$resSrc\*" -Destination $resDst -Recurse -Force
    Write-Host "    Copied resources/UIFiles"
}

# CoopHelper DLL (optional)
$coopHelperSrc = Join-Path $CoOptUIRepo "csharp\coophelper\bin\$Configuration\CoopHelper.dll"
if (Test-Path $coopHelperSrc) {
    $coopDst = Join-Path $DeployPath "mono\macros\coophelper"
    if (-not (Test-Path $coopDst)) { New-Item -ItemType Directory -Path $coopDst -Force | Out-Null }
    Copy-Item $coopHelperSrc -Destination $coopDst -Force
    Write-Host "    Copied CoopHelper.dll"
} else {
    Write-Host "    CoopHelper.dll not found (optional, skipping)"
}

if (-not $PluginOnly) {
# --- 3f: README (ready-to-go instructions) ---
$readmePath = Join-Path $DeployPath "README.txt"
$readmeContent = @"
MacroQuest EMU + E3Next + Mono + CoOpt UI (ready-to-go)

CONTENTS
  - MacroQuest launcher and EMU base (32-bit)
  - MQ2Mono plugin + mono-2.0-sgen.dll (C#/E3Next runtime)
  - E3Next (mono\macros\e3\) - load with /mono load e3
  - MQ2CoOptUI plugin + CoOpt UI Lua, macros, UI resources
  - config\MacroQuest.ini (mq2mono=1, MQ2CoOptUI=1, mq2lua=1, etc.)
  - Full CoOptUI3 reference: plugins, lua, macros, modules, resources, utilities

HOW TO USE
  1. Unzip this folder anywhere (e.g. C:\MQ-EMU).
  2. Run MacroQuest.exe.
  3. Launch EverQuest (EMU). Plugins load from config\MacroQuest.ini.
  4. Load E3 with /mono load e3 when in game.

FIRST RUN - What you should see
  - MQ2CoOptUI loads automatically (MQ2CoOptUI=1 in config). In chat you will see:
      [MQ2CoOptUI] v1.0.0 loaded - INI, IPC, cursor, items, loot, window capabilities ready.
      [MQ2CoOptUI] TLO: ${CoOptUI.Version}  Lua: require('plugin.MQ2CoOptUI')
  - To confirm: /echo ${CoOptUI.Version}  (should print 1.0.0)
  - Lua can use: require('plugin.MQ2CoOptUI') for ini, ipc, window, items, loot, cursor APIs.

FOLDER STRUCTURE (do not move files)
  MacroQuest.exe, mono-2.0-sgen.dll  (root)
  config\MacroQuest.ini
  plugins\MQ2Mono.dll, MQ2CoOptUI.dll, ...
  lua\itemui, lua\coopui, lua\scripttracker, lua\mq
  Macros\sell.mac, loot.mac, shared_config\
  mono\macros\e3\   (E3Next)
  config\e3 Bot Inis\   (place E3 bot INIs here)
  config\e3 Macro Inis\
  resources\UIFiles\Default\
"@
Set-Content $readmePath $readmeContent -NoNewline
Write-Host "    Wrote README.txt (included in zip)"
} # end of -not $PluginOnly block (3f)

# ======================================================================
# Stage 4: Optional zip
# ======================================================================

if ($CreateZip) {
    Write-Host ""
    Write-Host "--- Stage 4: Create Zip ---" -ForegroundColor Yellow

    if (-not $ZipVersion) {
        $ZipVersion = Get-Date -Format "yyyyMMdd"
    }
    $zipName = "CoOptUI-EMU-$ZipVersion.zip"
    $zipPath = Join-Path (Split-Path $DeployPath -Parent) $zipName

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipSafeTime = [DateTime]::Parse("2020-01-01 00:00:00")
    $deployRoot = (Resolve-Path $DeployPath).Path.TrimEnd('\')
    # Exclude Source and dev-only content - zip is for players only
    $excludeDirs = @("Source")
    $excludeExt = @(".pdb", ".cs", ".csproj", ".sln", ".vcxproj", ".vcxproj.filters", ".obj", ".lib")
    $allFiles = Get-ChildItem -Path $DeployPath -Recurse -File
    $files = $allFiles | Where-Object {
        $rel = $_.FullName.Substring($deployRoot.Length + 1)
        $excluded = $false
        foreach ($ex in $excludeDirs) {
            if ($rel -eq $ex -or $rel.StartsWith($ex + [IO.Path]::DirectorySeparatorChar)) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded -and $excludeExt -contains $_.Extension.ToLower()) { $excluded = $true }
        if (-not $excluded -and $rel -match '\\x64\\') { $excluded = $true }
        -not $excluded
    }
    $excludedCount = $allFiles.Count - $files.Count
    if ($excludedCount -gt 0) {
        Write-Host "  Excluded $excludedCount files (Source and dev-only folders)"
    }
    $archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $fileStream = $null
        foreach ($f in $files) {
            $entryName = $f.FullName.Substring($deployRoot.Length + 1).Replace('\', '/')
            $entry = $archive.CreateEntry($entryName, [System.IO.Compression.CompressionLevel]::Fastest)
            $entry.LastWriteTime = $zipSafeTime
            $stream = $entry.Open()
            try {
                $fileStream = [System.IO.File]::OpenRead($f.FullName)
                $fileStream.CopyTo($stream)
            } finally {
                if ($null -ne $fileStream) { $fileStream.Dispose() }
                $stream.Close()
            }
        }
        Write-Host "  Created: $zipPath" -ForegroundColor Green
    } finally {
        $archive.Dispose()
    }
}

# ======================================================================
# Summary
# ======================================================================

Write-Host ""
Write-Host "=== Deploy Complete ===" -ForegroundColor Cyan
Write-Host "  Target: $DeployPath"
Write-Host ""

# Verify key files
$checks = @(
    @{ Path = "MacroQuest.exe";              Label = "MacroQuest launcher" }
    @{ Path = "plugins\MQ2CoOptUI.dll";      Label = "MQ2CoOptUI plugin" }
    @{ Path = "plugins\MQ2Mono.dll";         Label = "MQ2Mono plugin" }
    @{ Path = "config\MacroQuest.ini";       Label = "MacroQuest config" }
    @{ Path = "lua\itemui\init.lua";         Label = "CoOpt UI Lua" }
    @{ Path = "mono\macros\e3\E3.dll";       Label = "E3Next" }
    @{ Path = "mono-2.0-sgen.dll";           Label = "Mono runtime" }
    @{ Path = "resources\UIFiles\Default\EQUI.xml"; Label = "UI resources" }
)

Write-Host "  Deployment check:"
foreach ($check in $checks) {
    $fullPath = Join-Path $DeployPath $check.Path
    if (Test-Path $fullPath) {
        Write-Host "    [OK]   $($check.Label)" -ForegroundColor Green
    } else {
        Write-Host "    [MISS] $($check.Label) ($($check.Path))" -ForegroundColor Yellow
    }
}
Write-Host ""
