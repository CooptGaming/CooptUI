<#
.SYNOPSIS
    Run the CoOpt UI regression tests.

.DESCRIPTION
    Runs every test under scripts/tests and reports a single pass/fail. Exits non-zero if
    any test fails, so it can gate a release.

    The Lua tests must run on LuaJIT (what MQ2Lua is), not Lua 5.4. By default the script
    looks for the vcpkg LuaJIT inside a Build-Smart output tree; pass -LuaJit to override.
    If no LuaJIT is found the Lua tests are SKIPPED and reported as skipped - they are never
    silently counted as passing.

.PARAMETER LuaJit
    Path to luajit.exe.

.PARAMETER All
    Also run the LuaJIT compile sweep over lua/ (catches the 60-upvalue limit that luacheck
    and Lua 5.4 both miss).

.EXAMPLE
    .\scripts\tests\run-tests.ps1
.EXAMPLE
    .\scripts\tests\run-tests.ps1 -LuaJit "C:\tools\luajit.exe" -All
#>
[CmdletBinding()]
param(
    [string]$LuaJit,
    [switch]$All
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$testsDir = $PSScriptRoot

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$Name, [string]$Status, [string]$Detail = '') {
    $results.Add([PSCustomObject]@{ Test = $Name; Status = $Status; Detail = $Detail })
}

# --- Locate LuaJIT -----------------------------------------------------------------
if (-not $LuaJit) {
    # Build-Smart clones MacroQuest into <OutputDir>\.mq-source, and vcpkg drops the LuaJIT
    # that MQ links at this path inside it. No location is hardcoded: set COOPT_LUAJIT, pass
    # -LuaJit, or let this find any Build-Smart output tree one level under a drive root.
    $relative = '.mq-source\macroquest\build\solution\vcpkg_installed\x86-windows-static\tools\luajit\luajit.exe'
    $candidates = @()
    if ($env:COOPT_LUAJIT) { $candidates += $env:COOPT_LUAJIT }
    $candidates += (Get-Command luajit -ErrorAction SilentlyContinue).Source
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        # Depth 2: a Build-Smart OutputDir is typically <drive>\<folder>\<deploy> (it is kept
        # outside the repo on purpose), so one level is not enough.
        $roots = Get-ChildItem -Path $drive.Root -Directory -ErrorAction SilentlyContinue
        $candidates += $roots | ForEach-Object { Join-Path $_.FullName $relative }
        $candidates += $roots | ForEach-Object {
            Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue
        } | ForEach-Object { Join-Path $_.FullName $relative }
    }
    $LuaJit = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if ($LuaJit -and -not (Test-Path $LuaJit)) { $LuaJit = $null }

# --- Python tests ------------------------------------------------------------------
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
foreach ($t in (Get-ChildItem $testsDir -Filter 'test_*.py' | Sort-Object Name)) {
    if (-not $py) { Add-Result $t.Name 'SKIPPED' 'python not on PATH'; continue }
    Push-Location $repoRoot
    $out = & $py $t.FullName 2>&1
    $code = $LASTEXITCODE
    Pop-Location
    if ($code -eq 0) { Add-Result $t.Name 'PASSED' }
    else { Add-Result $t.Name 'FAILED' (($out | Select-Object -Last 5) -join ' | ') }
}

# --- Lua tests ---------------------------------------------------------------------
foreach ($t in (Get-ChildItem $testsDir -Filter 'test_*.lua' | Sort-Object Name)) {
    if (-not $LuaJit) { Add-Result $t.Name 'SKIPPED' 'luajit.exe not found - pass -LuaJit'; continue }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("coopt_test_" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory $tmp | Out-Null
    try {
        $env:COOPT_REPO = $repoRoot
        $env:COOPT_TMP = $tmp
        $out = & $LuaJit $t.FullName 2>&1
        $code = $LASTEXITCODE
        if ($code -eq 0) { Add-Result $t.Name 'PASSED' }
        else { Add-Result $t.Name 'FAILED' (($out | Select-String -Pattern 'FAIL') -join ' | ') }
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- Optional: LuaJIT compile sweep -------------------------------------------------
if ($All) {
    if (-not $LuaJit) { Add-Result 'luajit-compile-sweep' 'SKIPPED' 'luajit.exe not found' }
    else {
        $failed = @()
        Get-ChildItem (Join-Path $repoRoot 'lua') -Recurse -Filter *.lua | ForEach-Object {
            $f = $_.FullName
            $out = & $LuaJit -e "local f, err = loadfile([[$f]]); if not f then io.stderr:write(err) os.exit(1) end" 2>&1
            if ($LASTEXITCODE -ne 0) { $failed += "$($_.Name): $out" }
        }
        if ($failed.Count -eq 0) { Add-Result 'luajit-compile-sweep' 'PASSED' }
        else { Add-Result 'luajit-compile-sweep' 'FAILED' ($failed -join ' | ') }
    }
}

# --- Report -------------------------------------------------------------------------
''
$results | Format-Table -AutoSize
$failedCount  = ($results | Where-Object Status -eq 'FAILED').Count
$skippedCount = ($results | Where-Object Status -eq 'SKIPPED').Count
$passedCount  = ($results | Where-Object Status -eq 'PASSED').Count
"$passedCount passed, $failedCount failed, $skippedCount skipped"
if ($skippedCount -gt 0) {
    Write-Warning "$skippedCount test(s) were SKIPPED - they did not pass, they did not run."
}
# A skip exits non-zero on purpose. This is a release gate: "I could not run" must not look
# the same as "everything passed". Install the missing prerequisite, or pass -LuaJit.
exit ([int](($failedCount -gt 0) -or ($skippedCount -gt 0)))
