# Upload the full EMU ZIP (MQ + Mono + E3 + CoOpt UI) to an existing GitHub Release.
#
# The full EMU ZIP is built locally via build-and-deploy.ps1 -CreateZip because it requires
# Visual Studio, CMake, Mono SDK, etc. that can't run in GitHub Actions. This script attaches
# that ZIP to the draft release created by publish-release.ps1 / GitHub Actions.
#
# Usage:
#   .\scripts\upload-emu-zip.ps1 -ZipPath "C:\MQ\CoOptUI-EMU-v1.0.0.zip"
#   .\scripts\upload-emu-zip.ps1 -ZipPath "C:\MQ\CoOptUI-EMU-v1.0.0.zip" -Tag "v1.0.0"
#   .\scripts\upload-emu-zip.ps1 -ZipPath "C:\MQ\CoOptUI-EMU-v1.0.0.zip" -DryRun
#
# Prerequisites:
#   - gh CLI installed and authenticated (https://cli.github.com/)
#   - A GitHub Release must already exist for the tag (draft or published)
#
# The script renames the ZIP to a consistent pattern: CoOptUI-EMU-v<version>.zip

param(
    [Parameter(Mandatory)][string]$ZipPath,
    [string]$Tag = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
$RepoRoot = Split-Path $ScriptDir -Parent

Write-Host ""
Write-Host "=== Upload EMU ZIP to GitHub Release ===" -ForegroundColor Cyan
Write-Host ""

# ======================================================================
# Pre-flight checks
# ======================================================================

# 1. gh CLI available
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "gh CLI is required but not found on PATH. Install from https://cli.github.com/"
}
Write-Host "  [OK] gh CLI" -ForegroundColor Green

# 2. gh authenticated
$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "gh CLI not authenticated. Run: gh auth login"
}
Write-Host "  [OK] gh authenticated" -ForegroundColor Green

# 3. ZIP file exists and is valid
if (-not (Test-Path $ZipPath)) {
    Write-Error "ZIP file not found: $ZipPath"
}
$zipItem = Get-Item $ZipPath
$sizeMB = [math]::Round($zipItem.Length / 1MB, 1)
Write-Host "  [OK] ZIP: $($zipItem.Name) ($sizeMB MB)" -ForegroundColor Green

# 4. Resolve tag
if (-not $Tag) {
    # Read version from lua/coopui/version.lua
    $versionLua = Join-Path $RepoRoot "lua\coopui\version.lua"
    if (Test-Path $versionLua) {
        $content = Get-Content $versionLua -Raw
        if ($content -match 'PACKAGE\s*=\s*"([^"]+)"') {
            $Tag = "v$($Matches[1])"
        }
    }
    if (-not $Tag) {
        # Fallback: latest tag
        $Tag = (git -C $RepoRoot describe --tags --abbrev=0 2>$null)
        if (-not $Tag) {
            Write-Error "Could not determine tag. Use -Tag parameter."
        }
    }
}
$Tag = $Tag.Trim()
Write-Host "  [OK] tag: $Tag" -ForegroundColor Green

# 5. Release exists for this tag
$releaseInfo = gh release view $Tag --repo RekkasGit/E3NextAndMQNextBinary --json tagName,isDraft,name 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Error "No GitHub Release found for tag '$Tag'. Run publish-release.ps1 first, or wait for GitHub Actions to create the draft."
}
$release = $releaseInfo | ConvertFrom-Json
$draftLabel = if ($release.isDraft) { " (draft)" } else { "" }
Write-Host "  [OK] release: $($release.name)$draftLabel" -ForegroundColor Green

# 6. Check if EMU ZIP already attached
$existingAssets = gh release view $Tag --repo RekkasGit/E3NextAndMQNextBinary --json assets 2>$null | ConvertFrom-Json
$version = $Tag -replace '^v', ''
$targetName = "CoOptUI-EMU-$Tag.zip"
$alreadyUploaded = $existingAssets.assets | Where-Object { $_.name -eq $targetName }
if ($alreadyUploaded) {
    Write-Warning "  Asset '$targetName' already exists on release $Tag."
    Write-Warning "  To replace it, delete it on GitHub first, then re-run."
    if (-not $DryRun) {
        Write-Error "Asset already exists. Delete it first or use a different filename."
    }
}

# ======================================================================
# Prepare and upload
# ======================================================================

Write-Host ""

# Rename/copy to consistent name if needed
$uploadPath = $ZipPath
if ($zipItem.Name -ne $targetName) {
    $uploadPath = Join-Path $zipItem.DirectoryName $targetName
    if ($uploadPath -ne $ZipPath) {
        Write-Host "  Copying to consistent name: $targetName"
        if (-not $DryRun) {
            Copy-Item $ZipPath -Destination $uploadPath -Force
        }
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Host "  [DRY RUN] Would upload:" -ForegroundColor Yellow
    Write-Host "    File:    $uploadPath ($sizeMB MB)"
    Write-Host "    Release: $Tag$draftLabel"
    Write-Host "    Asset:   $targetName"
    Write-Host ""
    Write-Host "=== DRY RUN Complete ===" -ForegroundColor Yellow
} else {
    Write-Host "  Uploading $targetName ($sizeMB MB) to release $Tag..."
    gh release upload $Tag $uploadPath --repo RekkasGit/E3NextAndMQNextBinary --clobber
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Upload failed."
    }

    # Clean up the copy if we made one
    if ($uploadPath -ne $ZipPath -and (Test-Path $uploadPath)) {
        Remove-Item $uploadPath -Force
    }

    Write-Host ""
    Write-Host "=== Upload Complete ===" -ForegroundColor Cyan
    Write-Host "  Asset: $targetName ($sizeMB MB)"
    Write-Host "  Release: https://github.com/RekkasGit/E3NextAndMQNextBinary/releases/tag/$Tag"
    Write-Host ""
    if ($release.isDraft) {
        Write-Host "  The release is still a draft. Review and publish it on GitHub." -ForegroundColor Yellow
    }
}
