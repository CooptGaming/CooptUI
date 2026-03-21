# Unified release script: manifest gen -> commit -> tag -> push -> local builds -> create release -> publish.
# Builds everything locally (CoOpt UI ZIP, Patcher exe, EMU ZIP) and uploads to GitHub.
#
# Usage:
#   .\scripts\release-all.ps1                          # Full release (all 3 assets)
#   .\scripts\release-all.ps1 -SkipEMU                 # CoOpt UI ZIP + patcher only
#   .\scripts\release-all.ps1 -DryRun                  # Preview all stages
#   .\scripts\release-all.ps1 -Force                   # No prompts, overwrite existing release
#   .\scripts\release-all.ps1 -Version "1.0.0"         # Override version
#   .\scripts\release-all.ps1 -Force -SkipPublish      # Build + upload, leave as draft

param(
    [string]$Version = "",
    [string]$Branch = "master",

    # EMU build (passed through to build-and-deploy.ps1)
    [string]$SourceRoot = "C:\MQ-EMU-Dev",
    [string]$DeployPath = "C:\MQ\Deploy",
    [string]$CMakePath  = "C:\MIS\CMake-3.30",

    # Skip flags
    [switch]$SkipEMU,        # Skip EMU build + upload
    [switch]$SkipPublish,    # Leave release as draft
    [switch]$DryRun,
    [switch]$Force           # Skip prompts + overwrite existing release/assets
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
$RepoRoot = Split-Path $ScriptDir -Parent
$Repo = "CooptGaming/CooptUI"

# ======================================================================
# Stage 1: Pre-flight Checks
# ======================================================================

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "  CoOpt UI - Full Release Pipeline" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "--- Stage 1: Pre-flight Checks ---" -ForegroundColor Yellow

# Required tools
foreach ($cmd in @("git", "python")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "$cmd is required but not found on PATH."
    }
    Write-Host "  [OK] $cmd" -ForegroundColor Green
}

# gh CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "gh CLI is required but not found on PATH. Install from https://cli.github.com/"
}
$ghAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "gh CLI not authenticated. Run: gh auth login"
}
Write-Host "  [OK] gh CLI (authenticated)" -ForegroundColor Green

# PyInstaller for patcher build
$pyiVersion = python -m PyInstaller --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "PyInstaller not found. Installing patcher requirements..."
    $reqFile = Join-Path $RepoRoot "patcher\requirements.txt"
    if (Test-Path $reqFile) {
        python -m pip install -r $reqFile --quiet
    } else {
        python -m pip install pyinstaller customtkinter Pillow --quiet
    }
}
Write-Host "  [OK] PyInstaller" -ForegroundColor Green

# EMU build prerequisites
if (-not $SkipEMU) {
    if (-not (Test-Path $SourceRoot)) {
        Write-Error "SourceRoot not found: $SourceRoot. Use -SkipEMU or provide a valid -SourceRoot."
    }
    Write-Host "  [OK] SourceRoot: $SourceRoot" -ForegroundColor Green

    if (-not (Test-Path $CMakePath)) {
        Write-Warning "CMake path not found: $CMakePath. EMU build may fail."
    } else {
        Write-Host "  [OK] CMake: $CMakePath" -ForegroundColor Green
    }
}

# Version resolution
$Version = $Version -replace '^v', ''
if (-not $Version) {
    $versionLua = Join-Path $RepoRoot "lua\coopui\version.lua"
    if (Test-Path $versionLua) {
        $content = Get-Content $versionLua -Raw
        $pattern = 'PACKAGE\s*=\s*"(.+?)"'
        if ($content -match $pattern) {
            $Version = $Matches[1]
        }
    }
    if (-not $Version) {
        Write-Error "Could not read version from lua/coopui/version.lua. Use -Version parameter."
    }
}
$tag = "v$Version"
Write-Host "  [OK] Version: $Version (tag: $tag)" -ForegroundColor Green

