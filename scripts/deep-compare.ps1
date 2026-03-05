$ref = "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI3"
$emu = "C:\MIS\MacroquestEnvironments\CoOptUI-EMU-20260302"

$refFiles = Get-ChildItem $ref -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($ref.Length + 1)
    [PSCustomObject]@{ Rel=$rel; Size=$_.Length; Dir="CoOptUI3" }
}

$emuFiles = Get-ChildItem $emu -Recurse -File | ForEach-Object {
    $rel = $_.FullName.Substring($emu.Length + 1)
    [PSCustomObject]@{ Rel=$rel; Size=$_.Length; Dir="EMU" }
}

$refMap = @{}
foreach ($f in $refFiles) { $refMap[$f.Rel] = $f.Size }
$emuMap = @{}
foreach ($f in $emuFiles) { $emuMap[$f.Rel] = $f.Size }

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FILES IN CoOptUI3 BUT NOT IN EMU" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Cyan
$missing = @()
foreach ($key in ($refMap.Keys | Sort-Object)) {
    if (-not $emuMap.ContainsKey($key)) {
        $sizeMB = [math]::Round($refMap[$key]/1MB, 2)
        $missing += [PSCustomObject]@{ File=$key; SizeMB=$sizeMB }
    }
}
$missing | Format-Table -AutoSize
Write-Host "Total missing: $($missing.Count) files" -ForegroundColor Yellow

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "FILES IN EMU BUT NOT IN CoOptUI3" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
$extra = @()
foreach ($key in ($emuMap.Keys | Sort-Object)) {
    if (-not $refMap.ContainsKey($key)) {
        $sizeMB = [math]::Round($emuMap[$key]/1MB, 2)
        $extra += [PSCustomObject]@{ File=$key; SizeMB=$sizeMB }
    }
}
$extra | Format-Table -AutoSize
Write-Host "Total extra: $($extra.Count) files" -ForegroundColor Yellow

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SIZE DIFFERENCES (same file, different size)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
$diffs = @()
foreach ($key in ($refMap.Keys | Sort-Object)) {
    if ($emuMap.ContainsKey($key) -and $refMap[$key] -ne $emuMap[$key]) {
        $diffs += [PSCustomObject]@{
            File=$key
            RefKB=[math]::Round($refMap[$key]/1KB,1)
            EmuKB=[math]::Round($emuMap[$key]/1KB,1)
        }
    }
}
$diffs | Format-Table -AutoSize
Write-Host "Total size differences: $($diffs.Count) files" -ForegroundColor Yellow

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "TOP-LEVEL FOLDER SIZE COMPARISON" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$refDirs = Get-ChildItem $ref -Directory | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $c = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
    [PSCustomObject]@{Name=$_.Name; RefMB=[math]::Round($s,2); RefCount=$c}
}
$emuDirs = Get-ChildItem $emu -Directory | ForEach-Object {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $c = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
    [PSCustomObject]@{Name=$_.Name; EmuMB=[math]::Round($s,2); EmuCount=$c}
}

$allDirNames = ($refDirs.Name + $emuDirs.Name) | Sort-Object -Unique
foreach ($d in $allDirNames) {
    $r = $refDirs | Where-Object { $_.Name -eq $d }
    $e = $emuDirs | Where-Object { $_.Name -eq $d }
    $rMB = if ($r) { $r.RefMB } else { "-" }
    $rC  = if ($r) { $r.RefCount } else { "-" }
    $eMB = if ($e) { $e.EmuMB } else { "-" }
    $eC  = if ($e) { $e.EmuCount } else { "-" }
    Write-Host ("  {0,-20} CoOptUI3: {1,8} MB ({2,5} files)   EMU: {3,8} MB ({4,5} files)" -f $d, $rMB, $rC, $eMB, $eC)
}

# Root files
$refRoot = Get-ChildItem $ref -File
$emuRoot = Get-ChildItem $emu -File
$rRootMB = [math]::Round(($refRoot | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
$eRootMB = [math]::Round(($emuRoot | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
Write-Host ("  {0,-20} CoOptUI3: {1,8} MB ({2,5} files)   EMU: {3,8} MB ({4,5} files)" -f "(root files)", $rRootMB, $refRoot.Count, $eRootMB, $emuRoot.Count)
