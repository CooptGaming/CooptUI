# List and verify contents of the CoOptUI-EMU zip.
# Usage: .\scripts\list-zip.ps1 -ZipPath "C:\MQ-EMU-Dev\CoOptUI-EMU-YYYYMMDD.zip"
param([Parameter(Mandatory)][string]$ZipPath)

if (-not (Test-Path $ZipPath)) {
    Write-Error "Zip not found: $ZipPath"
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
$entryNames = @{}
foreach ($e in $z.Entries) { $entryNames[$e.FullName.Replace('\', '/')] = $true }

Write-Host "=== Zip: $ZipPath ===" -ForegroundColor Cyan
Write-Host "Total entries: $($z.Entries.Count)"
Write-Host ""

# Required files (must exist in zip; paths use forward slash)
$required = @(
    "MacroQuest.exe",
    "plugins/MQ2CoOptUI.dll",
    "plugins/MQ2Mono.dll",
    "config/MacroQuest.ini",
    "config/Autoexec/AutoExec.cfg",
    "lua/itemui/init.lua",
    "mono/macros/e3/E3.dll",
    "mono-2.0-sgen.dll",
    "resources/UIFiles/Default/EQUI.xml",
    "README.txt"
)

Write-Host "--- Required files ---" -ForegroundColor Yellow
$ok = 0
foreach ($rel in $required) {
    $found = $entryNames.ContainsKey($rel)
    if ($found) { $ok++; Write-Host "  [OK]   $rel" -ForegroundColor Green }
    else        { Write-Host "  [MISS] $rel" -ForegroundColor Red }
}
Write-Host ""
Write-Host "Required: $ok / $($required.Count)" -ForegroundColor $(if ($ok -eq $required.Count) { "Green" } else { "Red" })
Write-Host ""

# Sample of contents (first 50)
Write-Host "--- Sample (first 50 entries) ---" -ForegroundColor Yellow
$z.Entries | Select-Object -First 50 FullName | ForEach-Object { $_.FullName }
Write-Host ""

# Extensions summary
$exts = $z.Entries | ForEach-Object { [System.IO.Path]::GetExtension($_.FullName) } | Group-Object | Sort-Object Count -Descending | Select-Object -First 25
Write-Host "--- Extensions (top 25) ---" -ForegroundColor Yellow
$exts | Format-Table Name, Count -AutoSize

if ($z) { $z.Dispose() }

if ($ok -ne $required.Count) { exit 1 }
