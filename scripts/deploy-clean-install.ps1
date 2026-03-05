# Deploy a "clean install" of CoOptUI for testing.
# Simulates: zip contents + CoOpt UI patcher deploy (release + default config) + E3 autologin files.
#
# Usage: .\scripts\deploy-clean-install.ps1 -SourceFolder "C:\MQ-EMU-Dev\E3NextAndMQNextBinary-main" -DeployRoot "C:\MQ-EMU-Dev\DeployTest"
#   SourceFolder: Source folder to copy from (extracted zip or prebuild contents).
#   DeployRoot: Destination parent folder where CoOptUI, CoOptUI2, ... are created.
#
# Creates DeployRoot\CoOptUI (or CoOptUI2, CoOptUI3, ...) with:
#   1. Contents of the zip file
#   2. CoOpt UI patcher files: release_manifest + default_config_manifest (from repo)
#   3. CoOptUIPatcher.exe (if built)
#   4. E3 autologin files: MQ2AutoLogin.ini + minimal MacroQuest.ini for mq2autologin plugin

param(
    [string]$SourceFolder = "",
    [string]$DeployRoot = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

if (-not $SourceFolder) {
    Write-Error "  -SourceFolder is required. Provide the path to the extracted zip or prebuild contents (e.g. C:\MQ-EMU-Dev\E3NextAndMQNextBinary-main)."
}
if (-not $DeployRoot) {
    Write-Error "  -DeployRoot is required. Provide the destination parent folder (e.g. C:\MQ-EMU-Dev\DeployTest)."
}

# Resolve deploy folder name: CoOptUI, CoOptUI2, CoOptUI3, ...
function Get-NextCoOptUIFolder {
    param([string]$BasePath)
    $name = "CoOptUI"
    $candidate = Join-Path $BasePath $name
    if (-not (Test-Path $candidate)) { return $name }
    $n = 2
    do {
        $candidate = Join-Path $BasePath "$name$n"
        if (-not (Test-Path $candidate)) { return "$name$n" }
        $n++
    } while ($true)
}

# Copy source folder contents into deploy destination
function Invoke-CopySourceFolder {
    param(
        [string]$SourcePath,
        [string]$DestPath
    )
    Get-ChildItem -Path $SourcePath -Force | Copy-Item -Destination $DestPath -Recurse -Force
    Write-Host "  Copied contents from $SourcePath"
}

# Copy CoOpt UI patcher release manifest files from repo to deploy (what the patcher would deploy)
function Invoke-ApplyReleaseManifest {
    param(
        [string]$DeployDest,
        [string]$RepoRootPath
    )
    $manifestPath = Join-Path $RepoRootPath "release_manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Warning "release_manifest.json not found at $manifestPath; skipping patcher file deploy."
        return
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $count = 0
    foreach ($entry in $manifest.files) {
        $path = $entry.path -replace "/", [System.IO.Path]::DirectorySeparatorChar
        $src = Join-Path $RepoRootPath $path
        $dst = Join-Path $DeployDest $path
        if (Test-Path $src) {
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -Path $src -Destination $dst -Force
            $count++
        }
    }
    Write-Host "  Applied $count release manifest files (CoOpt UI patcher)"
}

# Copy default config files per default_config_manifest (simulate patcher create-if-missing)
function Invoke-ApplyDefaultConfigManifest {
    param(
        [string]$DeployDest,
        [string]$RepoRootPath
    )
    $manifestPath = Join-Path $RepoRootPath "default_config_manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-Warning "default_config_manifest.json not found at $manifestPath; skipping config template install."
        return
    }
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $count = 0
    foreach ($entry in $manifest.files) {
        $repoPath = $entry.repoPath -replace "/", [System.IO.Path]::DirectorySeparatorChar
        $installPath = $entry.installPath -replace "/", [System.IO.Path]::DirectorySeparatorChar
        $src = Join-Path $RepoRootPath $repoPath
        $dst = Join-Path $DeployDest $installPath
        if (Test-Path $src) {
            $dstDir = Split-Path $dst -Parent
            if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
            Copy-Item -Path $src -Destination $dst -Force
            $count++
        }
    }
    Write-Host "  Applied $count default config files (patcher simulation)"
}

