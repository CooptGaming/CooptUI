# Sync CoOpt UI development files to a test environment.
# Copies Lua, Macros, resources, and CoopHelper DLL without overwriting user config INIs.
# With -IncludePlugin, also copies MQ2CoOptUI.dll from the MQ build output.
#
# Usage:
#   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2"
#   .\scripts\sync-to-deploytest.ps1 -Target "..." -IncludePlugin
#   .\scripts\sync-to-deploytest.ps1 -Target "..." -IncludePlugin -BuildOutputDir "C:\...\build\solution\bin\release"

param(
    [Parameter(Mandatory)][string]$Target,
    [switch]$IncludePlugin,
    [string]$BuildOutputDir = ""
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

# --- MQ2CoOptUI plugin DLL (from build output, if -IncludePlugin) ---

if ($IncludePlugin) {
    $pluginDll = $null
    if ($BuildOutputDir -and (Test-Path $BuildOutputDir)) {
        $pluginDll = Join-Path $BuildOutputDir "plugins\MQ2CoOptUI.dll"
    } else {
        $defaultBuild = "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution\bin\release\plugins\MQ2CoOptUI.dll"
        if (Test-Path $defaultBuild) { $pluginDll = $defaultBuild }
    }

    if ($pluginDll -and (Test-Path $pluginDll)) {
        $pluginsDst = Join-Path $Target "plugins"
        if (-not (Test-Path $pluginsDst)) { New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null }
        Copy-Item $pluginDll -Destination $pluginsDst -Force
        Write-Host "  [OK] plugins\MQ2CoOptUI.dll (from build output)" -ForegroundColor Green
        $count++
    } else {
        Write-Warning "  MQ2CoOptUI.dll not found in build output. Build with: cmake --build ...\build\solution --config Release --target MQ2CoOptUI"
    }
}

Write-Host ""
Write-Host "Synced $count item(s) to $Target" -ForegroundColor Cyan
Write-Host "Note: Config INIs (sell_config, shared_config, loot_config) are NOT overwritten." -ForegroundColor DarkGray
