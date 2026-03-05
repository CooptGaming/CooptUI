# Compare folder sizes between deploy, reference, and zip.
# Usage: .\scripts\compare-sizes.ps1 -DeployDir "C:\MQ-EMU-Dev\CompileTest" -RefDir "C:\MQ-EMU-Dev\DeployTest\CoOptUI3" [-ZipSearchDir "C:\MQ-EMU-Dev"]
param(
    [Parameter(Mandatory)][string]$DeployDir,
    [Parameter(Mandatory)][string]$RefDir,
    [string]$ZipSearchDir = ""
)

$deploy = $DeployDir
$ref = $RefDir
$zipPath = $null
if ($ZipSearchDir -and (Test-Path $ZipSearchDir)) {
    $zipPath = Get-ChildItem (Join-Path $ZipSearchDir "CoOptUI-EMU-*.zip") -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($zipPath) {
    $zipMB = [math]::Round($zipPath.Length/1MB, 2)
    $refMB = [math]::Round((Get-ChildItem $ref -Recurse -File | Measure-Object -Property Length -Sum).Sum/1MB, 2)
    Write-Host "=== Size comparison ==="
    Write-Host "Zip: $zipMB MB"
    Write-Host "Reference: $refMB MB"
    Write-Host "Ratio (zip/ref): $([math]::Round($zipPath.Length / (Get-ChildItem $ref -Recurse -File | Measure-Object -Property Length -Sum).Sum, 2))x"
    Write-Host ""
}

Write-Host "=== Deploy top-level folders ==="
Get-ChildItem $deploy -Directory | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    [PSCustomObject]@{Name=$_.Name; SizeMB=[math]::Round($s,2)}
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize

Write-Host "`n=== Reference top-level folders ==="
Get-ChildItem $ref -Directory | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    [PSCustomObject]@{Name=$_.Name; SizeMB=[math]::Round($s,2)}
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize
