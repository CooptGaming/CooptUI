# Phase 7 Pre-Flight Check (Simple Version)
Write-Host "`n=== Phase 7: Layout Integration Pre-Flight Check ===" -ForegroundColor Cyan

$passed = 0
$failed = 0

# Test 1: Files exist
Write-Host "`n[1] Checking files..." -ForegroundColor White
$initFile = "c:\MIS\E3NextAndMQNextBinary-main\lua\itemui\init.lua"
$layoutFile = "c:\MIS\E3NextAndMQNextBinary-main\lua\itemui\utils\layout.lua"

if (Test-Path $initFile) {
    Write-Host "  init.lua: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  init.lua: MISSING" -ForegroundColor Red
    $failed++
}

if (Test-Path $layoutFile) {
    Write-Host "  utils/layout.lua: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  utils/layout.lua: MISSING" -ForegroundColor Red
    $failed++
}

# Test 2: Check content
Write-Host "`n[2] Checking integration..." -ForegroundColor White
$content = Get-Content $initFile -Raw

if ($content -like "*require('itemui.utils.layout')*") {
    Write-Host "  require statement: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  require statement: MISSING" -ForegroundColor Red
    $failed++
}

if ($content -like "*layoutUtils.init*") {
    Write-Host "  layoutUtils.init(): OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  layoutUtils.init(): MISSING" -ForegroundColor Red
    $failed++
}

# Test 3: Count lines
Write-Host "`n[3] Checking file size..." -ForegroundColor White
$lineCount = (Get-Content $initFile).Count
Write-Host "  init.lua lines: $lineCount"

if ($lineCount -lt 5200) {
    Write-Host "  Size reduction: OK (was 5544)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  Size reduction: WARNING (expected < 5200)" -ForegroundColor Yellow
}

# Test 4: Count wrappers
Write-Host "`n[4] Checking wrappers..." -ForegroundColor White
$wrapperMatches = Select-String -Path $initFile -Pattern "layoutUtils\." -AllMatches
$wrapperCount = $wrapperMatches.Matches.Count
Write-Host "  layoutUtils calls: $wrapperCount"

if ($wrapperCount -ge 15) {
    Write-Host "  Wrapper count: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  Wrapper count: WARNING (expected >= 15)" -ForegroundColor Yellow
}

# Test 5: Context module (60 upvalue fix)
Write-Host "`n[5] Checking context module (upvalue limit fix)..." -ForegroundColor White
$contextFile = "c:\MIS\E3NextAndMQNextBinary-main\lua\itemui\context.lua"
if (Test-Path $contextFile) {
    Write-Host "  context.lua: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  context.lua: MISSING" -ForegroundColor Red
    $failed++
}
if ($content -like "*require('itemui.context')*") {
    Write-Host "  context.init/build: OK" -ForegroundColor Green
    $passed++
} else {
    Write-Host "  context require: MISSING" -ForegroundColor Red
    $failed++
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Passed: $passed / 8" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
}

if ($failed -eq 0) {
    Write-Host "`nStatus: READY FOR TESTING" -ForegroundColor Green
    Write-Host "`nNext steps:"
    Write-Host "  1. Start EverQuest"
    Write-Host "  2. Run: /lua run itemui"
    Write-Host "  3. Follow PHASE7_TESTING_GUIDE.md"
    Write-Host "`nUpvalue check: Set UPVALUE_DEBUG = true in init.lua (C table) to log upvalue counts on load."
    Write-Host "  Or run: /lua run itemui.upvalue_check  (in-game) to verify context.build() is under 60."
} else {
    Write-Host "`nStatus: ISSUES FOUND - FIX BEFORE TESTING" -ForegroundColor Red
}
