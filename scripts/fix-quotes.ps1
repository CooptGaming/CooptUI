# Fix build-and-deploy.ps1: replace Unicode curly quotes with ASCII, ensure UTF-8 BOM for PowerShell.
$path = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\build-and-deploy.ps1"
$bytes = [System.IO.File]::ReadAllBytes($path)
# Strip existing BOM so we can add it at the end consistently
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length-1)]
}
# Replace UTF-8 curly quotes (E2 80 9C / E2 80 9D) with ASCII 0x22
$out = New-Object System.Collections.Generic.List[byte]
$i = 0
while ($i -lt $bytes.Length) {
    if ($i -le $bytes.Length - 3 -and $bytes[$i] -eq 0xE2 -and $bytes[$i+1] -eq 0x80 -and ($bytes[$i+2] -eq 0x9C -or $bytes[$i+2] -eq 0x9D)) {
        $out.Add(0x22)
        $i += 3
    } else {
        $out.Add($bytes[$i])
        $i++
    }
}
# Add UTF-8 BOM so PowerShell parses the script as UTF-8 (avoids "Missing argument" parse errors)
$withBom = New-Object System.Collections.Generic.List[byte]
$withBom.Add(0xEF); $withBom.Add(0xBB); $withBom.Add(0xBF)
$withBom.AddRange($out)
[System.IO.File]::WriteAllBytes($path, $withBom)
Write-Host "build-and-deploy.ps1: curly quotes replaced (if any), UTF-8 BOM ensured."
