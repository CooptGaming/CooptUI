# Compare folder sizes between deploy, CoOptUI3, and zip
$deploy = "C:\MIS\MacroquestEnvironments\CompileTest"
$ref = "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI3"
$zipPath = Get-ChildItem "C:\MIS\MacroquestEnvironments\CoOptUI-EMU-*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($zipPath) {
    $zipMB = [math]::Round($zipPath.Length/1MB, 2)
    $refMB = [math]::Round((Get-ChildItem $ref -Recurse -File | Measure-Object -Property Length -Sum).Sum/1MB, 2)
    Write-Host "=== Size comparison ==="
    Write-Host "Zip: $zipMB MB"
    Write-Host "CoOptUI3: $refMB MB"
    Write-Host "Ratio (zip/CoOptUI3): $([math]::Round($zipPath.Length / (Get-ChildItem $ref -Recurse -File | Measure-Object -Property Length -Sum).Sum, 2))x"
    Write-Host ""
}

Write-Host "=== Deploy (CompileTest) top-level folders ==="
Get-ChildItem $deploy -Directory | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    [PSCustomObject]@{Name=$_.Name; SizeMB=[math]::Round($s,2)}
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize

Write-Host "`n=== CoOptUI3 top-level folders ==="
Get-ChildItem $ref -Directory | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    [PSCustomObject]@{Name=$_.Name; SizeMB=[math]::Round($s,2)}
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize
