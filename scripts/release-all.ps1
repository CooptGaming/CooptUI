# Unified release script: manifest gen -> commit -> tag -> push -> CI wait -> EMU build -> upload -> publish.
# Orchestrates existing scripts - no logic duplicated.
#
# Usage:
#   .\scripts\release-all.ps1                          # Full release (CI + EMU build + upload + publish)
#   .\scripts\release-all.ps1 -SkipEMU                 # CoOpt UI + patcher only (no EMU build)
#   .\scripts\release-all.ps1 -DryRun                  # Preview all stages without doing anything
#   .\scripts\release-all.ps1 -Force                   # No confirmation prompts
#   .\scripts\release-all.ps1 -Version "1.0.0"         # Override version
#   .\scripts\release-all.ps1 -SkipEMU -SkipPublish    # CI-only, leave draft

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
    [switch]$Force           # Skip confirmation prompts
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

# Summary
Write-Host ""
Write-Host "  Release Plan:" -ForegroundColor White
Write-Host "    Version:      $Version"
Write-Host "    Tag:          $tag"
Write-Host "    Branch:       $Branch"
$emuPlan = if ($SkipEMU) { "SKIP" } else { "Yes" }
$pubPlan = if ($SkipPublish) { "No (draft)" } else { "Yes" }
Write-Host "    EMU Build:    $emuPlan"
Write-Host "    Auto-Publish: $pubPlan"
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
# Stage 3: Wait for CI
# ======================================================================

Write-Host ""
Write-Host "--- Stage 3: Wait for CI ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would wait for GitHub Actions workflow triggered by tag $tag" -ForegroundColor Yellow
} else {
    Write-Host "  Waiting for GitHub Actions run to appear for tag $tag..."

    $runId = $null
    $maxAttempts = 30  # 5 minutes (30 x 10s)
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        $runsJson = gh run list --workflow release.yml --repo $Repo --json databaseId,headBranch,status,conclusion --limit 10 2>$null
        if ($runsJson) {
            $runs = $runsJson | ConvertFrom-Json
            $run = $runs | Where-Object { $_.headBranch -eq $tag } | Select-Object -First 1
            if ($run) {
                $runId = $run.databaseId
                break
            }
        }
        Write-Host "    Polling... ($($i + 1)/$maxAttempts)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 10
    }

    if (-not $runId) {
        Write-Error "GitHub Actions run for tag $tag did not appear within 5 minutes. Check: https://github.com/$Repo/actions"
    }

    Write-Host "  Found CI run: $runId. Streaming output..." -ForegroundColor Green
    Write-Host ""

    gh run watch $runId --repo $Repo --exit-status
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  CI FAILED. View details:" -ForegroundColor Red
        Write-Host "    https://github.com/$Repo/actions/runs/$runId" -ForegroundColor Red
        Write-Host ""
        Write-Host "  To retry: gh run rerun $runId --repo $Repo" -ForegroundColor Yellow
        Write-Error "CI workflow failed. Fix the issue, then re-run or retry the workflow."
    }

    Write-Host ""
    Write-Host "  [OK] CI passed - draft release created with CoOpt UI ZIP + Patcher" -ForegroundColor Green
}

# ======================================================================
# Stage 4: Build EMU ZIP
# ======================================================================

Write-Host ""
Write-Host "--- Stage 4: Build EMU ZIP ---" -ForegroundColor Yellow

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
# Stage 5: Upload EMU ZIP
# ======================================================================

Write-Host ""
Write-Host "--- Stage 5: Upload EMU ZIP ---" -ForegroundColor Yellow

if ($SkipEMU) {
    Write-Host "  [SKIP] EMU upload skipped (-SkipEMU)" -ForegroundColor DarkGray
} elseif ($DryRun) {
    Write-Host "  [DRY RUN] Would upload: $emuZipPath to release $tag" -ForegroundColor Yellow
} else {
    & "$ScriptDir\upload-emu-zip.ps1" -ZipPath $emuZipPath -Tag $tag

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Upload failed. Retry manually:" -ForegroundColor Red
        Write-Host "    .\scripts\upload-emu-zip.ps1 -ZipPath `"$emuZipPath`" -Tag `"$tag`"" -ForegroundColor Yellow
        Write-Error "EMU ZIP upload failed."
    }
    Write-Host "  [OK] EMU ZIP uploaded" -ForegroundColor Green
}

# ======================================================================
# Stage 6: Verify Release Assets
# ======================================================================

Write-Host ""
Write-Host "--- Stage 6: Verify Release Assets ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would verify release assets for $tag" -ForegroundColor Yellow
    $expectedList = "CoOpt UI_v$Version.zip, CoOptUIPatcher.exe"
    if (-not $SkipEMU) { $expectedList += ", CoOptUI-EMU-$tag.zip" }
    Write-Host "    Expected: $expectedList"
} else {
    $assetsJson = gh release view $tag --repo $Repo --json assets 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not read release assets. The release may not exist yet."
    } else {
        $assets = ($assetsJson | ConvertFrom-Json).assets
        Write-Host ""
        Write-Host "  Release Assets for $tag`:" -ForegroundColor White

        $expectedAssets = @(
            "CoOpt UI_v$Version.zip",
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
# Stage 7: Publish + Summary
# ======================================================================

Write-Host ""
Write-Host "--- Stage 7: Publish Release ---" -ForegroundColor Yellow

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