# Check for existing release
$existingRelease = $false
$releaseJson = gh release view $tag --repo $Repo --json tagName,isDraft 2>$null
if ($LASTEXITCODE -eq 0) {
    $existingRelease = $true
    if ($Force) {
        Write-Host "  [!!] Release $tag already exists - will overwrite (-Force)" -ForegroundColor Yellow
    } else {
        Write-Error "Release $tag already exists. Use -Force to overwrite, or choose a different -Version."
    }
}

# Summary
Write-Host ""
Write-Host "  Release Plan:" -ForegroundColor White
Write-Host "    Version:      $Version"
Write-Host "    Tag:          $tag"
Write-Host "    Branch:       $Branch"
$emuPlan = if ($SkipEMU) { "SKIP" } else { "Yes" }
$pubPlan = if ($SkipPublish) { "No (draft)" } else { "Yes" }
$forcePlan = if ($Force) { "Yes (overwrite)" } else { "No" }
Write-Host "    EMU Build:    $emuPlan"
Write-Host "    Auto-Publish: $pubPlan"
Write-Host "    Force:        $forcePlan"
if ($DryRun) {
    Write-Host "    Mode:         DRY RUN" -ForegroundColor Yellow
}
Write-Host ""

if (-not $Force -and -not $DryRun) {
    $confirm = Read-Host "  Proceed? [Y/n]"
    if ($confirm -and $confirm -notin @("y", "Y", "yes", "Yes", "")) {
        Write-Host "  Aborted." -ForegroundColor Red
        return
    }
}

# ======================================================================
# Stage 2: Publish (manifests, commit, tag, push)
# ======================================================================

Write-Host ""
Write-Host "--- Stage 2: Publish (manifests, commit, tag, push) ---" -ForegroundColor Yellow

$publishArgs = @{
    Version = $Version
    Branch  = $Branch
}
if ($DryRun) { $publishArgs.DryRun = $true }

& "$ScriptDir\publish-release.ps1" @publishArgs

if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
    Write-Error "publish-release.ps1 failed. Fix the issue and re-run."
}
Write-Host "  [OK] Publish complete" -ForegroundColor Green

# ======================================================================
# Stage 3: Build CoOpt UI ZIP (local)
# ======================================================================

Write-Host ""
Write-Host "--- Stage 3: Build CoOpt UI ZIP ---" -ForegroundColor Yellow

$cooptZipName = "CoOptUI_v$Version.zip"
$cooptZipPath = Join-Path $RepoRoot $cooptZipName

