# Build CoOpt UI release zip for GitHub or local distribution.
# Usage: .\scripts\build-release.ps1 [-Version "0.1.0-alpha"] [-OutputDir "."]
#   Version: version string for zip name (e.g. 0.1.0-alpha). Default from env RELEASE_VERSION or "0.1.0-alpha".
#   OutputDir: where to write the zip. Default: repo root.
# Run from repo root, or script will use script's parent's parent as repo root.

param(
    [string]$Version = $env:RELEASE_VERSION,
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }
if (-not $Version) { $Version = "1.0.0" }
if (-not $OutputDir) { $OutputDir = $RepoRoot }

$ZipName = "CoOptUI-v$Version.zip"
$Staging = Join-Path $env:TEMP "CoOptUI_release_staging_$(Get-Random)"
New-Item -ItemType Directory -Path $Staging -Force | Out-Null

try {
    # Lua: itemui (full), scripttracker (full), coopui (version + theme), mq/ItemUtils.lua
    $luaDest = Join-Path $Staging "lua"
    New-Item -ItemType Directory -Path $luaDest -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot "lua\itemui") -Destination (Join-Path $luaDest "itemui") -Recurse -Force

    # Remove dev-only files from release staging
    $itemuiStaged = Join-Path $luaDest "itemui"
    Remove-Item -Path (Join-Path $itemuiStaged "docs") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $itemuiStaged "upvalue_check.lua") -Force -ErrorAction SilentlyContinue

    Copy-Item -Path (Join-Path $RepoRoot "lua\scripttracker") -Destination (Join-Path $luaDest "scripttracker") -Recurse -Force
    Copy-Item -Path (Join-Path $RepoRoot "lua\coopui") -Destination (Join-Path $luaDest "coopui") -Recurse -Force
    $mqDest = Join-Path $luaDest "mq"
    New-Item -ItemType Directory -Path $mqDest -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot "lua\mq\ItemUtils.lua") -Destination (Join-Path $mqDest "ItemUtils.lua") -Force

    # Macros: sell.mac, loot.mac, shared_config/*.mac only
    $macrosDest = Join-Path $Staging "Macros"
    New-Item -ItemType Directory -Path $macrosDest -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot "Macros\sell.mac") -Destination $macrosDest -Force
    Copy-Item -Path (Join-Path $RepoRoot "Macros\loot.mac") -Destination $macrosDest -Force
    $sharedDest = Join-Path $macrosDest "shared_config"
    New-Item -ItemType Directory -Path $sharedDest -Force | Out-Null
    Get-ChildItem -Path (Join-Path $RepoRoot "Macros\shared_config") -Filter "*.mac" | Copy-Item -Destination $sharedDest -Force

    # config_templates: INI files from config_templates/ (canonical source; Macros/*.ini are gitignored)
    $ct = Join-Path $Staging "config_templates"
    $ctSell = Join-Path $ct "sell_config"
    $ctShared = Join-Path $ct "shared_config"
    $ctLoot = Join-Path $ct "loot_config"
    New-Item -ItemType Directory -Path $ctSell, $ctShared, $ctLoot -Force | Out-Null
    Get-ChildItem -Path (Join-Path $RepoRoot "config_templates\sell_config") -Filter "*.ini" -ErrorAction SilentlyContinue | Copy-Item -Destination $ctSell -Force
    Get-ChildItem -Path (Join-Path $RepoRoot "config_templates\shared_config") -Filter "*.ini" -ErrorAction SilentlyContinue | Copy-Item -Destination $ctShared -Force
    Get-ChildItem -Path (Join-Path $RepoRoot "config_templates\loot_config") -Filter "*.ini" -ErrorAction SilentlyContinue | Copy-Item -Destination $ctLoot -Force

    # resources: ItemUI UI files only
    $resDest = Join-Path $Staging "resources\UIFiles\Default"
    New-Item -ItemType Directory -Path $resDest -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot "resources\UIFiles\Default\EQUI.xml") -Destination $resDest -Force
    Copy-Item -Path (Join-Path $RepoRoot "resources\UIFiles\Default\MQUI_ItemColorAnimation.xml") -Destination $resDest -Force
    $tgaPath = Join-Path $RepoRoot "resources\UIFiles\Default\ItemColorBG.tga"
    if (Test-Path $tgaPath) {
        Copy-Item -Path $tgaPath -Destination $resDest -Force
    } else {
        Write-Warning "ItemColorBG.tga not found at $tgaPath (optional UI texture)"
    }

    # Root: DEPLOY.md, optional CHANGELOG.md
    Copy-Item -Path (Join-Path $RepoRoot "DEPLOY.md") -Destination $Staging -Force
    $changelog = Join-Path $RepoRoot "CHANGELOG.md"
    if (Test-Path $changelog) { Copy-Item -Path $changelog -Destination $Staging -Force }

    # Create zip
    $zipPath = Join-Path $OutputDir $ZipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $Staging "*") -DestinationPath $zipPath -Force
    Write-Host "Created: $zipPath"
    return $zipPath
} finally {
    if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
}
