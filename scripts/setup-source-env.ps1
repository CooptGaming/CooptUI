# Assemble a unified source environment for building MacroQuest EMU + MQ2Mono + MQ2CoOptUI + E3Next.
#
# Creates a single source root containing:
#   macroquest/        — MQ clone (eqlib on EMU branch, submodules, vcpkg bootstrapped)
#     plugins/MQ2Mono/ — MQ2Mono clone
#     plugins/MQ2CoOptUI/ — symlink to this repo's plugin/MQ2CoOptUI
#   E3Next/            — E3Next C# solution
#
# Usage:
#   .\scripts\setup-source-env.ps1 [-SourceRoot "C:\MQ-EMU-Dev"]
#   .\scripts\setup-source-env.ps1 -SourceRoot "D:\Build\MQ" -MQ2MonoRepo "https://github.com/yourfork/MQ2Mono.git"
#
# After running this, use build-and-deploy.ps1 to build and deploy.

param(
    [string]$SourceRoot = "",
    [string]$CMakePath = "",
    [string]$MQRepo = "https://github.com/macroquest/macroquest.git",
    [string]$MQBranch = "master",
    [string]$EqLibBranch = "emu",
    [string]$MQ2MonoRepo = "https://github.com/RekkasGit/MQ2Mono.git",
    [string]$E3NextRepo = "https://github.com/RekkasGit/E3Next.git",
    [string]$CoOptUIRepo = "",
    [switch]$SkipGotchas,
    [switch]$SkipE3Next,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
$RepoRoot = Split-Path $ScriptDir -Parent

# --- Resolve defaults ---

if (-not $SourceRoot) {
    $SourceRoot = Join-Path (Split-Path $RepoRoot -Parent) "MQ-EMU-Dev"
}

if (-not $CoOptUIRepo) {
    $CoOptUIRepo = $RepoRoot
}

$MQClone = Join-Path $SourceRoot "macroquest"
$E3NextDir = Join-Path $SourceRoot "E3Next"
$PluginsDir = Join-Path $MQClone "plugins"
$MQ2MonoDir = Join-Path $PluginsDir "MQ2Mono"
$MQ2MonoFramework32Dir = Join-Path $SourceRoot "MQ2Mono-Framework32"
$MQ2CoOptUILink = Join-Path $PluginsDir "MQ2CoOptUI"
$PluginSource = Join-Path $CoOptUIRepo "plugin\MQ2CoOptUI"

Write-Host "=== CoOpt UI Source Environment Setup ===" -ForegroundColor Cyan
Write-Host "  Source root:     $SourceRoot"
Write-Host "  MQ clone:        $MQClone"
Write-Host "  Plugin source:   $PluginSource"
Write-Host "  E3Next:          $E3NextDir"
Write-Host "  CMake:           $CMakePath"
Write-Host ""

# --- Validate prerequisites ---

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is required but not found on PATH."
}

if (-not $CMakePath) {
    $autoDetected = @(
        "C:\Program Files\CMake",
        "C:\Program Files (x86)\CMake",
        "${env:LOCALAPPDATA}\CMake"
    ) | Where-Object { Test-Path (Join-Path $_ "bin\cmake.exe") } | Select-Object -First 1
    if ($autoDetected) {
        $CMakePath = $autoDetected
        Write-Host "  Auto-detected CMake at: $CMakePath" -ForegroundColor DarkGray
    } else {
        $fromPath = Get-Command cmake.exe -ErrorAction SilentlyContinue
        if ($fromPath) {
            $CMakePath = Split-Path (Split-Path $fromPath.Source -Parent) -Parent
            Write-Host "  Auto-detected CMake from PATH: $CMakePath" -ForegroundColor DarkGray
        }
    }
}

$cmakeExe = if ($CMakePath) { Join-Path $CMakePath "bin\cmake.exe" } else { "" }
if (-not $cmakeExe -or -not (Test-Path $cmakeExe)) {
    Write-Warning "CMake not found. Provide -CMakePath (e.g. C:\Program Files\CMake) or install CMake and add it to PATH."
    Write-Warning "Download from https://cmake.org/download/"
}

if (-not (Test-Path $PluginSource)) {
    Write-Error "Plugin source not found at: $PluginSource`nEnsure this repo has plugin/MQ2CoOptUI/"
}

