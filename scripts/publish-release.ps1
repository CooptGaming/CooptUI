# Publish a CoOpt UI release: regenerate manifests, commit, tag, push.
# GitHub Actions (release.yml) then builds the ZIP + patcher exe and creates a draft release.
#
# Usage:
#   .\scripts\publish-release.ps1                   # Read version from version.lua
#   .\scripts\publish-release.ps1 -Version "1.0.0"  # Override version
#   .\scripts\publish-release.ps1 -DryRun            # Preview without committing/pushing
#   .\scripts\publish-release.ps1 -BuildLocal         # Also build zip locally
#   .\scripts\publish-release.ps1 -CleanZips          # Remove old *.zip from repo root

param(
    [string]$Version = "",
    [string]$Branch = "master",
    [switch]$BuildLocal,
    [switch]$CleanZips,
    [switch]$DryRun,
    [switch]$SkipPush
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
$RepoRoot = Split-Path $ScriptDir -Parent

# ======================================================================
# Stage 1: Pre-flight Checks
# ======================================================================

Write-Host ""
Write-Host "=== CoOpt UI Release ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "--- Stage 1: Pre-flight Checks ---" -ForegroundColor Yellow

# 1a. Git available
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is required but not found on PATH."
}
Write-Host "  [OK] git" -ForegroundColor Green

# 1b. Python available
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python is required but not found on PATH (needed for manifest generation)."
}
Write-Host "  [OK] python" -ForegroundColor Green

