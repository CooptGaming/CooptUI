# Bootstrap development environment for building the CoOpt UI plugin (Phase 1).
# Idempotent: re-running skips completed steps.
# See docs/plugin/dev_setup.md for full details.
#
# Usage: .\scripts\bootstrap_dev.ps1

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CoOptUIRepo = (Resolve-Path (Join-Path $scriptDir "..")).Path
$MQClonePath = "C:\MIS\MacroquestClone"
$VcpkgPath  = Join-Path $MQClonePath "contrib\vcpkg"
$BuildDir   = Join-Path $MQClonePath "build\solution"

function Write-Step { param([string]$Message) Write-Host "`n$Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "  $Message" -ForegroundColor Gray }

# ---------------------------------------------------------------------------
# 1. Visual Studio 2022 Build Tools
# ---------------------------------------------------------------------------
Write-Step "Checking Visual Studio 2022 Build Tools..."
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vsWhere -PathType Leaf)) {
    Write-Host "  Not found. Installing via winget (Build Tools + C++ workload + MFC)..." -ForegroundColor Yellow
    winget install Microsoft.VisualStudio.2022.BuildTools --accept-package-agreements --accept-source-agreements `
        --add Microsoft.VisualStudio.Workload.VCTools `
        --add Microsoft.VisualStudio.Component.VC.MFC.Latest
    if ($LASTEXITCODE -ne 0) { throw "winget install failed" }
    Write-Ok "Install requested. If build fails, run the script again or install VS 2022 manually."
} else {
    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VCPKG.CMake -property installationPath 2>$null
    if (-not $vsPath) {
        $vsPath = & $vsWhere -latest -products * -property installationPath 2>$null
    }
    if ($vsPath) { Write-Ok "Found: $vsPath" } else { Write-Ok "VS 2022 present (vswhere); ensure C++ and MFC are installed." }
}

# ---------------------------------------------------------------------------
# 2. Git
# ---------------------------------------------------------------------------
Write-Step "Checking Git..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "  Not found. Installing via winget..." -ForegroundColor Yellow
    winget install Git.Git --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install Git failed" }
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Ok "Git installed. You may need to restart the shell for 'git' to be on PATH."
} else {
    Write-Ok "Found: $(git --version)"
}

# ---------------------------------------------------------------------------
# 3. Clone MQ repo and submodules
# ---------------------------------------------------------------------------
Write-Step "Checking MacroQuest clone at $MQClonePath..."
if (-not (Test-Path -LiteralPath $MQClonePath -PathType Container)) {
    Write-Host "  Cloning macroquest/macroquest..." -ForegroundColor Yellow
    $parent = Split-Path -Parent $MQClonePath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    git clone https://github.com/macroquest/macroquest.git $MQClonePath
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
    Write-Ok "Clone done."
}
Set-Location $MQClonePath
if (-not (Test-Path -LiteralPath "src\eqlib\.git" -PathType Container)) {
    Write-Host "  Initializing submodules..." -ForegroundColor Yellow
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) { throw "git submodule update failed" }
    Write-Ok "Submodules initialized."
} else {
    Write-Ok "Repo and submodules already present."
}

# ---------------------------------------------------------------------------
# 4. Bootstrap vcpkg
# ---------------------------------------------------------------------------
Write-Step "Bootstrapping vcpkg..."
if (-not (Test-Path -LiteralPath (Join-Path $VcpkgPath "vcpkg.exe") -PathType Leaf)) {
    $bootstrap = Join-Path $VcpkgPath "bootstrap-vcpkg.bat"
    if (-not (Test-Path -LiteralPath $bootstrap -PathType Leaf)) { throw "vcpkg not found at $VcpkgPath" }
    & cmd /c "`"$bootstrap`""
    if ($LASTEXITCODE -ne 0) { throw "vcpkg bootstrap failed" }
    Write-Ok "vcpkg bootstrapped."
} else {
    Write-Ok "vcpkg already bootstrapped."
}

# ---------------------------------------------------------------------------
# 5. Set VCPKG_ROOT for this session and persist hint
# ---------------------------------------------------------------------------
$env:VCPKG_ROOT = $VcpkgPath
Write-Step "Environment"
Write-Ok "VCPKG_ROOT = $env:VCPKG_ROOT (current session only; add to your profile if needed)"

# ---------------------------------------------------------------------------
# 6. CMake configure
# ---------------------------------------------------------------------------
Write-Step "Configuring CMake (x64, custom plugins ON)..."
if (-not (Test-Path -LiteralPath (Join-Path $BuildDir "CMakeCache.txt") -PathType Leaf)) {
    cmake -B $BuildDir -G "Visual Studio 17 2022" -A x64 -DMQ_BUILD_CUSTOM_PLUGINS=ON
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
    Write-Ok "Configure done."
} else {
    Write-Ok "Already configured (delete build\solution to reconfigure)."
}

# ---------------------------------------------------------------------------
# 7. Next-step instructions
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Bootstrap complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Add plugin symlink (or copy) when building the plugin (Phase 2):" -ForegroundColor White
Write-Host "     New-Item -ItemType SymbolicLink -Path `"$MQClonePath\plugins\MQ2CoOptUI`" -Target `"$CoOptUIRepo\plugin\MQ2CoOptUI`" -Force" -ForegroundColor Gray
Write-Host "     Or: Copy-Item -Path `"$CoOptUIRepo\plugin\MQ2CoOptUI`" -Destination `"$MQClonePath\plugins\MQ2CoOptUI`" -Recurse" -ForegroundColor Gray
Write-Host "  2. Build MQ (and plugin):" -ForegroundColor White
Write-Host "     cd $MQClonePath" -ForegroundColor Gray
Write-Host "     cmake --build build\solution --config Release" -ForegroundColor Gray
Write-Host "  3. Or open the solution in VS 2022:" -ForegroundColor White
Write-Host "     $BuildDir\MacroQuest.sln" -ForegroundColor Gray
Write-Host "  4. Create a test distribution (from CoOpt UI repo):" -ForegroundColor White
Write-Host "     .\scripts\create_mq64_coopui_copy.ps1 -TargetDir `"C:\MIS\MQ64-CoopUI`"" -ForegroundColor Gray
Write-Host ""
Write-Host "Full details: docs/plugin/dev_setup.md" -ForegroundColor DarkGray
Write-Host ""