# --- Create source root ---

if (-not (Test-Path $SourceRoot)) {
    New-Item -ItemType Directory -Path $SourceRoot -Force | Out-Null
    Write-Host "Created source root: $SourceRoot"
}

# ======================================================================
# Stage 1: Clone MacroQuest
# ======================================================================

Write-Host ""
Write-Host "--- Stage 1: MacroQuest ---" -ForegroundColor Yellow

if (Test-Path $MQClone) {
    if ($Force) {
        Write-Host "  Force flag set. Removing existing MQ clone..."
        Remove-Item $MQClone -Recurse -Force
    } else {
        Write-Host "  MQ clone already exists at $MQClone (use -Force to re-clone)"
    }
}

if (-not (Test-Path $MQClone)) {
    Write-Host "  Cloning MacroQuest from $MQRepo ..."
    git clone --branch $MQBranch $MQRepo $MQClone
    if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed for MacroQuest" }
}

# Submodules
Write-Host "  Initializing submodules..."
Push-Location $MQClone
try {
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { Write-Warning "Submodule update had issues (may be OK if some are optional)" }

    # Switch eqlib to EMU branch
    $eqlibDir = Join-Path $MQClone "src\eqlib"
    if (Test-Path $eqlibDir) {
        Write-Host "  Checking out eqlib on '$EqLibBranch' branch..."
        git -C $eqlibDir checkout $EqLibBranch
        if ($LASTEXITCODE -ne 0) { Write-Warning "Could not checkout eqlib branch '$EqLibBranch'. Verify the branch exists." }
        git -C $eqlibDir pull --ff-only 2>$null
    } else {
        Write-Warning "eqlib directory not found at $eqlibDir"
    }
} finally {
    Pop-Location
}

# Bootstrap vcpkg
$vcpkgExe = Join-Path $MQClone "contrib\vcpkg\vcpkg.exe"
if (-not (Test-Path $vcpkgExe)) {
    Write-Host "  Bootstrapping vcpkg..."
    $bootstrapBat = Join-Path $MQClone "contrib\vcpkg\bootstrap-vcpkg.bat"
    if (Test-Path $bootstrapBat) {
        & cmd /c $bootstrapBat
    } else {
        Write-Warning "vcpkg bootstrap script not found at $bootstrapBat"
    }
} else {
    Write-Host "  vcpkg already bootstrapped"
}

# ======================================================================
# Stage 2: MQ2Mono
# ======================================================================

Write-Host ""
Write-Host "--- Stage 2: MQ2Mono ---" -ForegroundColor Yellow

if (Test-Path $MQ2MonoDir) {
    Write-Host "  MQ2Mono already present at $MQ2MonoDir"
} else {
    Write-Host "  Cloning MQ2Mono from $MQ2MonoRepo ..."
    git clone $MQ2MonoRepo $MQ2MonoDir
    if ($LASTEXITCODE -ne 0) { Write-Error "git clone failed for MQ2Mono" }
    Write-Host "  MQ2Mono cloned." -ForegroundColor Green
}

if (Test-Path $MQ2MonoDir) {
    $monoHasCMake = Test-Path (Join-Path $MQ2MonoDir "CMakeLists.txt")
    if (-not $monoHasCMake) {
        Write-Host "  MQ2Mono uses vcxproj; MQ build will auto-convert to CMake."
    }
}

# --- Stage 2b: MQ2Mono-Framework32 (mono-2.0-sgen.dll for EMU 32-bit) ---
Write-Host ""
Write-Host "--- Stage 2b: Mono Framework (32-bit for EMU) ---" -ForegroundColor Yellow
if (Test-Path $MQ2MonoFramework32Dir) {
    Write-Host "  MQ2Mono-Framework32 already present at $MQ2MonoFramework32Dir"
} else {
    Write-Host "  Cloning MQ2Mono-Framework32 for mono-2.0-sgen.dll ..."
    git clone --depth 1 https://github.com/RekkasGit/MQ2Mono-Framework32.git $MQ2MonoFramework32Dir
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  git clone failed for MQ2Mono-Framework32. You can manually download:"
        Write-Warning "  https://github.com/RekkasGit/MQ2Mono-Framework32/archive/refs/heads/main.zip"
    } else {
        Write-Host "  MQ2Mono-Framework32 cloned." -ForegroundColor Green
    }
}

