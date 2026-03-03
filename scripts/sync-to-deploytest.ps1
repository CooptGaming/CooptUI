# Sync CoOpt UI development files to a test environment.
# Copies Lua, Macros, resources, and CoopHelper DLL without overwriting user config INIs.
#
# Usage:
#   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2"

param(
    [Parameter(Mandatory)][string]$Target
)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($PSScriptRoot) { Split-Path $PSScriptRoot -Parent } else { Get-Location }

if (-not (Test-Path $Target)) {
    Write-Error "Target directory not found: $Target"
}

Write-Host "Syncing CoOpt UI to: $Target" -ForegroundColor Cyan
Write-Host "  Source: $RepoRoot"
Write-Host ""

$count = 0

# --- Lua modules ---

$luaSources = @(
    @{ Src = "lua\itemui";       Dst = "lua\itemui" }
    @{ Src = "lua\coopui";       Dst = "lua\coopui" }
    @{ Src = "lua\scripttracker"; Dst = "lua\scripttracker" }
)

foreach ($ls in $luaSources) {
    $src = Join-Path $RepoRoot $ls.Src
    $dst = Join-Path $Target $ls.Dst
    if (Test-Path $src) {
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $src -Destination $dst -Recurse -Force
        Remove-Item (Join-Path $dst "docs") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $dst "upvalue_check.lua") -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] $($ls.Src)" -ForegroundColor Green
        $count++
    }
}

$mqLuaSrc = Join-Path $RepoRoot "lua\mq\ItemUtils.lua"
$mqLuaDst = Join-Path $Target "lua\mq"
if (Test-Path $mqLuaSrc) {
    if (-not (Test-Path $mqLuaDst)) { New-Item -ItemType Directory -Path $mqLuaDst -Force | Out-Null }
    Copy-Item $mqLuaSrc -Destination (Join-Path $mqLuaDst "ItemUtils.lua") -Force
    Write-Host "  [OK] lua\mq\ItemUtils.lua" -ForegroundColor Green
    $count++
}

# --- Macros (sell.mac, loot.mac, shared_config/*.mac only — NOT config INIs) ---

$macrosDst = Join-Path $Target "Macros"

$sellMac = Join-Path $RepoRoot "Macros\sell.mac"
if (Test-Path $sellMac) {
    Copy-Item $sellMac -Destination $macrosDst -Force
    Write-Host "  [OK] Macros\sell.mac" -ForegroundColor Green
    $count++
}

$lootMac = Join-Path $RepoRoot "Macros\loot.mac"
if (Test-Path $lootMac) {
    Copy-Item $lootMac -Destination $macrosDst -Force
    Write-Host "  [OK] Macros\loot.mac" -ForegroundColor Green
    $count++
}

$sharedSrc = Join-Path $RepoRoot "Macros\shared_config"
$sharedDst = Join-Path $macrosDst "shared_config"
if (Test-Path $sharedSrc) {
    if (-not (Test-Path $sharedDst)) { New-Item -ItemType Directory -Path $sharedDst -Force | Out-Null }
    Get-ChildItem $sharedSrc -Filter "*.mac" | ForEach-Object {
        Copy-Item $_.FullName -Destination $sharedDst -Force
        $count++
    }
    Write-Host "  [OK] Macros\shared_config\*.mac" -ForegroundColor Green
}

# --- Resources ---

$resSrc = Join-Path $RepoRoot "resources\UIFiles\Default"
$resDst = Join-Path $Target "resources\UIFiles\Default"
if (Test-Path $resSrc) {
    if (-not (Test-Path $resDst)) { New-Item -ItemType Directory -Path $resDst -Force | Out-Null }
    Get-ChildItem $resSrc | Copy-Item -Destination $resDst -Force
    Write-Host "  [OK] resources\UIFiles\Default" -ForegroundColor Green
    $count++
}

# --- CoopHelper DLL (if built) ---

$coopDll = Join-Path $RepoRoot "csharp\coophelper\bin\Release\CoopHelper.dll"
if (-not (Test-Path $coopDll)) {
    $coopDll = Join-Path $RepoRoot "csharp\coophelper\bin\Debug\CoopHelper.dll"
}
if (Test-Path $coopDll) {
    $coopDst = Join-Path $Target "Mono\macros\coophelper"
    if (-not (Test-Path $coopDst)) { New-Item -ItemType Directory -Path $coopDst -Force | Out-Null }
    Copy-Item $coopDll -Destination $coopDst -Force
    Write-Host "  [OK] CoopHelper.dll -> Mono\macros\coophelper\" -ForegroundColor Green
    $count++
}

Write-Host ""
Write-Host "Synced $count item(s) to $Target" -ForegroundColor Cyan
Write-Host "Note: Config INIs (sell_config, shared_config, loot_config) are NOT overwritten." -ForegroundColor DarkGray