# Copy CoOptUIPatcher.exe to deploy root (run from MQ root)
function Invoke-CopyPatcherExe {
    param(
        [string]$DeployDest,
        [string]$RepoRootPath
    )
    $src = Join-Path $RepoRootPath "patcher\dist\CoOptUIPatcher.exe"
    if (-not (Test-Path $src)) {
        Write-Host "  CoOptUIPatcher.exe not found (run: cd patcher; pyinstaller patcher.spec); skipping."
        return
    }
    Copy-Item -Path $src -Destination $DeployDest -Force
    Write-Host "  Copied CoOptUIPatcher.exe to deploy root"
}

# Copy E3 autologin files: MQ2AutoLogin.ini + ensure mq2autologin plugin enabled in MacroQuest.ini
function Invoke-CopyAutoLoginConfig {
    param(
        [string]$DeployDest,
        [string]$RepoRootPath
    )
    $configDir = Join-Path $DeployDest "config"
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }

    # MQ2AutoLogin.ini (required for autologin)
    $autologinSrc = Join-Path $RepoRootPath "config\MQ2AutoLogin.ini"
    if (Test-Path $autologinSrc) {
        Copy-Item -Path $autologinSrc -Destination (Join-Path $configDir "MQ2AutoLogin.ini") -Force
        Write-Host "  Copied MQ2AutoLogin.ini (login config)"
    } else {
        Write-Warning "config\MQ2AutoLogin.ini not found at $autologinSrc; skipping."
    }

    # MacroQuest.ini: ensure mq2autologin=1 so the plugin loads (required for autologin to work)
    $mqIniPath = Join-Path $configDir "MacroQuest.ini"
    $needsAutologin = $true
    if (Test-Path $mqIniPath) {
        $content = Get-Content $mqIniPath -Raw
        if ($content -match "mq2autologin\s*=\s*1") { $needsAutologin = $false }
    }
    if ($needsAutologin) {
        if (Test-Path $mqIniPath) {
            $lines = Get-Content $mqIniPath
            $newLines = @()
            $inserted = $false
            foreach ($line in $lines) {
                $newLines += $line
                if (-not $inserted -and $line -match "^\s*\[Plugins\]\s*$") {
                    $newLines += "mq2autologin=1"
                    $inserted = $true
                }
            }
            if (-not $inserted) { $newLines += "[Plugins]"; $newLines += "mq2autologin=1" }
            Set-Content -Path $mqIniPath -Value $newLines
            Write-Host "  Enabled mq2autologin in MacroQuest.ini"
        } else {
            Set-Content -Path $mqIniPath -Value "[Plugins]`r`nmq2autologin=1`r`n"
            Write-Host "  Created minimal MacroQuest.ini with mq2autologin=1"
        }
    }
}

# --- Main ---
Write-Host "Deploy Clean Install"
Write-Host "  Source: $SourceFolder"
Write-Host "  Target: $DeployRoot"
Write-Host "  Repo:   $RepoRoot"

if (-not (Test-Path $SourceFolder)) {
    Write-Error "Source folder not found: $SourceFolder"
}

if (-not (Test-Path $DeployRoot)) {
    New-Item -ItemType Directory -Path $DeployRoot -Force | Out-Null
}

$folderName = Get-NextCoOptUIFolder -BasePath $DeployRoot
$DeployDest = Join-Path $DeployRoot $folderName
New-Item -ItemType Directory -Path $DeployDest -Force | Out-Null
Write-Host ""
Write-Host "Creating deploy: $DeployDest"

# 1. Copy source folder contents
Write-Host "  Copying from source folder..."
Invoke-CopySourceFolder -SourcePath $SourceFolder -DestPath $DeployDest

# 2. CoOpt UI patcher: copy release_manifest files (what the patcher deploys)
Write-Host "  Applying CoOpt UI patcher release manifest..."
Invoke-ApplyReleaseManifest -DeployDest $DeployDest -RepoRootPath $RepoRoot

# 3. CoOpt UI patcher: apply default_config_manifest (create-if-missing for clean install)
Write-Host "  Applying patcher default config manifest..."
Invoke-ApplyDefaultConfigManifest -DeployDest $DeployDest -RepoRootPath $RepoRoot

# 4. Copy CoOptUIPatcher.exe (if built)
Write-Host "  Copying patcher exe..."
Invoke-CopyPatcherExe -DeployDest $DeployDest -RepoRootPath $RepoRoot

# 5. E3 autologin: MQ2AutoLogin.ini + ensure mq2autologin plugin enabled
Write-Host "  Copying E3 autologin files..."
Invoke-CopyAutoLoginConfig -DeployDest $DeployDest -RepoRootPath $RepoRoot

Write-Host ""
Write-Host "Done. Clean install deployed to: $DeployDest"