# ======================================================================
# Stage 3: MQ2CoOptUI symlink
# ======================================================================

Write-Host ""
Write-Host "--- Stage 3: MQ2CoOptUI Plugin Symlink ---" -ForegroundColor Yellow

if (-not (Test-Path $PluginsDir)) {
    New-Item -ItemType Directory -Path $PluginsDir -Force | Out-Null
}

if (Test-Path $MQ2CoOptUILink) {
    $item = Get-Item $MQ2CoOptUILink -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        Write-Host "  Symlink already exists: $MQ2CoOptUILink"
    } else {
        Write-Warning "  $MQ2CoOptUILink exists but is NOT a symlink. Remove it and re-run, or replace manually."
    }
} else {
    Write-Host "  Creating symlink: $MQ2CoOptUILink -> $PluginSource"
    try {
        New-Item -ItemType SymbolicLink -Path $MQ2CoOptUILink -Target $PluginSource -ErrorAction Stop | Out-Null
        Write-Host "  Symlink created successfully." -ForegroundColor Green
    } catch {
        Write-Warning "  Symlink creation failed (may need elevated prompt or Developer Mode enabled)."
        Write-Warning "  Error: $_"
        Write-Host "  Fallback: creating directory junction..."
        try {
            & cmd /c mklink /J "$MQ2CoOptUILink" "$PluginSource"
            Write-Host "  Junction created." -ForegroundColor Green
        } catch {
            Write-Error "Could not create symlink or junction. Run from an elevated prompt or enable Developer Mode."
        }
    }
}

# ======================================================================
# Stage 4: E3Next
# ======================================================================

Write-Host ""
Write-Host "--- Stage 4: E3Next ---" -ForegroundColor Yellow

if ($SkipE3Next) {
    Write-Host "  Skipped (-SkipE3Next flag)"
} elseif (Test-Path $E3NextDir) {
    Write-Host "  E3Next already present at $E3NextDir"
} else {
    Write-Host "  Cloning E3Next from $E3NextRepo ..."
    git clone $E3NextRepo $E3NextDir
    if ($LASTEXITCODE -ne 0) { Write-Warning "git clone failed for E3Next (non-fatal)" }
}

# ======================================================================
# Stage 5: Apply build gotchas
# ======================================================================

Write-Host ""
Write-Host "--- Stage 5: Build Gotchas ---" -ForegroundColor Yellow

if ($SkipGotchas) {
    Write-Host "  Skipped (-SkipGotchas flag)"
} else {
    $gotchasScript = Join-Path $ScriptDir "apply-build-gotchas.ps1"
    if (Test-Path $gotchasScript) {
        & $gotchasScript -MQClone $MQClone
    } else {
        Write-Warning "apply-build-gotchas.ps1 not found at $gotchasScript"
    }
}

# ======================================================================
# Summary
# ======================================================================

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Source root:  $SourceRoot"
Write-Host "MQ clone:     $MQClone"
Write-Host "MQ2CoOptUI:   $MQ2CoOptUILink -> $PluginSource"
if (Test-Path $MQ2MonoDir) {
    Write-Host "MQ2Mono:      $MQ2MonoDir"
} else {
    Write-Host "MQ2Mono:      NOT INSTALLED (provide -MQ2MonoRepo to include)"
}
if (-not $SkipE3Next -and (Test-Path $E3NextDir)) {
    Write-Host "E3Next:       $E3NextDir"
}
Write-Host ""
Write-Host "Next step: build and deploy with:" -ForegroundColor Yellow
Write-Host "  .\scripts\build-and-deploy.ps1 -SourceRoot `"$SourceRoot`" -DeployPath `"C:\MQ\Deploy`""
Write-Host ""
Write-Host "Or configure and build manually:"
Write-Host "  `$env:Path = `"$CMakePath\bin;`" + `$env:Path"
Write-Host "  `$env:VCPKG_ROOT = `"$(Join-Path $MQClone 'contrib\vcpkg')`""
Write-Host "  cd `"$MQClone`""
Write-Host "  cmake -B build/solution -G `"Visual Studio 17 2022`" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON -DMQ_REGENERATE_SOLUTION=OFF"
Write-Host "  cmake --build build/solution --config Release"