if ($DryRun) {
    Write-Host "  [DRY RUN] Would run: build-release.ps1 -Version `"$Version`"" -ForegroundColor Yellow
    Write-Host "    Output: $cooptZipPath"
} else {
    & "$ScriptDir\build-release.ps1" -Version $Version -OutputDir $RepoRoot

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "CoOpt UI ZIP build failed."
    }

    if (-not (Test-Path $cooptZipPath)) {
        Write-Error "Expected CoOpt UI ZIP not found at: $cooptZipPath"
    }
    $sizeMB = [math]::Round((Get-Item $cooptZipPath).Length / 1MB, 1)
    Write-Host "  [OK] CoOpt UI ZIP: $cooptZipName ($sizeMB MB)" -ForegroundColor Green
}

# ======================================================================
# Stage 4: Build Patcher exe (local)
# ======================================================================

Write-Host ""
Write-Host "--- Stage 4: Build Patcher exe ---" -ForegroundColor Yellow

$patcherExePath = Join-Path $RepoRoot "patcher\dist\CoOptUIPatcher.exe"

if ($DryRun) {
    Write-Host "  [DRY RUN] Would build patcher via PyInstaller" -ForegroundColor Yellow
    Write-Host "    Output: $patcherExePath"
} else {
    Write-Host "  Building patcher..."

    # Install requirements
    $reqFile = Join-Path $RepoRoot "patcher\requirements.txt"
    if (Test-Path $reqFile) {
        python -m pip install -r $reqFile --quiet
    }

    # Build icon if script exists
    $buildIconScript = Join-Path $RepoRoot "patcher\build_icon.py"
    if (Test-Path $buildIconScript) {
        Push-Location (Join-Path $RepoRoot "patcher")
        python build_icon.py
        Pop-Location
    }

    # Run PyInstaller
    Push-Location (Join-Path $RepoRoot "patcher")
    python -m PyInstaller patcher.spec --noconfirm
    Pop-Location

    if (-not (Test-Path $patcherExePath)) {
        Write-Error "Patcher exe not found at: $patcherExePath"
    }
    $sizeMB = [math]::Round((Get-Item $patcherExePath).Length / 1MB, 1)
    Write-Host "  [OK] Patcher: CoOptUIPatcher.exe ($sizeMB MB)" -ForegroundColor Green
}

# ======================================================================
# Stage 5: Build EMU ZIP
# ======================================================================

Write-Host ""
Write-Host "--- Stage 5: Build EMU ZIP ---" -ForegroundColor Yellow

$emuZipPath = $null

if ($SkipEMU) {
    Write-Host "  [SKIP] EMU build skipped (-SkipEMU)" -ForegroundColor DarkGray
} elseif ($DryRun) {
    $emuZipPath = Join-Path (Split-Path $DeployPath -Parent) "CoOptUI-EMU-$Version.zip"
    Write-Host "  [DRY RUN] Would run:" -ForegroundColor Yellow
    Write-Host "    build-and-deploy.ps1 -SourceRoot `"$SourceRoot`" -DeployPath `"$DeployPath`" -CMakePath `"$CMakePath`" -CreateZip -ZipVersion `"$Version`""
    Write-Host "    Output: $emuZipPath"
} else {
    Write-Host "  Building full EMU (MQ + E3 + CoOpt UI)... this may take several minutes."
    Write-Host ""

    & "$ScriptDir\build-and-deploy.ps1" `
        -SourceRoot $SourceRoot `
        -DeployPath $DeployPath `
        -CMakePath $CMakePath `
        -CreateZip `
        -ZipVersion $Version

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "EMU build failed. Fix the issue and re-run, or use -SkipEMU."
    }

    $emuZipPath = Join-Path (Split-Path $DeployPath -Parent) "CoOptUI-EMU-$Version.zip"
    if (-not (Test-Path $emuZipPath)) {
        Write-Error "Expected EMU ZIP not found at: $emuZipPath"
    }
    $sizeMB = [math]::Round((Get-Item $emuZipPath).Length / 1MB, 1)
    Write-Host ""
    Write-Host "  [OK] EMU ZIP: $emuZipPath ($sizeMB MB)" -ForegroundColor Green
}

# ======================================================================
# Stage 6: Create/Update GitHub Release + Upload Assets
# ======================================================================

Write-Host ""
Write-Host "--- Stage 6: Upload to GitHub Release ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would create/update release $tag and upload:" -ForegroundColor Yellow
    Write-Host "    - $cooptZipName"
    Write-Host "    - CoOptUIPatcher.exe"
    if (-not $SkipEMU) {
        Write-Host "    - CoOptUI-EMU-$tag.zip"
    }
} else {
    # Delete existing release if -Force and it exists
    if ($existingRelease -and $Force) {
        Write-Host "  Deleting existing release $tag..." -ForegroundColor Yellow
        gh release delete $tag --repo $Repo --yes 2>$null
        # Also delete the remote tag so we can recreate it
        # (publish-release.ps1 already created/pushed the new tag)
    }

    # Create draft release
    Write-Host "  Creating draft release $tag..."
    $releaseAssets = @($cooptZipPath, $patcherExePath)
    if (-not $SkipEMU -and $emuZipPath) {
        # Rename EMU ZIP to consistent release name
        $emuReleaseName = "CoOptUI-EMU-$tag.zip"
        $emuReleasePath = Join-Path (Split-Path $emuZipPath -Parent) $emuReleaseName
        if ($emuReleasePath -ne $emuZipPath) {
            Copy-Item $emuZipPath -Destination $emuReleasePath -Force
        }
        $releaseAssets += $emuReleasePath
    }

    # Build the gh release create command with all assets
    $ghArgs = @("release", "create", $tag)
    $ghArgs += $releaseAssets
    $ghArgs += @("--repo", $Repo, "--title", $tag, "--generate-notes", "--draft")
    gh @ghArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create release. Check gh CLI output above."
    }

    # Clean up the EMU copy if we made one
    if (-not $SkipEMU -and $emuReleasePath -and $emuReleasePath -ne $emuZipPath -and (Test-Path $emuReleasePath)) {
        Remove-Item $emuReleasePath -Force
    }

    Write-Host "  [OK] Draft release created with all assets" -ForegroundColor Green
}

# ======================================================================
# Stage 7: Verify Release Assets
# ======================================================================

Write-Host ""
Write-Host "--- Stage 7: Verify Release Assets ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would verify release assets for $tag" -ForegroundColor Yellow
    $expectedList = "$cooptZipName, CoOptUIPatcher.exe"
    if (-not $SkipEMU) { $expectedList += ", CoOptUI-EMU-$tag.zip" }
    Write-Host "    Expected: $expectedList"
} else {
    $assetsJson = gh release view $tag --repo $Repo --json assets 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not read release assets."
    } else {
        $assets = ($assetsJson | ConvertFrom-Json).assets
        Write-Host ""

        $expectedAssets = @(
            $cooptZipName,
            "CoOptUIPatcher.exe"
        )
        if (-not $SkipEMU) {
            $expectedAssets += "CoOptUI-EMU-$tag.zip"
        }

        foreach ($expected in $expectedAssets) {
            $found = $assets | Where-Object { $_.name -eq $expected }
            if ($found) {
                $sizeMB = [math]::Round($found.size / 1MB, 1)
                Write-Host "    [OK] $($found.name) ($sizeMB MB)" -ForegroundColor Green
            } else {
                Write-Host "    [!!] $expected - MISSING" -ForegroundColor Red
            }
        }

        # Show any unexpected extras
        $extras = $assets | Where-Object { $_.name -notin $expectedAssets }
        foreach ($extra in $extras) {
            $sizeMB = [math]::Round($extra.size / 1MB, 1)
            Write-Host "    [??] $($extra.name) ($sizeMB MB) - unexpected" -ForegroundColor Yellow
        }
        Write-Host ""
    }
}

# ======================================================================
# Stage 8: Publish + Summary
# ======================================================================

Write-Host ""
Write-Host "--- Stage 8: Publish Release ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host ""
    $dryPublishLabel = if ($SkipPublish) { "leave release as draft" } else { "publish release" }
    Write-Host "  [DRY RUN] Would $dryPublishLabel" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Yellow
    Write-Host "  DRY RUN Complete - no changes made" -ForegroundColor Yellow
    Write-Host "======================================================" -ForegroundColor Yellow
} else {
    $published = $false

    if ($SkipPublish) {
        Write-Host "  Release left as draft (-SkipPublish)" -ForegroundColor DarkGray
    } else {
        $doPublish = $true
        if (-not $Force) {
            $confirm = Read-Host "  All assets uploaded. Publish release $tag? [Y/n]"
            if ($confirm -and $confirm -notin @("y", "Y", "yes", "Yes", "")) {
                $doPublish = $false
                Write-Host "  Release left as draft." -ForegroundColor Yellow
            }
        }

        if ($doPublish) {
            gh release edit $tag --repo $Repo --draft=false
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Failed to publish release. Do it manually on GitHub."
            } else {
                $published = $true
                Write-Host "  [OK] Release published!" -ForegroundColor Green
            }
        }
    }

    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Release $tag Complete" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Release: https://github.com/$Repo/releases/tag/$tag"
    $statusLabel = if ($published) { "Published" } else { "Draft" }
    $emuLabel = if ($SkipEMU) { "Skipped" } else { "Uploaded" }
    Write-Host "  Status:  $statusLabel"
    Write-Host "  EMU:     $emuLabel"
    Write-Host ""
    if (-not $published) {
        Write-Host "  To publish: gh release edit $tag --repo $Repo --draft=false" -ForegroundColor Yellow
        Write-Host ""
    }
}