# 1c. Correct branch
$currentBranch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
if ($currentBranch -ne $Branch) {
    Write-Error "Expected branch '$Branch' but on '$currentBranch'. Switch branches or use -Branch `"$currentBranch`"."
}
Write-Host "  [OK] branch: $currentBranch" -ForegroundColor Green

# 1d. Fetch and check if behind remote
Write-Host "  Fetching origin..." -ForegroundColor DarkGray
git -C $RepoRoot fetch origin $Branch --quiet 2>$null
$localHead = (git -C $RepoRoot rev-parse HEAD 2>$null).Trim()
$remoteHead = (git -C $RepoRoot rev-parse "origin/$Branch" 2>$null).Trim()
if ($localHead -and $remoteHead) {
    $behind = (git -C $RepoRoot rev-list --count "$localHead..$remoteHead" 2>$null).Trim()
    if ($behind -and [int]$behind -gt 0) {
        Write-Warning "  Local is $behind commit(s) behind origin/$Branch. Consider pulling first."
    }
}

# 1e. Read version
if (-not $Version) {
    $versionLua = Join-Path $RepoRoot "lua\coopui\version.lua"
    if (-not (Test-Path $versionLua)) {
        Write-Error "lua/coopui/version.lua not found. Cannot determine version."
    }
    $content = Get-Content $versionLua -Raw
    if ($content -match 'PACKAGE\s*=\s*"([^"]+)"') {
        $Version = $Matches[1]
    } else {
        Write-Error "Could not parse PACKAGE version from lua/coopui/version.lua."
    }
}
# Strip leading "v" if user passed e.g. -Version "v1.0.0" — the tag prefix is added later
$Version = $Version -replace '^v', ''
Write-Host "  [OK] version: $Version" -ForegroundColor Green

# 1f. Loose semver validation (warn only)
if ($Version -notmatch '^\d+\.\d+\.\d+(-[a-zA-Z0-9.\-]+)?$') {
    Write-Warning "  Version '$Version' does not look like semver (X.Y.Z[-prerelease]). Continuing anyway."
}

# 1g. Changelog check (warn only)
$changelogPath = Join-Path $RepoRoot "CHANGELOG.md"
$changelogFound = $false
if (Test-Path $changelogPath) {
    $clContent = Get-Content $changelogPath -Raw
    # Escape regex-special chars in version string for matching
    $escapedVer = [regex]::Escape($Version)
    if ($clContent -match "## \[$escapedVer\]") {
        $changelogFound = $true
        Write-Host "  [OK] CHANGELOG.md has entry for [$Version]" -ForegroundColor Green
    } else {
        Write-Warning "  CHANGELOG.md does not contain a ## [$Version] heading. Release notes may be sparse."
    }
} else {
    Write-Warning "  CHANGELOG.md not found. Release notes will use auto-generated commit list."
}

# 1h. Tag uniqueness
$tag = "v$Version"
$existingTag = git -C $RepoRoot tag --list $tag 2>$null
if ($existingTag -and $existingTag.Trim()) {
    Write-Error "Tag '$tag' already exists. Bump the version in lua/coopui/version.lua or use -Version."
}
Write-Host "  [OK] tag '$tag' is available" -ForegroundColor Green

# 1i. Clean working tree (allow manifest files to be dirty)
$dirtyFiles = git -C $RepoRoot status --porcelain 2>$null
if ($dirtyFiles) {
    $nonManifest = $dirtyFiles | Where-Object {
        $line = $_.Trim()
        -not ($line -match 'release_manifest\.json$') -and
        -not ($line -match 'default_config_manifest\.json$')
    }
    if ($nonManifest) {
        Write-Host ""
        Write-Host "  Uncommitted changes detected:" -ForegroundColor Red
        $nonManifest | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        Write-Error "Working tree is dirty. Commit or stash changes before releasing."
    }
}
Write-Host "  [OK] working tree clean" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "  Release Summary" -ForegroundColor Cyan
Write-Host "  Version:    $Version"
Write-Host "  Tag:        $tag"
Write-Host "  Branch:     $Branch"
Write-Host "  Changelog:  $(if ($changelogFound) { 'found' } else { 'not found (warning)' })"
if ($DryRun) { Write-Host "  Mode:       DRY RUN (no commit/tag/push)" -ForegroundColor Yellow }
if ($SkipPush) { Write-Host "  Mode:       SKIP PUSH (commit + tag locally only)" -ForegroundColor Yellow }
Write-Host ""

# ======================================================================
# Stage 2: Generate Manifests
# ======================================================================

Write-Host "--- Stage 2: Generate Manifests ---" -ForegroundColor Yellow

Push-Location $RepoRoot
try {
    python patcher/generate_manifest.py
    if ($LASTEXITCODE -ne 0) { Write-Error "generate_manifest.py failed." }

    python patcher/generate_default_config_manifest.py
    if ($LASTEXITCODE -ne 0) { Write-Error "generate_default_config_manifest.py failed." }
} finally {
    Pop-Location
}

# Verify generated manifest
$manifestPath = Join-Path $RepoRoot "release_manifest.json"
if (-not (Test-Path $manifestPath)) {
    Write-Error "release_manifest.json was not generated."
}
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$manifestVer = $manifest.version
$fileCount = ($manifest.files | Measure-Object).Count
if ($fileCount -eq 0) {
    Write-Error "release_manifest.json has 0 files. Something went wrong."
}
if ($manifestVer -ne $Version) {
    Write-Warning "  Manifest version '$manifestVer' differs from release version '$Version'."
    Write-Warning "  This usually means lua/coopui/version.lua PACKAGE doesn't match -Version."
}
Write-Host "  release_manifest.json: $fileCount files, version $manifestVer" -ForegroundColor Green

$defaultManifestPath = Join-Path $RepoRoot "default_config_manifest.json"
if (Test-Path $defaultManifestPath) {
    $defaultManifest = Get-Content $defaultManifestPath -Raw | ConvertFrom-Json
    $configCount = ($defaultManifest.files | Measure-Object).Count
    Write-Host "  default_config_manifest.json: $configCount entries" -ForegroundColor Green
}

# ======================================================================
# Stage 3: Commit Manifests
# ======================================================================

Write-Host ""
Write-Host "--- Stage 3: Commit Manifests ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would stage: release_manifest.json, default_config_manifest.json" -ForegroundColor Yellow
    Write-Host "  [DRY RUN] Would commit: chore: regenerate release manifests for $tag" -ForegroundColor Yellow
} else {
    git -C $RepoRoot add release_manifest.json default_config_manifest.json

    # Check if there is actually a diff to commit
    $hasDiff = $true
    git -C $RepoRoot diff --cached --quiet 2>$null
    if ($LASTEXITCODE -eq 0) {
        $hasDiff = $false
    }

    if ($hasDiff) {
        git -C $RepoRoot commit -m "chore: regenerate release manifests for $tag"
        if ($LASTEXITCODE -ne 0) { Write-Error "git commit failed." }
        Write-Host "  Committed manifest updates." -ForegroundColor Green
    } else {
        Write-Host "  Manifests already up to date. No commit needed." -ForegroundColor DarkGray
    }
}

# ======================================================================
# Stage 4: Create Tag
# ======================================================================

Write-Host ""
Write-Host "--- Stage 4: Create Tag ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would create annotated tag: $tag" -ForegroundColor Yellow
} else {
    git -C $RepoRoot tag -a $tag -m "Release $tag"
    if ($LASTEXITCODE -ne 0) { Write-Error "git tag failed." }
    Write-Host "  Created tag: $tag" -ForegroundColor Green
}

# ======================================================================
# Stage 5: Push
# ======================================================================

Write-Host ""
Write-Host "--- Stage 5: Push to Origin ---" -ForegroundColor Yellow

if ($DryRun) {
    Write-Host "  [DRY RUN] Would push: git push origin $Branch" -ForegroundColor Yellow
    Write-Host "  [DRY RUN] Would push: git push origin $tag" -ForegroundColor Yellow
} elseif ($SkipPush) {
    Write-Host "  [SKIP] -SkipPush flag set. Commit and tag are local only." -ForegroundColor Yellow
    Write-Host "  When ready, run:" -ForegroundColor Yellow
    Write-Host "    git push origin $Branch && git push origin $tag" -ForegroundColor White
} else {
    Write-Host "  Pushing branch $Branch..."
    git -C $RepoRoot push origin $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Push failed. Your commit and tag are local. Fix the issue and run:" -ForegroundColor Red
        Write-Host "    git push origin $Branch && git push origin $tag" -ForegroundColor White
        Write-Error "git push origin $Branch failed."
    }
    Write-Host "  Pushing tag $tag..."
    git -C $RepoRoot push origin $tag
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "  Tag push failed. Branch was pushed. Run:" -ForegroundColor Red
        Write-Host "    git push origin $tag" -ForegroundColor White
        Write-Error "git push origin $tag failed."
    }

    # Print helpful URLs
    $remoteUrl = (git -C $RepoRoot remote get-url origin 2>$null).Trim()
    if ($remoteUrl) {
        $repoUrl = $remoteUrl -replace '\.git$', ''
        # Convert SSH to HTTPS for display
        if ($repoUrl -match '^git@github\.com:(.+)$') {
            $repoUrl = "https://github.com/$($Matches[1])"
        }
        Write-Host ""
        Write-Host "  GitHub Actions: $repoUrl/actions" -ForegroundColor Green
        Write-Host "  Draft release:  $repoUrl/releases" -ForegroundColor Green
    }
}

# ======================================================================
# Stage 6 (optional): Local Build
# ======================================================================

if ($BuildLocal) {
    Write-Host ""
    Write-Host "--- Stage 6: Local Build ---" -ForegroundColor Yellow
    $buildScript = Join-Path $ScriptDir "build-release.ps1"
    if (-not (Test-Path $buildScript)) {
        Write-Warning "  build-release.ps1 not found at $buildScript. Skipping local build."
    } else {
        $zipPath = & $buildScript -Version $Version -OutputDir $RepoRoot
        Write-Host "  Local build: $zipPath" -ForegroundColor Green
    }
}

# ======================================================================
# Stage 7 (optional): Clean Old ZIPs
# ======================================================================

if ($CleanZips) {
    Write-Host ""
    Write-Host "--- Stage 7: Clean Old ZIPs ---" -ForegroundColor Yellow
    $currentZipName = "CoOpt UI_v$Version.zip"
    $zips = Get-ChildItem -Path $RepoRoot -Filter "*.zip" -File | Where-Object { $_.Name -ne $currentZipName }
    if ($zips.Count -eq 0) {
        Write-Host "  No old ZIPs to clean." -ForegroundColor DarkGray
    } else {
        foreach ($z in $zips) {
            Remove-Item $z.FullName -Force
            Write-Host "  Removed: $($z.Name)" -ForegroundColor DarkGray
        }
        Write-Host "  Cleaned $($zips.Count) old ZIP(s)." -ForegroundColor Green
    }
}

# ======================================================================
# Done
# ======================================================================

Write-Host ""
if ($DryRun) {
    Write-Host "=== DRY RUN Complete ===" -ForegroundColor Yellow
    Write-Host "  Manifests regenerated but NOT committed."
    Write-Host "  Run without -DryRun to release."
} else {
    Write-Host "=== Release $tag Published ===" -ForegroundColor Cyan
    if (-not $SkipPush) {
        Write-Host "  GitHub Actions will build the ZIP and patcher exe."
        Write-Host "  Review the draft release on GitHub, then publish it."
    }
}
Write-Host ""
