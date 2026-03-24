<#
.SYNOPSIS
    Intelligent build and deploy script for CoOpt UI.
.DESCRIPTION
    Single entry point for all CoOpt UI build/deploy/release operations.
    Uses SHA256 hashing and GitHub API to detect changes and only rebuild what's needed.

    Usage:
      .\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy"                          # Full EMU bundle
      .\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy" -Target CoOptOnly        # Lua/macros only
      .\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy" -Force                   # Rebuild everything
      .\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy" -Release                 # Build + release
      .\Build-Smart.ps1 -OutputDir dist -Target All -Force -CI             # CI mode
#>

param(
    [Parameter(Mandatory)]
    [string]$OutputDir,

    [ValidateSet('FullBundle', 'CoOptOnly', 'PluginOnly', 'All')]
    [string]$Target = 'FullBundle',

    [string]$Version = '',
    [switch]$Force,
    [switch]$SkipPlugin,
    [string]$MQSourceRoot = '',
    [string]$CMakePath = '',
    [switch]$Release,
    [switch]$DryRun,
    [switch]$CI
)

$ErrorActionPreference = 'Stop'
$BuildStartTime = Get-Date

# CI implies Force (always clean build)
if ($CI) { $Force = $true }

# ======================================================================
# Region 1: Utilities
# ======================================================================

function Write-Stage { param([string]$Name); Write-Host ''; Write-Host "--- $Name ---" -ForegroundColor Yellow }
function Write-Ok { param([string]$Msg); Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg); Write-Host "  [SKIP] $Msg" -ForegroundColor DarkGray }
function Write-Info { param([string]$Msg); Write-Host "  $Msg" }

function Assert-FileExists {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Error "[FATAL] Required file missing: $Label -- Expected at: $Path"
    }
}

function Get-RepoRoot {
    $dir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    return $dir.ToString()
}

function Read-CoOptVersion {
    param([string]$RepoRoot)
    $versionLua = Join-Path $RepoRoot 'lua\coopui\version.lua'
    if (-not (Test-Path $versionLua)) {
        Write-Error "lua/coopui/version.lua not found. Cannot determine version."
    }
    $content = Get-Content $versionLua -Raw
    if ($content -match 'PACKAGE\s*=\s*"([^"]+)"') {
        return $Matches[1]
    }
    Write-Error "Could not parse PACKAGE version from lua/coopui/version.lua."
}

# ======================================================================
# Region 2: State File Management
# ======================================================================

function Get-BuildStatePath {
    param([string]$OutputDir)
    return Join-Path $OutputDir '.build_state.json'
}

function Read-BuildState {
    param([string]$OutputDir)
    $path = Get-BuildStatePath $OutputDir
    if (Test-Path $path) {
        try {
            return Get-Content $path -Raw | ConvertFrom-Json
        } catch {
            Write-Warning "Corrupt .build_state.json — starting fresh."
        }
    }
    # Return empty state object
    return [PSCustomObject]@{
        lastBuild  = $null
        fullBuild  = [PSCustomObject]@{ sourceHash = ''; mqBinDir = '' }
        e3next     = [PSCustomObject]@{ sourceHash = ''; outputDir = '' }
        plugin     = [PSCustomObject]@{ sourceHash = ''; mqRef = ''; dllPath = '' }
        cooptui    = [PSCustomObject]@{ sourceHash = '' }
        version    = ''
    }
}

function Save-BuildState {
    param([string]$OutputDir, [PSCustomObject]$State)
    $State.lastBuild = (Get-Date).ToString('o')
    $path = Get-BuildStatePath $OutputDir
    $State | ConvertTo-Json -Depth 4 | Set-Content $path -Encoding UTF8
}

# ======================================================================
# Region 3: Hash Computation
# ======================================================================

function Get-FileContentHash {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
}

function Get-DirectoryHash {
    param([string]$BasePath, [string[]]$Include, [string[]]$Exclude = @())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $allHashes = [System.Collections.Generic.List[string]]::new()
        foreach ($pattern in $Include) {
            $files = Get-ChildItem -Path $BasePath -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                $relPath = $f.FullName.Substring($BasePath.Length).TrimStart('\', '/').Replace('\', '/')
                # Check exclusions
                $skip = $false
                foreach ($ex in $Exclude) {
                    if ($relPath -like $ex) { $skip = $true; break }
                }
                if ($skip) { continue }
                $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                $hash = $sha.ComputeHash($bytes)
                $allHashes.Add("$relPath`:$([BitConverter]::ToString($hash) -replace '-','')")
            }
        }
        $allHashes.Sort()
        if ($allHashes.Count -eq 0) { return '' }
        $combined = $allHashes -join '|'
        $combinedBytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
        return ([BitConverter]::ToString($sha.ComputeHash($combinedBytes)) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
}

function Get-MultiPathHash {
    param([hashtable[]]$Paths)
    # Each entry: @{ Path = "..."; Include = @("*.lua"); Exclude = @("docs/*") }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $allHashes = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $Paths) {
            $basePath = $entry.Path
            if (-not (Test-Path $basePath)) { continue }

            if ((Get-Item $basePath).PSIsContainer) {
                $includes = if ($entry.Include) { $entry.Include } else { @('*') }
                $excludes = if ($entry.Exclude) { $entry.Exclude } else { @() }
                $files = Get-ChildItem -Path $basePath -Recurse -File -ErrorAction SilentlyContinue
                foreach ($f in $files) {
                    $relPath = $f.FullName.Substring($basePath.Length).TrimStart('\', '/').Replace('\', '/')
                    # Check include patterns
                    $matched = $false
                    foreach ($inc in $includes) {
                        if ($f.Name -like $inc -or $relPath -like $inc) { $matched = $true; break }
                    }
                    if (-not $matched) { continue }
                    # Check exclude patterns
                    $skip = $false
                    foreach ($ex in $excludes) {
                        if ($relPath -like $ex) { $skip = $true; break }
                    }
                    if ($skip) { continue }
                    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
                    $hash = $sha.ComputeHash($bytes)
                    $allHashes.Add("$relPath`:$([BitConverter]::ToString($hash) -replace '-','')")
                }
            } else {
                # Single file
                $bytes = [System.IO.File]::ReadAllBytes($basePath)
                $hash = $sha.ComputeHash($bytes)
                $name = [System.IO.Path]::GetFileName($basePath)
                $allHashes.Add("$name`:$([BitConverter]::ToString($hash) -replace '-','')")
            }
        }
        $allHashes.Sort()
        if ($allHashes.Count -eq 0) { return '' }
        $combined = $allHashes -join '|'
        $combinedBytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
        return ([BitConverter]::ToString($sha.ComputeHash($combinedBytes)) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
}

function Get-PluginSourceHash {
    param([string]$RepoRoot)
    return Get-MultiPathHash @(
        @{ Path = (Join-Path $RepoRoot 'plugin\MQ2CoOptUI'); Include = @('*.cpp', '*.h', '*.txt') }
        @{ Path = (Join-Path $RepoRoot 'plugin\MQ_COMMIT_SHA.txt') }
        @{ Path = (Join-Path $RepoRoot 'scripts\apply-build-gotchas.ps1') }
    )
}

function Get-CoOptUISourceHash {
    param([string]$RepoRoot)
    return Get-MultiPathHash @(
        @{ Path = (Join-Path $RepoRoot 'lua\itemui');        Include = @('*.lua'); Exclude = @('docs/*', 'upvalue_check.lua') }
        @{ Path = (Join-Path $RepoRoot 'lua\coopui');        Include = @('*.lua') }
        @{ Path = (Join-Path $RepoRoot 'lua\scripttracker'); Include = @('*.lua'); Exclude = @('scripttracker.ini') }
        @{ Path = (Join-Path $RepoRoot 'lua\mq\ItemUtils.lua') }
        @{ Path = (Join-Path $RepoRoot 'Macros\sell.mac') }
        @{ Path = (Join-Path $RepoRoot 'Macros\loot.mac') }
        @{ Path = (Join-Path $RepoRoot 'Macros\shared_config'); Include = @('*.mac') }
        @{ Path = (Join-Path $RepoRoot 'config_templates');  Include = @('*.ini') }
        @{ Path = (Join-Path $RepoRoot 'resources\UIFiles\Default'); Include = @('*') }
        @{ Path = (Join-Path $RepoRoot 'config\MQ2CustomBinds.txt') }
        @{ Path = (Join-Path $RepoRoot 'DEPLOY.md') }
        @{ Path = (Join-Path $RepoRoot 'CHANGELOG.md') }
        @{ Path = (Join-Path $RepoRoot 'Install-CoOptUI.ps1') }
    )
}

# ======================================================================
# Region 4: From-Source Build Helpers (replaces prebuild download)
# ======================================================================

# Get the latest commit SHA for a GitHub repo/branch (for freshness checks)
function Get-GitHubCommitSha {
    param([string]$Repo, [string]$Branch = 'master')
    $headers = @{ 'User-Agent' = 'CoOptUI-Build' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }
    try {
        $resp = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits/$Branch" `
            -Headers $headers -Method Get -ErrorAction Stop
        return $resp.sha
    } catch {
        Write-Warning "  GitHub API check for $Repo failed: $($_.Exception.Message)"
        return $null
    }
}

# Get the local HEAD SHA for a git clone
function Get-LocalHeadSha {
    param([string]$ClonePath)
    if (-not (Test-Path $ClonePath)) { return '' }
    $sha = git -C $ClonePath rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return $sha.Trim()
}

# Build E3Next C# solution
function Build-E3Next {
    param([string]$E3NextDir, [string]$Configuration = 'Release')

    $slnFiles = Get-ChildItem $E3NextDir -Filter '*.sln' -Recurse -Depth 2 | Select-Object -First 1
    if (-not $slnFiles) {
        Write-Warning "No .sln file found in $E3NextDir — E3Next build skipped."
        return $null
    }
    Write-Info "Building E3Next: $($slnFiles.Name)"

    # Find MSBuild via vswhere
    $msbuild = $null
    foreach ($pf in @("${env:ProgramFiles(x86)}", "${env:ProgramFiles}")) {
        $found = & "$pf\Microsoft Visual Studio\Installer\vswhere.exe" `
            -latest -requires Microsoft.Component.MSBuild `
            -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
        if ($found) { $msbuild = $found; break }
    }

    if (-not $msbuild) {
        Write-Warning "MSBuild not found. Install VS 2022 with .NET desktop workload."
        return $null
    }

    # Restore NuGet (E3Next uses packages.config)
    $nugetExe = 'C:\MIS\tools\nuget.exe'
    if (-not (Test-Path $nugetExe)) {
        $nugetExe = (Get-Command nuget.exe -ErrorAction SilentlyContinue).Source
    }
    if ($nugetExe -and (Test-Path $nugetExe)) {
        Write-Info 'Restoring NuGet packages...'
        # Pipe to Write-Host so output doesn't pollute the function return value
        & $nugetExe restore $slnFiles.FullName -NonInteractive -Verbosity quiet 2>&1 | ForEach-Object { Write-Host "  $_" }
    }

    # Pipe to Write-Host so MSBuild output doesn't pollute the function return value
    & $msbuild $slnFiles.FullName /p:Configuration=$Configuration "/p:Platform=Any CPU" /v:minimal 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "E3Next build failed. You may need .NET Framework 4.8 Developer Pack."
        return $null
    }

    # Find E3Next output DLL
    $candidates = @(
        (Join-Path $E3NextDir "E3Next\bin\$Configuration"),
        (Join-Path $E3NextDir "bin\$Configuration"),
        (Join-Path $E3NextDir "E3Next\bin\Release")
    )
    foreach ($c in $candidates) {
        if ((Test-Path $c) -and ((Get-ChildItem $c -Filter 'E3Next.dll' -EA SilentlyContinue) -or
                                  (Get-ChildItem $c -Filter 'E3.dll' -EA SilentlyContinue))) {
            Write-Ok "E3Next built: $c"
            return $c
        }
    }
    # Recursive search fallback
    $e3Dll = Get-ChildItem $E3NextDir -Filter 'E3.dll' -Recurse -Depth 5 | Select-Object -First 1
    if (-not $e3Dll) { $e3Dll = Get-ChildItem $E3NextDir -Filter 'E3Next.dll' -Recurse -Depth 5 | Select-Object -First 1 }
    if ($e3Dll) {
        Write-Ok "E3Next built: $($e3Dll.DirectoryName)"
        return $e3Dll.DirectoryName
    }

    Write-Warning 'E3Next build produced no output DLL.'
    return $null
}

# Build full MacroQuest (all targets: MQ2Main, MQ2Mono, MQ2CoOptUI, plugins, launcher)
function Build-MQFull {
    param(
        [string]$MQClone,
        [string]$CMakeExe,
        [string]$RepoRoot,
        [switch]$PluginOnly
    )

    $MQBuildDir = Join-Path $MQClone 'build\solution'
    $origPath = $env:Path

    # CRITICAL: Remove any other CMake from PATH so vcpkg's internal builds use 3.30.
    # vcpkg spawns cmake subprocesses (e.g. for bzip2 via Ninja) and discovers cmake
    # from PATH. CMake 4.x breaks old portfiles (cmake_minimum_required < 3.5 rejected).
    $cmake330Dir = (Split-Path $CMakeExe -Parent).TrimEnd('\')
    $filteredPath = ($origPath -split ';' | Where-Object {
        $dir = $_.TrimEnd('\')
        ($dir -eq $cmake330Dir) -or ($dir -notmatch '[Cc][Mm]ake' -and -not (Test-Path (Join-Path $dir 'cmake.exe')))
    }) -join ';'
    $env:Path = "$cmake330Dir;$filteredPath"
    Write-Info "PATH: CMake 3.30 at front, other cmake dirs removed"

    $env:VCPKG_ROOT = Join-Path $MQClone 'contrib\vcpkg'
    $env:VCPKG_TARGET_TRIPLET = 'x86-windows-static'
    $env:VCPKG_BUILD_TYPE = 'release'

    try {
        # --- Helper: run cmake configure ---
        $configureArgs = @(
            '-B', $MQBuildDir, '-S', $MQClone,
            '-G', 'Visual Studio 17 2022', '-A', 'Win32',
            '-DVCPKG_TARGET_TRIPLET=x86-windows-static',
            '-DVCPKG_BUILD_TYPE=release',
            '-DMQ_BUILD_CUSTOM_PLUGINS=ON',
            '-DMQ_BUILD_LAUNCHER=ON',
            '-DMQ_REGENERATE_SOLUTION=OFF'
        )

        # Check if existing cache is stale (missing MQ2CoOptUI target)
        $cacheFile = Join-Path $MQBuildDir 'CMakeCache.txt'
        $pluginVcxproj = Get-ChildItem $MQBuildDir -Filter 'MQ2CoOptUI.vcxproj' -Recurse -EA SilentlyContinue | Select-Object -First 1
        $needsConfigure = (-not (Test-Path $cacheFile)) -or (-not $pluginVcxproj)

        if ($needsConfigure -and (Test-Path $cacheFile)) {
            Write-Info 'Stale CMake cache (MQ2CoOptUI target missing) — removing build dir for clean configure...'
            Remove-Item $MQBuildDir -Recurse -Force
        }

        if ($needsConfigure) {
            # Clean vcpkg buildtrees that may have cached CMake 4.x paths from prior runs
            $vcpkgBuildtrees = Join-Path $MQClone 'contrib\vcpkg\buildtrees'
            if (Test-Path $vcpkgBuildtrees) {
                Write-Info 'Cleaning vcpkg buildtrees (ensure CMake 3.30 used)...'
                Remove-Item $vcpkgBuildtrees -Recurse -Force
            }

            # Pass 1: configure — expected to fail if crashpad not yet installed.
            # vcpkg installs packages (including crashpad) during this pass, then
            # the configure itself errors on the duplicate crashpad target. That's OK.
            Write-Info 'Configuring CMake pass 1/2 (installs vcpkg deps, may warn on crashpad)...'
            & $CMakeExe @configureArgs 2>&1 | ForEach-Object {
                # Suppress the expected crashpad duplicate-target error, show everything else
                if ($_ -notmatch 'crashpad.*already exists|cannot create.*crashpad') {
                    Write-Host "  $_"
                }
            }
            # Don't check $LASTEXITCODE here — crashpad error is expected on first pass
        }

        # --- Apply post-configure patches (always idempotent) ---
        $needReconfigure = $false

        # Crashpad duplicate target guard
        $crashpadConfig = Join-Path $MQBuildDir 'vcpkg_installed\x86-windows-static\share\crashpad\crashpadConfig.cmake'
        if (Test-Path $crashpadConfig) {
            $content = Get-Content $crashpadConfig -Raw
            if ($content -match 'add_library\(crashpad INTERFACE\)' -and $content -notmatch 'if\s*\(\s*NOT\s+TARGET\s+crashpad\s*\)') {
                $content = $content -replace 'add_library\(crashpad INTERFACE\)', "if(NOT TARGET crashpad)`nadd_library(crashpad INTERFACE)"
                $content = $content.TrimEnd() + "`nendif()`n"
                Set-Content $crashpadConfig $content -NoNewline
                Write-Info 'Patched crashpad (duplicate target guard)'
                $needReconfigure = $true
            }
            $content = Get-Content $crashpadConfig -Raw
            if ($content -match 'find_library\(_LIB \$\{LIB_NAME\}\)' -and $content -notmatch 'PATHS.*_IMPORT_PREFIX.*/lib') {
                $content = $content -replace 'find_library\(_LIB \$\{LIB_NAME\}\)', 'find_library(_LIB ${LIB_NAME} PATHS "${_IMPORT_PREFIX}/lib" NO_DEFAULT_PATH)'
                Set-Content $crashpadConfig $content -NoNewline
                Write-Info 'Patched crashpad (release libs only)'
                $needReconfigure = $true
            }
        } elseif ($needsConfigure) {
            # crashpadConfig.cmake wasn't created — first pass had a different failure
            Write-Error 'CMake pass 1 failed (crashpadConfig.cmake not found). Check the output above.'
        }

        # Apply build gotchas to build dir (Fix 19, etc.)
        $gotchasScript = Join-Path $RepoRoot 'scripts\apply-build-gotchas.ps1'
        if (Test-Path $gotchasScript) {
            & $gotchasScript -MQClone $MQClone -MQBuildDir $MQBuildDir 2>$null
        }

        if ($needReconfigure -or $needsConfigure) {
            # Pass 2: clean configure with patches applied — must succeed
            Write-Info 'Configuring CMake pass 2/2 (with patches applied)...'
            # Pipe to Write-Host so output goes to console, not captured into return value
            & $CMakeExe @configureArgs 2>&1 | ForEach-Object { Write-Host "  $_" }
            if ($LASTEXITCODE -ne 0) { Write-Error 'CMake configure pass 2 failed' }
        }

        # --- Validate MQ2CoOptUI target exists before building ---
        $pluginVcxproj = Get-ChildItem $MQBuildDir -Filter 'MQ2CoOptUI.vcxproj' -Recurse -EA SilentlyContinue | Select-Object -First 1
        if (-not $pluginVcxproj) {
            Write-Error "CMake did not generate MQ2CoOptUI target. Check that plugins/MQ2CoOptUI symlink exists and contains CMakeLists.txt."
        }

        # --- Build ---
        # Pipe all cmake --build output to Write-Host so it's not captured into the return value
        if ($PluginOnly) {
            Write-Info 'Building MQ2CoOptUI only (Release Win32)...'
            & $CMakeExe --build $MQBuildDir --config Release --target MQ2CoOptUI --parallel `
                -- /p:ContinueOnError=true 2>&1 | ForEach-Object { Write-Host "  $_" }
        } else {
            Write-Info 'Building full MacroQuest (Release Win32)...'
            & $CMakeExe --build $MQBuildDir --config Release --parallel `
                -- /p:ContinueOnError=true 2>&1 | ForEach-Object { Write-Host "  $_" }
        }

        $MQBinDir = Join-Path $MQBuildDir 'bin\release'

        # Validate the plugin DLL at minimum
        $pluginDll = Join-Path $MQBinDir 'plugins\MQ2CoOptUI.dll'
        if (-not (Test-Path $pluginDll)) {
            Write-Error "Build failed — MQ2CoOptUI.dll not found at $pluginDll"
        }
        Validate-DllArchitecture $pluginDll | Out-Null

        Write-Ok "MacroQuest built: $MQBinDir"
        return $MQBinDir
    } finally {
        $env:Path = $origPath
    }
}

# ======================================================================
# Region 5: MQ Source Environment
# ======================================================================

function Ensure-MQSourceEnv {
    param(
        [string]$MQSourceRoot,
        [string]$RepoRoot,
        [string]$MQRef
    )

    $MQClone = Join-Path $MQSourceRoot 'macroquest'
    $PluginsDir = Join-Path $MQClone 'plugins'

    if (-not (Test-Path $MQSourceRoot)) {
        New-Item -ItemType Directory -Path $MQSourceRoot -Force | Out-Null
    }

    # --- MacroQuest ---
    if (-not (Test-Path $MQClone)) {
        Write-Info 'Cloning MacroQuest (first-time setup, may take several minutes)...'
        git clone --branch master https://github.com/macroquest/macroquest.git $MQClone
        if ($LASTEXITCODE -ne 0) { Write-Error 'git clone failed for MacroQuest' }
    } else {
        Write-Info 'MacroQuest clone exists — pulling latest...'
        git -C $MQClone pull --ff-only 2>$null
    }

    # Submodules + eqlib EMU branch
    Write-Info 'Updating submodules...'
    Push-Location $MQClone
    try {
        git submodule update --init --recursive 2>$null
        $eqlibDir = Join-Path $MQClone 'src\eqlib'
        if (Test-Path $eqlibDir) {
            git -C $eqlibDir checkout emu 2>$null
            git -C $eqlibDir pull --ff-only 2>$null
        }
    } finally { Pop-Location }

    # Checkout specific MQ ref
    if ($MQRef -and $MQRef -ne 'master') {
        Write-Info "Checking out MQ ref: $MQRef"
        git -C $MQClone fetch origin $MQRef --quiet 2>$null
        git -C $MQClone checkout $MQRef 2>$null
    }

    # --- MQ2Mono (plugin inside MQ) ---
    $MQ2MonoDir = Join-Path $PluginsDir 'MQ2Mono'
    if (-not (Test-Path $MQ2MonoDir)) {
        Write-Info 'Cloning MQ2Mono...'
        git clone --recursive https://github.com/RekkasGit/MQ2Mono.git $MQ2MonoDir
        if ($LASTEXITCODE -ne 0) { Write-Warning 'MQ2Mono clone failed' }
    } else {
        git -C $MQ2MonoDir pull --ff-only 2>$null
    }
    # Ensure Mono headers (needed for MQ2Mono compilation)
    if (Test-Path $MQ2MonoDir) {
        Push-Location $MQ2MonoDir
        try { git submodule update --init --recursive 2>$null } finally { Pop-Location }
    }

    # --- MQ2Mono-Framework32 (Mono runtime: mono-2.0-sgen.dll + resources/Mono/32bit) ---
    $MonoFwDir = Join-Path $MQSourceRoot 'MQ2Mono-Framework32'
    if (-not (Test-Path $MonoFwDir)) {
        Write-Info 'Cloning MQ2Mono-Framework32 (Mono runtime for EMU 32-bit)...'
        git clone --depth 1 https://github.com/RekkasGit/MQ2Mono-Framework32.git $MonoFwDir
        if ($LASTEXITCODE -ne 0) { Write-Warning 'MQ2Mono-Framework32 clone failed' }
    } else {
        git -C $MonoFwDir pull --ff-only 2>$null
    }

    # --- E3Next (C# solution) ---
    $E3NextDir = Join-Path $MQSourceRoot 'E3Next'
    if (-not (Test-Path $E3NextDir)) {
        Write-Info 'Cloning E3Next...'
        git clone https://github.com/RekkasGit/E3Next.git $E3NextDir
        if ($LASTEXITCODE -ne 0) { Write-Warning 'E3Next clone failed' }
    } else {
        git -C $E3NextDir pull --ff-only 2>$null
    }

    # --- MQ2CoOptUI symlink/junction ---
    $MQ2CoOptUILink = Join-Path $PluginsDir 'MQ2CoOptUI'
    $PluginSource = Join-Path $RepoRoot 'plugin\MQ2CoOptUI'
    if (-not (Test-Path $MQ2CoOptUILink)) {
        Write-Info 'Creating plugin symlink...'
        try {
            New-Item -ItemType SymbolicLink -Path $MQ2CoOptUILink -Target $PluginSource -Force | Out-Null
        } catch {
            try {
                New-Item -ItemType Junction -Path $MQ2CoOptUILink -Target $PluginSource -Force | Out-Null
            } catch {
                Write-Error "Could not create symlink/junction at $MQ2CoOptUILink. Enable Developer Mode or run as admin."
            }
        }
    }

    # --- Bootstrap vcpkg ---
    $vcpkgExe = Join-Path $MQClone 'contrib\vcpkg\vcpkg.exe'
    if (-not (Test-Path $vcpkgExe)) {
        Write-Info 'Bootstrapping vcpkg...'
        $bootstrapBat = Join-Path $MQClone 'contrib\vcpkg\bootstrap-vcpkg.bat'
        if (Test-Path $bootstrapBat) { & cmd /c $bootstrapBat }
    }

    # --- Apply build gotchas (idempotent patches to MQ source) ---
    $gotchasScript = Join-Path $RepoRoot 'scripts\apply-build-gotchas.ps1'
    if (Test-Path $gotchasScript) {
        Write-Info 'Applying build gotchas to MQ clone...'
        & $gotchasScript -MQClone $MQClone
    }

    Write-Ok "Source environment ready at $MQSourceRoot"
    return @{
        MQClone    = $MQClone
        E3NextDir  = $E3NextDir
        MonoFwDir  = $MonoFwDir
    }
}

# ======================================================================
# Region 6: Plugin Build
# ======================================================================

function Find-CMake330 {
    param([string]$Hint)

    # Check hint first
    if ($Hint) {
        $exe = if ($Hint -like '*.exe') { $Hint } else { Join-Path $Hint 'bin\cmake.exe' }
        if (Test-Path $exe) {
            $ver = & $exe --version 2>$null | Select-Object -First 1
            if ($ver -match '3\.\d+') { return $exe }
        }
    }

    # Search common locations
    foreach ($candidate in @(
        'C:\MIS\CMake-3.30\bin\cmake.exe',
        'C:\Program Files\CMake\bin\cmake.exe',
        'C:\Program Files (x86)\CMake\bin\cmake.exe'
    )) {
        if (Test-Path $candidate) {
            $ver = & $candidate --version 2>$null | Select-Object -First 1
            if ($ver -match '3\.\d+' -and $ver -notmatch '4\.\d+') { return $candidate }
        }
    }

    # Check PATH
    $pathCmake = (Get-Command cmake.exe -ErrorAction SilentlyContinue).Source
    if ($pathCmake) {
        $ver = & $pathCmake --version 2>$null | Select-Object -First 1
        if ($ver -match '3\.\d+' -and $ver -notmatch '4\.\d+') { return $pathCmake }
        Write-Warning "Found cmake on PATH but version is $ver (need 3.30, not 4.x)"
    }

    return $null
}

function Validate-DllArchitecture {
    param([string]$DllPath)
    if (-not (Test-Path $DllPath)) { return $false }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($DllPath)
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
        if ($machine -eq 0x14C) { return $true }   # x86 (Win32)
        if ($machine -eq 0x8664) {
            Write-Error '[FATAL] MQ2CoOptUI.dll is 64-bit (x64). E3Next requires 32-bit (Win32/x86).'
        }
        Write-Warning "Unknown PE machine type 0x$($machine.ToString('X4')) in $DllPath"
        return $false
    } catch {
        Write-Warning "Could not validate DLL architecture: $_"
        return $false
    }
}

function Test-PluginBuildNeeded {
    param([PSCustomObject]$State, [string]$CurrentHash)
    return ($State.plugin.sourceHash -ne $CurrentHash)
}

# Get combined source hash for all repos (MQ + MQ2Mono + E3Next + plugin + gotchas)
function Get-FullBuildSourceHash {
    param([string]$RepoRoot, [string]$MQSourceRoot)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $parts = @()

        # MQ HEAD
        $mqHead = Get-LocalHeadSha (Join-Path $MQSourceRoot 'macroquest')
        $parts += "mq:$mqHead"

        # MQ2Mono HEAD
        $monoHead = Get-LocalHeadSha (Join-Path $MQSourceRoot 'macroquest\plugins\MQ2Mono')
        $parts += "mq2mono:$monoHead"

        # E3Next HEAD
        $e3Head = Get-LocalHeadSha (Join-Path $MQSourceRoot 'E3Next')
        $parts += "e3next:$e3Head"

        # MQ2Mono-Framework32 HEAD
        $fwHead = Get-LocalHeadSha (Join-Path $MQSourceRoot 'MQ2Mono-Framework32')
        $parts += "monofw:$fwHead"

        # Plugin source hash (our C++ code)
        $pluginHash = Get-PluginSourceHash $RepoRoot
        $parts += "plugin:$pluginHash"

        $combined = $parts -join '|'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
    } finally { $sha.Dispose() }
}

# ======================================================================
# Region 7: CoOptUI File Assembly
# ======================================================================

function Copy-CoOptUIFiles {
    param([string]$StagingDir, [string]$RepoRoot)

    # Lua modules
    $luaDst = Join-Path $StagingDir 'lua'
    New-Item -ItemType Directory -Path $luaDst -Force | Out-Null

    foreach ($mod in @('itemui', 'coopui', 'scripttracker')) {
        $src = Join-Path $RepoRoot "lua\$mod"
        Assert-FileExists $src "lua\$mod"
        Copy-Item $src -Destination (Join-Path $luaDst $mod) -Recurse -Force
        Remove-Item (Join-Path $luaDst "$mod\docs") -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $luaDst "$mod\upvalue_check.lua") -Force -ErrorAction SilentlyContinue
    }

    $mqDst = Join-Path $luaDst 'mq'
    New-Item -ItemType Directory -Path $mqDst -Force | Out-Null
    Copy-Item (Join-Path $RepoRoot 'lua\mq\ItemUtils.lua') -Destination (Join-Path $mqDst 'ItemUtils.lua') -Force

    # Macros
    $macrosDst = Join-Path $StagingDir 'Macros'
    New-Item -ItemType Directory -Path $macrosDst -Force | Out-Null
    foreach ($mac in @('sell.mac', 'loot.mac')) {
        $src = Join-Path $RepoRoot "Macros\$mac"
        Assert-FileExists $src "Macros\$mac"
        Copy-Item $src -Destination $macrosDst -Force
    }
    $sharedDst = Join-Path $macrosDst 'shared_config'
    New-Item -ItemType Directory -Path $sharedDst -Force | Out-Null
    $sharedSrc = Join-Path $RepoRoot 'Macros\shared_config'
    if (Test-Path $sharedSrc) {
        Get-ChildItem $sharedSrc -Filter '*.mac' | Copy-Item -Destination $sharedDst -Force
    }

    # Config templates
    $ctDst = Join-Path $StagingDir 'config_templates'
    foreach ($sub in @('sell_config', 'shared_config', 'loot_config')) {
        $subDst = Join-Path $ctDst $sub
        New-Item -ItemType Directory -Path $subDst -Force | Out-Null
        $subSrc = Join-Path $RepoRoot "config_templates\$sub"
        if (Test-Path $subSrc) {
            Get-ChildItem $subSrc -Filter '*.ini' -ErrorAction SilentlyContinue |
                Copy-Item -Destination $subDst -Force
        }
    }

    # Resources
    $resSrc = Join-Path $RepoRoot 'resources\UIFiles\Default'
    if (Test-Path $resSrc) {
        $resDst = Join-Path $StagingDir 'resources\UIFiles\Default'
        New-Item -ItemType Directory -Path $resDst -Force | Out-Null
        Get-ChildItem $resSrc | Copy-Item -Destination $resDst -Force
    }

    # Config
    $cbSrc = Join-Path $RepoRoot 'config\MQ2CustomBinds.txt'
    if (Test-Path $cbSrc) {
        $cfgDst = Join-Path $StagingDir 'config'
        New-Item -ItemType Directory -Path $cfgDst -Force | Out-Null
        Copy-Item $cbSrc -Destination $cfgDst -Force
    }

    # Docs + manifests
    foreach ($doc in @('DEPLOY.md', 'CHANGELOG.md')) {
        $docPath = Join-Path $RepoRoot $doc
        if (Test-Path $docPath) { Copy-Item $docPath -Destination $StagingDir -Force }
    }
    $dcm = Join-Path $RepoRoot 'default_config_manifest.json'
    if (Test-Path $dcm) { Copy-Item $dcm -Destination $StagingDir -Force }

    # Installer
    $patcher = Join-Path $RepoRoot 'Install-CoOptUI.ps1'
    if (Test-Path $patcher) { Copy-Item $patcher -Destination $StagingDir -Force }
}

function Ensure-MacroQuestIni {
    param([string]$StagingDir)
    $configDir = Join-Path $StagingDir 'config'
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $mqIni = Join-Path $configDir 'MacroQuest.ini'

    if (-not (Test-Path $mqIni)) {
        # Create a complete MacroQuest.ini with all required plugins + auto-exec
        $iniContent = @"
[MacroQuest]
MacroQuestWinClassName=__MacroQuestTray
MacroQuestWinName=MacroQuest
ShowLoaderConsole=0
ShowMacroQuestConsole=1

[Plugins]
mq2lua=1
mq2mono=1
MQ2CoOptUI=1
mq2chatwnd=1
mq2custombinds=1
mq2itemdisplay=1
mq2map=1
mq2nav=1
mq2dannet=1

[AutoExec]
/mono load e3
"@
        Set-Content $mqIni $iniContent
        Write-Ok 'Created MacroQuest.ini (with /mono load e3 auto-exec)'
    } else {
        # Patch existing to ensure required plugins are enabled
        $content = Get-Content $mqIni -Raw
        $modified = $false
        foreach ($plugin in @('mq2mono', 'MQ2CoOptUI', 'mq2custombinds')) {
            if ($content -notmatch "$plugin\s*=\s*1") {
                $content = $content -replace '(\[Plugins\])', "`$1`r`n$plugin=1"
                $modified = $true
            }
        }
        # Ensure [AutoExec] with /mono load e3
        if ($content -notmatch '\[AutoExec\]') {
            $content = $content.TrimEnd() + "`r`n`r`n[AutoExec]`r`n/mono load e3`r`n"
            $modified = $true
        } elseif ($content -notmatch '/mono\s+load\s+e3') {
            $content = $content -replace '(\[AutoExec\])', "`$1`r`n/mono load e3"
            $modified = $true
        }
        if ($modified) { Set-Content $mqIni $content -NoNewline }
    }
}

# ======================================================================
# Region 8: Packaging
# ======================================================================

function New-ZipFromStaging {
    param([string]$StagingDir, [string]$ZipPath)

    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zipSafeTime = [DateTime]::Parse('2025-01-01 00:00:00')
    $root = (Resolve-Path $StagingDir).Path.TrimEnd('\')
    $files = Get-ChildItem -Path $StagingDir -Recurse -File

    $archive = [System.IO.Compression.ZipFile]::Open(
        $ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $entryName = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
            $entry = $archive.CreateEntry($entryName,
                [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $zipSafeTime
            $stream = $entry.Open()
            try {
                $fs = [System.IO.File]::OpenRead($f.FullName)
                try { $fs.CopyTo($stream) }
                finally { $fs.Dispose() }
            } finally { $stream.Close() }
        }
    } finally { $archive.Dispose() }

    $sizeKB = [math]::Round((Get-Item $ZipPath).Length / 1KB, 0)
    $fc = $files.Count
    Write-Ok "Created: $(Split-Path $ZipPath -Leaf) -- ${sizeKB} KB, $fc files"
}

# ======================================================================
# Region 9: Release Pipeline
# ======================================================================

function Generate-Manifests {
    param(
        [string]$RepoRoot,
        [string]$PluginDllPath = '',
        [string]$ReleaseTag = ''
    )
    Push-Location $RepoRoot
    try {
        $manifestArgs = @('patcher/generate_manifest.py')
        if ($PluginDllPath -and (Test-Path $PluginDllPath)) {
            $manifestArgs += '--plugin-dll', $PluginDllPath
        }
        if ($ReleaseTag) {
            $manifestArgs += '--release-tag', $ReleaseTag
        }
        python @manifestArgs 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { Write-Error 'generate_manifest.py failed' }
        python patcher/generate_default_config_manifest.py 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { Write-Error 'generate_default_config_manifest.py failed' }
        Write-Ok 'Manifests generated'
    } finally { Pop-Location }
}

function Build-PatcherExe {
    param([string]$RepoRoot)

    # Check Python available
    $pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
    if (-not $pythonExe) {
        Write-Warning 'Python not found — skipping patcher build. Install Python 3.10+ to build CoOptUIPatcher.'
        return $null
    }

    $reqFile = Join-Path $RepoRoot 'patcher\requirements.txt'
    if (Test-Path $reqFile) {
        Write-Info 'Installing patcher Python dependencies...'
        # Pipe to Write-Host so output doesn't pollute return value
        python -m pip install -r $reqFile --quiet 2>&1 | ForEach-Object { Write-Host "  $_" }
    }
    Push-Location (Join-Path $RepoRoot 'patcher')
    try {
        $buildIconScript = Join-Path $RepoRoot 'patcher\build_icon.py'
        if (Test-Path $buildIconScript) {
            python build_icon.py 2>&1 | ForEach-Object { Write-Host "  $_" }
        }
        Write-Info 'Running PyInstaller...'
        python -m PyInstaller patcher.spec --noconfirm 2>&1 | ForEach-Object { Write-Host "  $_" }
    } finally { Pop-Location }

    $exePath = Join-Path $RepoRoot 'patcher\dist\CoOptUIPatcher.exe'
    if (-not (Test-Path $exePath)) {
        Write-Warning "Patcher exe not found at $exePath — PyInstaller may have failed."
        return $null
    }
    $sizeMB = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
    Write-Ok "Patcher built: CoOptUIPatcher.exe ($sizeMB MB)"
    return $exePath
}

function Publish-Release {
    param(
        [string]$RepoRoot,
        [string]$Version,
        [string]$Branch = 'master',
        [switch]$DryRun
    )

    $tag = "v$Version"

    # Pre-flight: branch, clean tree, tag uniqueness
    $currentBranch = (git -C $RepoRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($currentBranch -ne $Branch) {
        Write-Error "Expected branch '$Branch' but on '$currentBranch'."
    }

    $existingTag = git -C $RepoRoot tag --list $tag 2>$null
    if ($existingTag -and $existingTag.Trim()) {
        Write-Error "Tag '$tag' already exists. Bump the version or delete the tag."
    }

    # Stage manifests
    git -C $RepoRoot add release_manifest.json default_config_manifest.json

    $hasDiff = $true
    git -C $RepoRoot diff --cached --quiet 2>$null
    if ($LASTEXITCODE -eq 0) { $hasDiff = $false }

    if ($DryRun) {
        Write-Info "[DRY RUN] Would commit manifests and create tag $tag"
        return
    }

    if ($hasDiff) {
        git -C $RepoRoot commit -m "chore: regenerate release manifests for $tag"
        if ($LASTEXITCODE -ne 0) { Write-Error 'git commit failed' }
    }

    git -C $RepoRoot tag -a $tag -m "Release $tag"
    if ($LASTEXITCODE -ne 0) { Write-Error 'git tag failed' }

    git -C $RepoRoot push origin $Branch
    if ($LASTEXITCODE -ne 0) { Write-Error "git push origin $Branch failed" }

    git -C $RepoRoot push origin $tag
    if ($LASTEXITCODE -ne 0) { Write-Error "git push origin $tag failed" }

    Write-Ok "Pushed $Branch + tag $tag to origin"
}

function Create-GitHubRelease {
    param(
        [string]$Version,
        [string[]]$Artifacts,
        [switch]$DryRun
    )

    $tag = "v$Version"
    $Repo = 'CooptGaming/CooptUI'

    if ($DryRun) {
        Write-Info "[DRY RUN] Would create GitHub release $tag with:"
        foreach ($a in $Artifacts) { Write-Info "  - $(Split-Path $a -Leaf)" }
        return
    }

    # Verify gh CLI
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warning 'gh CLI not found — skipping GitHub release creation.'
        Write-Warning 'Install from https://cli.github.com/ and run: gh auth login'
        return
    }

    $ghArgs = @('release', 'create', $tag)
    $ghArgs += $Artifacts
    $ghArgs += @('--repo', $Repo, '--title', $tag, '--generate-notes', '--draft')
    gh @ghArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create GitHub release."
    }

    Write-Ok "Draft release $tag created on GitHub"
    Write-Info "Review and publish at: https://github.com/$Repo/releases"
}

# ======================================================================
# Region 10: Main Orchestrator
# ======================================================================

$RepoRoot = Get-RepoRoot

# Resolve version
if (-not $Version) { $Version = Read-CoOptVersion $RepoRoot }
$Version = $Version -replace '^v', ''

# Resolve output dir
if (-not [System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path (Get-Location) $OutputDir
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Resolve MQ source root
if (-not $MQSourceRoot) { $MQSourceRoot = Join-Path $OutputDir '.mq-source' }

# Resolve targets
$targets = switch ($Target) {
    'All' { @('FullBundle', 'CoOptOnly', 'PluginOnly') }
    default { @($Target) }
}

$needsPlugin = (-not $SkipPlugin) -and (($targets -contains 'FullBundle') -or ($targets -contains 'PluginOnly'))
$needsFullBuild = ($targets -contains 'FullBundle')

Write-Host ''
Write-Host '=== CoOpt UI Smart Build (From Source) ===' -ForegroundColor Cyan
Write-Host "  Version:    $Version"
Write-Host "  Target:     $Target"
Write-Host "  Output:     $OutputDir"
Write-Host "  MQ Source:  $MQSourceRoot"
Write-Host "  Plugin:     $(if ($needsPlugin) { 'yes' } else { 'skip' })"
Write-Host "  Full Build: $(if ($needsFullBuild) { 'yes (MQ + MQ2Mono + E3Next)' } else { 'no' })"
Write-Host "  Force:      $Force"
if ($Release) { Write-Host "  Release:    yes" -ForegroundColor Yellow }
if ($DryRun) { Write-Host "  DRY RUN:    yes" -ForegroundColor Yellow }
Write-Host ''

# Load state
$state = if ($Force) { Read-BuildState '__force_empty__' } else { Read-BuildState $OutputDir }

# Track what changed
$mqBuildChanged = $false
$e3BuildChanged = $false
$pluginChanged = $false
$cooptuiChanged = $false

# Shared variables for build outputs
$mqBinDir = ''
$e3OutputDir = ''
$pluginDllPath = ''
$sourceEnv = $null

# ------------------------------------------------------------------
# Stage 1: Setup Source Environment + Check for Changes
# ------------------------------------------------------------------

if ($needsFullBuild -or $needsPlugin) {
    Write-Stage 'Stage 1: Source Environment'

    # Read MQ ref from plugin config
    $mqRefFile = Join-Path $RepoRoot 'plugin\MQ_COMMIT_SHA.txt'
    $mqRef = 'master'
    if (Test-Path $mqRefFile) {
        $mqRef = (Get-Content $mqRefFile | Where-Object { $_ -and -not $_.StartsWith('#') } | Select-Object -First 1).Trim()
    }

    # Ensure all repos are cloned and up-to-date
    $sourceEnv = Ensure-MQSourceEnv -MQSourceRoot $MQSourceRoot -RepoRoot $RepoRoot -MQRef $mqRef

    # Find CMake
    $cmakeExe = Find-CMake330 $CMakePath
    if (-not $cmakeExe) {
        Write-Error 'CMake 3.30 not found. Install it and pass -CMakePath, or set PATH.'
    }
    Write-Ok "CMake: $cmakeExe"
} else {
    Write-Stage 'Stage 1: Source Environment'
    Write-Skip 'Not needed for CoOptOnly target'
}

# ------------------------------------------------------------------
# Stage 2: Build MacroQuest (full or plugin-only)
# ------------------------------------------------------------------

if ($needsFullBuild -or $needsPlugin) {
    Write-Stage 'Stage 2: MacroQuest Build'

    # Check if rebuild needed
    $currentBuildHash = Get-FullBuildSourceHash $RepoRoot $MQSourceRoot
    $buildNeeded = $Force -or ($state.fullBuild.sourceHash -ne $currentBuildHash)

    # Also check if the MQ bin dir still exists from last build
    if (-not $buildNeeded -and $state.fullBuild.mqBinDir -and (Test-Path $state.fullBuild.mqBinDir)) {
        $pluginInBin = Join-Path $state.fullBuild.mqBinDir 'plugins\MQ2CoOptUI.dll'
        if (-not (Test-Path $pluginInBin)) { $buildNeeded = $true }
    } elseif (-not $buildNeeded) {
        $buildNeeded = $true  # no cached bin dir
    }

    if ($buildNeeded) {
        Write-Info "Source changed or first build — building MacroQuest..."
        $mqBinDir = Build-MQFull -MQClone $sourceEnv.MQClone -CMakeExe $cmakeExe -RepoRoot $RepoRoot `
            -PluginOnly:(-not $needsFullBuild)

        $mqBuildChanged = $true
        $pluginChanged = $true

        # Update state
        $state.fullBuild.sourceHash = $currentBuildHash
        $state.fullBuild.mqBinDir = $mqBinDir
        $pluginDllPath = Join-Path $mqBinDir 'plugins\MQ2CoOptUI.dll'
        $state.plugin.sourceHash = (Get-PluginSourceHash $RepoRoot)
        $state.plugin.dllPath = $pluginDllPath
    } else {
        Write-Skip "Sources unchanged (hash: $($currentBuildHash.Substring(0,12))...)"
        $mqBinDir = $state.fullBuild.mqBinDir
        $pluginDllPath = $state.plugin.dllPath
    }
} else {
    Write-Stage 'Stage 2: MacroQuest Build'
    Write-Skip 'Not needed'
}

# ------------------------------------------------------------------
# Stage 2b: Build E3Next (C#)
# ------------------------------------------------------------------

$e3OutputDir = ''
if ($needsFullBuild -and $sourceEnv) {
    Write-Stage 'Stage 2b: E3Next Build'

    $e3Head = Get-LocalHeadSha $sourceEnv.E3NextDir
    $e3BuildNeeded = $Force -or ($state.e3next.sourceHash -ne $e3Head)

    if (-not $e3BuildNeeded -and $state.e3next.outputDir -and (Test-Path $state.e3next.outputDir)) {
        Write-Skip "E3Next unchanged (SHA: $($e3Head.Substring(0,8))...)"
        $e3OutputDir = $state.e3next.outputDir
    } else {
        $e3OutputDir = Build-E3Next -E3NextDir $sourceEnv.E3NextDir
        if ($e3OutputDir) {
            $e3BuildChanged = $true
            $state.e3next.sourceHash = $e3Head
            $state.e3next.outputDir = $e3OutputDir
        }
    }
} else {
    if ($needsFullBuild) {
        Write-Stage 'Stage 2b: E3Next Build'
        Write-Skip 'Source env not available'
    }
}

# ------------------------------------------------------------------
# Stage 2c: Build Patcher (Python/PyInstaller)
# ------------------------------------------------------------------

$patcherExePath = $null
if ($needsFullBuild -or $Target -eq 'All') {
    Write-Stage 'Stage 2c: Patcher Build'

    $patcherSpec = Join-Path $RepoRoot 'patcher\patcher.spec'
    if (Test-Path $patcherSpec) {
        # Check if cached patcher is still current
        $patcherSrcHash = Get-MultiPathHash @(
            @{ Path = (Join-Path $RepoRoot 'patcher'); Include = @('*.py', '*.spec', '*.txt'); Exclude = @('dist/*', 'build/*') }
            @{ Path = (Join-Path $RepoRoot 'patcher\assets'); Include = @('*') }
        )
        $cachedPatcherExe = Join-Path $RepoRoot 'patcher\dist\CoOptUIPatcher.exe'
        $patcherBuildNeeded = $Force -or (-not (Test-Path $cachedPatcherExe)) -or
            ($state.PSObject.Properties['patcher'] -and $state.patcher.sourceHash -ne $patcherSrcHash) -or
            (-not $state.PSObject.Properties['patcher'])

        if ($patcherBuildNeeded) {
            $patcherExePath = Build-PatcherExe $RepoRoot
            if ($patcherExePath) {
                $patcherChanged = $true
                if (-not $state.PSObject.Properties['patcher']) {
                    $state | Add-Member -NotePropertyName 'patcher' -NotePropertyValue @{ sourceHash = ''; exePath = '' }
                }
                $state.patcher.sourceHash = $patcherSrcHash
                $state.patcher.exePath = $patcherExePath
            }
        } else {
            Write-Skip "Patcher unchanged (using cached exe)"
            $patcherExePath = $cachedPatcherExe
        }
    } else {
        Write-Skip 'No patcher\patcher.spec found — skipping patcher build'
    }
} else {
    Write-Stage 'Stage 2c: Patcher Build'
    Write-Skip 'Not needed for this target'
}

# ------------------------------------------------------------------
# Stage 3: Check CoOptUI Sources
# ------------------------------------------------------------------

Write-Stage 'Stage 3: CoOptUI Source Check'

$currentCoOptHash = Get-CoOptUISourceHash $RepoRoot
$cooptuiNeedsUpdate = $Force -or ($state.cooptui.sourceHash -ne $currentCoOptHash)

if ($cooptuiNeedsUpdate) {
    Write-Info 'CoOptUI sources changed — will re-copy files.'
    $cooptuiChanged = $true
} else {
    Write-Skip "CoOptUI sources unchanged (hash: $($currentCoOptHash.Substring(0,12))...)"
}

# ------------------------------------------------------------------
# Stage 4: Assemble Output
# ------------------------------------------------------------------

$outputZips = @()
$anythingChanged = $Force -or $mqBuildChanged -or $e3BuildChanged -or $pluginChanged -or $cooptuiChanged -or $patcherChanged

foreach ($t in $targets) {
    Write-Stage "Stage 4: Assemble -- $t"

    if (-not $anythingChanged -and $state.version -eq $Version) {
        $existingZip = switch ($t) {
            'FullBundle' { Join-Path $OutputDir "CoOptUI-EMU-v$Version.zip" }
            'CoOptOnly'  { Join-Path $OutputDir "CoOptUI-v$Version.zip" }
            'PluginOnly' { Join-Path $OutputDir "MQ2CoOptUI-v$Version-Win32.zip" }
        }
        if (Test-Path $existingZip) {
            Write-Skip "Output already exists: $(Split-Path $existingZip -Leaf)"
            $outputZips += $existingZip
            continue
        }
    }

    $staging = Join-Path $env:TEMP "CoOptUI_smart_${t}_$(Get-Random)"
    New-Item -ItemType Directory -Path $staging -Force | Out-Null

    try {
        switch ($t) {
            'CoOptOnly' {
                Copy-CoOptUIFiles -StagingDir $staging -RepoRoot $RepoRoot
                $zipPath = Join-Path $OutputDir "CoOptUI-v$Version.zip"
                New-ZipFromStaging $staging $zipPath
                $outputZips += $zipPath
            }

            'PluginOnly' {
                if ($pluginDllPath -and (Test-Path $pluginDllPath)) {
                    $pluginsDst = Join-Path $staging 'plugins'
                    New-Item -ItemType Directory -Path $pluginsDst -Force | Out-Null
                    Copy-Item $pluginDllPath -Destination $pluginsDst -Force
                    $patcherFile = Join-Path $RepoRoot 'Install-CoOptUI.ps1'
                    if (Test-Path $patcherFile) { Copy-Item $patcherFile -Destination $staging -Force }
                    $zipPath = Join-Path $OutputDir "MQ2CoOptUI-v$Version-Win32.zip"
                    New-ZipFromStaging $staging $zipPath
                    $outputZips += $zipPath
                } else {
                    Write-Warning 'No plugin DLL available — skipping PluginOnly target.'
                }
            }

            'FullBundle' {
                # ============================================================
                # Layer 0: Repo distribution base
                # Copy the pre-existing distribution files (third-party plugins,
                # configs, macros, lua scripts, resources, utilities, modules).
                # Later layers overwrite core binaries with freshly built ones.
                # ============================================================

                # 0a: Pre-built third-party plugins (85+ DLLs not compiled by us)
                $repoPlugins = Join-Path $RepoRoot 'plugins'
                if (Test-Path $repoPlugins) {
                    $dstPlugins = Join-Path $staging 'plugins'
                    New-Item -ItemType Directory -Path $dstPlugins -Force | Out-Null
                    Copy-Item "$repoPlugins\*.dll" -Destination $dstPlugins -Force
                    $pluginCount = (Get-ChildItem $dstPlugins -Filter '*.dll').Count
                    Write-Ok "Repo plugins base: $pluginCount DLLs"
                }

                # 0b: Pre-built top-level binaries (crashpad, eqbcs, D3DX9, etc.)
                $prebuiltFiles = @(
                    'crashpad_handler.exe', 'D3DX9_43.dll', 'D3DX9d_43.dll',
                    'eqbcs.exe', 'MeshGenerator.exe', 'imgui-64.dll'
                )
                $copiedPrebuilt = 0
                foreach ($f in $prebuiltFiles) {
                    $src = Join-Path $RepoRoot $f
                    if (Test-Path $src) { Copy-Item $src -Destination $staging -Force; $copiedPrebuilt++ }
                }
                if ($copiedPrebuilt) { Write-Ok "Pre-built binaries: $copiedPrebuilt files" }

                # 0c: Config tree (all MQ/E3 config files, ini, cfg)
                $repoConfig = Join-Path $RepoRoot 'config'
                if (Test-Path $repoConfig) {
                    $dstConfig = Join-Path $staging 'config'
                    Copy-Item $repoConfig -Destination $staging -Recurse -Force
                    Write-Ok 'Config tree copied'
                }

                # 0d: Macros tree (all .mac files + config subdirs)
                $repoMacros = Join-Path $RepoRoot 'Macros'
                if (Test-Path $repoMacros) {
                    Copy-Item $repoMacros -Destination $staging -Recurse -Force
                    Write-Ok 'Macros tree copied'
                }

                # 0e: Lua scripts (all directories — boxhud, buttonmaster, mq, etc.)
                $repoLua = Join-Path $RepoRoot 'lua'
                if (Test-Path $repoLua) {
                    $dstLua = Join-Path $staging 'lua'
                    New-Item -ItemType Directory -Path $dstLua -Force | Out-Null
                    # Copy each lua subdirectory
                    Get-ChildItem $repoLua -Directory | ForEach-Object {
                        Copy-Item $_.FullName -Destination (Join-Path $dstLua $_.Name) -Recurse -Force
                    }
                    # Copy top-level .lua files (eval.lua, FocusEffects.lua, etc.)
                    Get-ChildItem $repoLua -File -Filter '*.lua' -EA SilentlyContinue |
                        Copy-Item -Destination $dstLua -Force
                    $luaDirs = (Get-ChildItem $dstLua -Directory).Count
                    Write-Ok "Lua scripts: $luaDirs packages"
                }

                # 0f: Resources (MQ2Nav doors, MQ2LinkDB, Sounds, UIFiles, Mono runtime, etc.)
                $repoResources = Join-Path $RepoRoot 'resources'
                if (Test-Path $repoResources) {
                    $dstResources = Join-Path $staging 'resources'
                    New-Item -ItemType Directory -Path $dstResources -Force | Out-Null
                    Copy-Item "$repoResources\*" -Destination $dstResources -Recurse -Force
                    Write-Ok 'Resources tree copied (MQ2Nav, MQ2LinkDB, Sounds, UIFiles, etc.)'
                }

                # 0g: Modules (LuaRocks + native DLLs: lfs.dll, lsqlite3.dll)
                $repoModules = Join-Path $RepoRoot 'modules'
                if (Test-Path $repoModules) {
                    Copy-Item $repoModules -Destination $staging -Recurse -Force
                    Write-Ok 'Modules copied (LuaRocks)'
                }

                # 0h: Utilities (GamParse, batch files, etc.)
                $repoUtilities = Join-Path $RepoRoot 'Utilities'
                if (Test-Path $repoUtilities) {
                    Copy-Item $repoUtilities -Destination $staging -Recurse -Force
                    Write-Ok 'Utilities copied'
                }

                # ============================================================
                # Layer 1: MQ build output (overwrites repo base with fresh binaries)
                # ============================================================
                if ($mqBinDir -and (Test-Path $mqBinDir)) {
                    # Root binaries (MacroQuest.exe, MQ2Main.dll, eqlib.dll, imgui.dll, luarocks.exe)
                    # NOTE: -Exclude is broken with full paths in PowerShell — use Where-Object instead
                    Get-ChildItem $mqBinDir -File | Where-Object { $_.Extension -ne '.pdb' } |
                        Copy-Item -Destination $staging -Force
                    # Freshly built plugins (MQ2CoOptUI, MQ2Mono, MQ2Lua, etc. — overwrites repo versions)
                    $srcPlugins = Join-Path $mqBinDir 'plugins'
                    if (Test-Path $srcPlugins) {
                        $dstPlugins = Join-Path $staging 'plugins'
                        New-Item -ItemType Directory -Path $dstPlugins -Force | Out-Null
                        Get-ChildItem $srcPlugins -File | Where-Object { $_.Extension -ne '.pdb' } |
                            Copy-Item -Destination $dstPlugins -Force
                    }
                    # Resources from build output (ItemDB, Zones.ini, etc.)
                    $srcRes = Join-Path $mqBinDir 'resources'
                    if (Test-Path $srcRes) {
                        $dstRes = Join-Path $staging 'resources'
                        New-Item -ItemType Directory -Path $dstRes -Force | Out-Null
                        Copy-Item "$srcRes\*" -Destination $dstRes -Recurse -Force
                    }
                    $builtPluginCount = (Get-ChildItem $srcPlugins -File -Filter '*.dll' -EA SilentlyContinue).Count
                    Write-Ok "MQ build output overlaid (core + $builtPluginCount built plugins)"
                }

                # ============================================================
                # Layer 2: Mono runtime (mono-2.0-sgen.dll + resources/Mono/32bit)
                # Overwrites repo's older Mono with freshly cloned MQ2Mono-Framework32
                # ============================================================
                if ($sourceEnv -and $sourceEnv.MonoFwDir -and (Test-Path $sourceEnv.MonoFwDir)) {
                    $monoFw = $sourceEnv.MonoFwDir
                    $monoSgen = Join-Path $monoFw 'mono-2.0-sgen.dll'
                    if (Test-Path $monoSgen) {
                        Copy-Item $monoSgen -Destination $staging -Force
                        Write-Ok 'Copied mono-2.0-sgen.dll'
                    }
                    $mono32Src = Join-Path $monoFw 'resources\Mono\32bit'
                    if (Test-Path $mono32Src) {
                        $mono32Dst = Join-Path $staging 'resources\mono\32bit'
                        New-Item -ItemType Directory -Path $mono32Dst -Force | Out-Null
                        Copy-Item "$mono32Src\*" -Destination $mono32Dst -Recurse -Force
                        Write-Ok 'Mono runtime updated (resources\mono\32bit)'
                    }
                    $monoBCL = Join-Path $monoFw 'lib\mono'
                    if (Test-Path $monoBCL) {
                        $dstBCL = Join-Path $staging 'lib\mono'
                        New-Item -ItemType Directory -Path $dstBCL -Force | Out-Null
                        Copy-Item "$monoBCL\*" -Destination $dstBCL -Recurse -Force
                    }
                }

                # ============================================================
                # Layer 3: E3Next (freshly built, overwrites repo's old E3 in mono/macros/e3/)
                # ============================================================
                if ($e3OutputDir -and (Test-Path $e3OutputDir)) {
                    $e3Deploy = Join-Path $staging 'mono\macros\e3'
                    # Wipe old repo E3 content before copying fresh build
                    if (Test-Path $e3Deploy) { Remove-Item $e3Deploy -Recurse -Force }
                    New-Item -ItemType Directory -Path $e3Deploy -Force | Out-Null
                    Copy-Item "$e3OutputDir\*" -Destination $e3Deploy -Recurse -Force

                    # Merge sibling project outputs (ConfigEditor, Proxy, RemoteDebugger)
                    $e3SolutionRoot = Split-Path (Split-Path (Split-Path $e3OutputDir))
                    $siblingProjects = @('E3NextConfigEditor', 'E3NextProxy', 'RemoteDebuggerServer')
                    foreach ($proj in $siblingProjects) {
                        $sibBin = Join-Path $e3SolutionRoot "$proj\bin\Release"
                        if (Test-Path $sibBin) {
                            $sibFiles = Get-ChildItem $sibBin -File | Where-Object {
                                -not (Test-Path (Join-Path $e3Deploy $_.Name)) -and
                                $_.Extension -notin @('.pdb', '.xml')
                            }
                            foreach ($f in $sibFiles) { Copy-Item $f.FullName -Destination $e3Deploy -Force }
                            if ($sibFiles) {
                                $names = ($sibFiles | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '
                                $extra = if ($sibFiles.Count -gt 3) { " +$($sibFiles.Count - 3) more" } else { '' }
                                Write-Info "  Merged from ${proj}: ${names}${extra}"
                            }
                        }
                    }

                    # Move SQLite.Interop.dll to mono\libs\ (E3 expects it there)
                    $e3x86 = Join-Path $e3Deploy 'x86'
                    $e3x64 = Join-Path $e3Deploy 'x64'
                    if (Test-Path $e3x86) {
                        $monoLibs32 = Join-Path $staging 'mono\libs\32bit'
                        New-Item -ItemType Directory -Path $monoLibs32 -Force | Out-Null
                        Copy-Item (Join-Path $e3x86 'SQLite.Interop.dll') -Destination $monoLibs32 -Force -EA SilentlyContinue
                    }
                    if (Test-Path $e3x64) {
                        $monoLibs64 = Join-Path $staging 'mono\libs\64bit'
                        New-Item -ItemType Directory -Path $monoLibs64 -Force | Out-Null
                        Copy-Item (Join-Path $e3x64 'SQLite.Interop.dll') -Destination $monoLibs64 -Force -EA SilentlyContinue
                    }
                    # Clean up dev artifacts
                    Remove-Item $e3x86 -Recurse -Force -EA SilentlyContinue
                    Remove-Item $e3x64 -Recurse -Force -EA SilentlyContinue
                    Get-ChildItem $e3Deploy -Filter '*.pdb' -Recurse -File | Remove-Item -Force -EA SilentlyContinue
                    Get-ChildItem $e3Deploy -Filter '*.xml' -Recurse -File | Remove-Item -Force -EA SilentlyContinue
                    Write-Ok 'E3Next deployed to mono\macros\e3 (freshly built)'
                }

                # ============================================================
                # Layer 4: CoOptUI overlay (itemui, coopui, scripttracker Lua + macros)
                # Overwrites/extends what came from Layer 0
                # ============================================================
                Copy-CoOptUIFiles -StagingDir $staging -RepoRoot $RepoRoot
                Write-Ok 'CoOptUI files overlaid'

                # ============================================================
                # Layer 5: Config finalization (MacroQuest.ini with plugin load list)
                # ============================================================
                Ensure-MacroQuestIni $staging

                # ============================================================
                # Layer 6: Patcher exe
                # ============================================================
                if ($patcherExePath -and (Test-Path $patcherExePath)) {
                    Copy-Item $patcherExePath -Destination $staging -Force
                    Write-Ok "Patcher included: CoOptUIPatcher.exe"
                }

                # --- README ---
                @(
                    "CoOpt UI v$Version — Full EMU Bundle (built from source)"
                    ''
                    'CONTENTS'
                    '  - MacroQuest launcher and EMU base (32-bit, built from latest source)'
                    '  - All MQ plugins (MQ2Nav, MQ2EQBC, MQ2DanNet, MQ2Cast, MQ2Melee, etc.)'
                    '  - MQ2Mono plugin + Mono runtime (32-bit)'
                    '  - E3Next in mono\macros\e3\ (built from latest source)'
                    '  - MQ2CoOptUI plugin + CoOpt UI Lua, macros, resources'
                    '  - BoxHUD, ButtonMaster, and other community Lua scripts'
                    '  - CoOptUIPatcher.exe for easy future updates'
                    ''
                    'HOW TO USE'
                    '  1. Unzip this folder anywhere (e.g. C:\MQ-EMU).'
                    '  2. Run MacroQuest.exe.'
                    '  3. Launch EverQuest (EMU).'
                    '  4. In-game: /lua run itemui'
                    '  5. Load E3: /mono load e3'
                    '  6. For future updates: run CoOptUIPatcher.exe'
                ) | Set-Content (Join-Path $staging 'README.txt')

                # --- Final cleanup: remove sensitive/user-specific/dev artifacts ---
                $removedCount = 0

                # 1. Credential databases (login.db stores account passwords!)
                Get-ChildItem $staging -Recurse -File -EA SilentlyContinue | Where-Object {
                    $_.Name -match '^login\.db(-wal|-shm|-journal)?$'
                } | ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }

                # 2. Duplicate config/config/ directory (accidental nesting from repo)
                $dupConfig = Join-Path $staging 'config\config'
                if (Test-Path $dupConfig) {
                    $dupCount = (Get-ChildItem $dupConfig -Recurse -File).Count
                    Remove-Item $dupConfig -Recurse -Force
                    $removedCount += $dupCount
                }

                # 3. Character-named config files (CharName_Server.ini pattern)
                $configDir = Join-Path $staging 'config'
                if (Test-Path $configDir) {
                    # Remove per-character MQ configs (e.g. "Perky Crew_Dripe.ini")
                    Get-ChildItem $configDir -File -Filter '*.ini' | Where-Object {
                        $_.Name -match '_.*\.' -and
                        $_.Name -notin @('MacroQuest.ini','MacroQuest_default.ini','MacroQuest_Overlay.ini','MacroQuest_LauncherUI.ini')
                    } | ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }
                    # Remove NULL.ini (accumulated junk)
                    $nullIni = Join-Path $configDir 'NULL.ini'
                    if (Test-Path $nullIni) { Remove-Item $nullIni -Force; $removedCount++ }
                    # Remove runtime-generated files
                    foreach ($rtFile in @('sort_settings.ini','ingame.cfg','zoned.cfg','giveitems.ini')) {
                        $f = Join-Path $configDir $rtFile
                        if (Test-Path $f) { Remove-Item $f -Force; $removedCount++ }
                    }
                }

                # 4. E3 Bot Inis: keep class template FOLDERS, remove ALL .ini files (they contain character data)
                $e3BotDir = Join-Path $staging 'config\e3 Bot Inis'
                if (Test-Path $e3BotDir) {
                    # Remove ALL .ini files (root and nested in class subdirs — all are character-specific)
                    Get-ChildItem $e3BotDir -File -Filter '*.ini' -Recurse | ForEach-Object {
                        Remove-Item $_.FullName -Force; $removedCount++
                    }
                }

                # 5. E3 Macro Inis: remove character-specific files, keep general templates
                $e3MacroDir = Join-Path $staging 'config\e3 Macro Inis'
                if (Test-Path $e3MacroDir) {
                    Get-ChildItem $e3MacroDir -File -Recurse | Where-Object {
                        $_.Name -match '^(E3UI_|Loot_Stackable_|eva_unlock)' -or
                        $_.Name -match '_(Lazarus|Perky)' -or
                        $_.Extension -eq '.reg'
                    } | ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }
                }

                # 6. Macro user data: character inventories, logs, bank data, caches
                foreach ($userDir in @('Macros\sell_config\Chars', 'Macros\bank_data', 'Macros\logs')) {
                    $d = Join-Path $staging $userDir
                    if (Test-Path $d) {
                        $c = (Get-ChildItem $d -Recurse -File).Count
                        Remove-Item $d -Recurse -Force
                        $removedCount += $c
                    }
                }
                # Remove user-specific loot/sell runtime files
                $lootCfg = Join-Path $staging 'Macros\loot_config'
                if (Test-Path $lootCfg) {
                    Get-ChildItem $lootCfg -File | Where-Object {
                        $_.Name -match '(history|session|skipped|progress)\.ini$'
                    } | ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }
                }
                $sellCfg = Join-Path $staging 'Macros\sell_config'
                if (Test-Path $sellCfg) {
                    Get-ChildItem $sellCfg -File -Filter 'sell_cache.ini' -EA SilentlyContinue |
                        ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }
                }
                # Remove version stamps and user config markers
                foreach ($stamp in @('Macros\coopui_installed_version.txt',
                                     'Macros\sell_config\default_layout_version.txt',
                                     'Macros\perky_config.ini')) {
                    $f = Join-Path $staging $stamp
                    if (Test-Path $f) { Remove-Item $f -Force; $removedCount++ }
                }

                # 7. GamParse INI (contains local paths and character names)
                # Note: directory may be named GamParse or GameParse depending on repo
                Get-ChildItem $staging -Filter 'GamParse.INI' -Recurse -File -EA SilentlyContinue |
                    ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }

                # 8. Registry files (could contain user system modifications)
                Get-ChildItem $staging -Filter '*.reg' -Recurse -File -EA SilentlyContinue |
                    ForEach-Object { Remove-Item $_.FullName -Force; $removedCount++ }

                # 9. Server/team-specific resource files
                $perkyCSV = Join-Path $staging 'resources\perky_aa_browser.csv'
                if (Test-Path $perkyCSV) { Remove-Item $perkyCSV -Force; $removedCount++ }

                # 10. Dev artifacts: .pdb, .git, Source/
                Get-ChildItem $staging -Filter '*.pdb' -Recurse -File |
                    Remove-Item -Force -EA SilentlyContinue
                Get-ChildItem $staging -Filter '.git' -Recurse -Directory -Force -EA SilentlyContinue |
                    Remove-Item -Recurse -Force -EA SilentlyContinue
                Get-ChildItem $staging -Filter '.gitignore' -Recurse -File -Force -EA SilentlyContinue |
                    Remove-Item -Force -EA SilentlyContinue
                $sourceDir = Join-Path $staging 'Source'
                if (Test-Path $sourceDir) { Remove-Item $sourceDir -Recurse -Force }

                Write-Ok "Cleaned $removedCount sensitive/user-specific files from bundle"

                $zipPath = Join-Path $OutputDir "CoOptUI-EMU-v$Version.zip"
                New-ZipFromStaging $staging $zipPath
                $outputZips += $zipPath
            }
        }
    } finally {
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    }
}

# ------------------------------------------------------------------
# Stage 4b: Patcher standalone artifact
# ------------------------------------------------------------------

if ($patcherExePath -and (Test-Path $patcherExePath)) {
    Write-Stage 'Stage 4b: Patcher Standalone'
    # Copy patcher exe directly to output dir (users can grab just this)
    $patcherDst = Join-Path $OutputDir 'CoOptUIPatcher.exe'
    try {
        Copy-Item $patcherExePath -Destination $patcherDst -Force
    } catch {
        Write-Warning "Could not copy patcher to output (file may be in use): $_"
        Write-Warning "Close CoOptUIPatcher.exe and re-run, or copy manually from: $patcherExePath"
    }
    Write-Ok "Patcher copied to output: CoOptUIPatcher.exe"

    # Also create a small ZIP with just the patcher + readme
    $patcherStaging = Join-Path $env:TEMP "CoOptUI_patcher_$(Get-Random)"
    New-Item -ItemType Directory -Path $patcherStaging -Force | Out-Null
    try {
        Copy-Item $patcherExePath -Destination $patcherStaging -Force
        @(
            'CoOptUI Patcher'
            '==============='
            ''
            'Run CoOptUIPatcher.exe in your MacroQuest folder to update'
            'CoOpt UI (Lua scripts, macros, config templates, resources)'
            'without re-downloading the full EMU bundle.'
            ''
            'This only updates the CoOpt UI overlay files, NOT MacroQuest'
            'binaries, MQ2Mono, or E3Next.'
        ) | Set-Content (Join-Path $patcherStaging 'README.txt')
        $patcherZip = Join-Path $OutputDir "CoOptUIPatcher-v$Version.zip"
        New-ZipFromStaging $patcherStaging $patcherZip
        $outputZips += $patcherZip
        Write-Ok "Created: CoOptUIPatcher-v$Version.zip"
    } finally {
        if (Test-Path $patcherStaging) { Remove-Item $patcherStaging -Recurse -Force }
    }
}

# ------------------------------------------------------------------
# Stage 5: Release (optional)
# ------------------------------------------------------------------

if ($Release) {
    Write-Stage 'Stage 5: Release Pipeline'

    # --- Validate version ---
    if (-not $Version) {
        $currentLuaVersion = Read-CoOptVersion $RepoRoot
        $latestTag = (git -C $RepoRoot describe --tags --abbrev=0 2>$null)
        Write-Host ''
        Write-Host '  [ERROR] -Version is required for -Release.' -ForegroundColor Red
        Write-Host "    Current version.lua: $currentLuaVersion"
        if ($latestTag) { Write-Host "    Latest git tag:      $latestTag" }
        Write-Host '    Example: -Version ''1.0.0''' -ForegroundColor Yellow
        Write-Error 'Provide a -Version to release.'
    }

    $tag = "v$Version"

    # Check tag doesn't already exist
    $existingTag = git -C $RepoRoot tag --list $tag 2>$null
    if ($existingTag -and $existingTag.Trim()) {
        if ($DryRun) {
            Write-Warning "Tag '$tag' already exists — would need to delete before real release."
        } else {
            Write-Error "Tag '$tag' already exists. Delete it first: git tag -d $tag && git push origin :refs/tags/$tag"
        }
    }

    if ($DryRun) {
        Write-Info "[DRY RUN] Would bump version to $Version in version.lua"
        Write-Info "[DRY RUN] Would regenerate release manifests"
        Write-Info "[DRY RUN] Would commit manifests + version bump"
        Write-Info "[DRY RUN] Would create tag $tag"
        Write-Info "[DRY RUN] Would push master + $tag to origin"
        Write-Info "[DRY RUN] Would create draft release with:"
        foreach ($z in $outputZips) { Write-Info "  - $(Split-Path $z -Leaf)" }
        $standalonePatcherPath = Join-Path $OutputDir 'CoOptUIPatcher.exe'
        if (Test-Path $standalonePatcherPath) { Write-Info "  - CoOptUIPatcher.exe" }
    } else {
        # --- Bump version in lua/coopui/version.lua ---
        $versionLua = Join-Path $RepoRoot 'lua\coopui\version.lua'
        if (Test-Path $versionLua) {
            $content = Get-Content $versionLua -Raw
            $content = $content -replace '(PACKAGE\s*=\s*")[^"]*(")', "`${1}$Version`${2}"
            Set-Content $versionLua $content -NoNewline
            Write-Ok "Version bumped to $Version in version.lua"
        }

        # --- Generate manifests (so patcher can detect updates) ---
        # Pass the built plugin DLL path so patcher can also update the plugin
        $dllForManifest = if ($pluginDllPath -and (Test-Path $pluginDllPath)) { $pluginDllPath } else { '' }
        Generate-Manifests -RepoRoot $RepoRoot -PluginDllPath $dllForManifest -ReleaseTag "v$Version"

        # --- Git commit, tag, push ---
        Write-Info "Staging release files..."
        git -C $RepoRoot add release_manifest.json default_config_manifest.json lua/coopui/version.lua 2>$null

        $hasDiff = $true
        git -C $RepoRoot diff --cached --quiet 2>$null
        if ($LASTEXITCODE -eq 0) { $hasDiff = $false }

        # Commit
        if ($hasDiff) {
            git -C $RepoRoot commit -m "release: v$Version"
            if ($LASTEXITCODE -ne 0) { Write-Error 'git commit failed' }
            Write-Ok "Committed release: v$Version"
        }

        # Tag
        git -C $RepoRoot tag -a $tag -m "Release $tag"
        if ($LASTEXITCODE -ne 0) { Write-Error 'git tag failed' }

        # Push
        git -C $RepoRoot push origin master 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { Write-Error 'git push origin master failed' }
        git -C $RepoRoot push origin $tag 2>&1 | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { Write-Error "git push origin $tag failed" }
        Write-Ok "Pushed master + tag $tag to origin"

        # --- Create GitHub release ---
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
            Write-Warning 'gh CLI not found — skipping GitHub release. Install: https://cli.github.com/'
        } else {
            $ghRepo = 'CooptGaming/CooptUI'
            $artifacts = @()
            foreach ($z in $outputZips) {
                if (Test-Path $z) { $artifacts += $z }
            }
            $standalonePatcherPath = Join-Path $OutputDir 'CoOptUIPatcher.exe'
            if (Test-Path $standalonePatcherPath) { $artifacts += $standalonePatcherPath }
            # Upload plugin DLL as standalone release asset (patcher downloads it)
            if ($pluginDllPath -and (Test-Path $pluginDllPath)) {
                $dllCopy = Join-Path $OutputDir 'MQ2CoOptUI.dll'
                Copy-Item $pluginDllPath -Destination $dllCopy -Force
                $artifacts += $dllCopy
            }

            $ghArgs = @('release', 'create', $tag)
            $ghArgs += $artifacts
            $ghArgs += @('--repo', $ghRepo, '--title', "CoOpt UI $tag", '--generate-notes', '--draft')
            gh @ghArgs 2>&1 | ForEach-Object { Write-Host "  $_" }

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "GitHub release creation failed. Create manually: gh release create $tag"
            } else {
                Write-Ok "Draft release $tag created on GitHub"
                Write-Info "Review and publish: https://github.com/$ghRepo/releases/tag/$tag"
            }
        }
    }
}

# ------------------------------------------------------------------
# Save State
# ------------------------------------------------------------------

$state.cooptui.sourceHash = $currentCoOptHash
$state.version = $Version
Save-BuildState $OutputDir $state

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

$elapsed = (Get-Date) - $BuildStartTime

Write-Host ''
Write-Host '=== Build Complete ===' -ForegroundColor Cyan
Write-Host "  Version:  $Version"
Write-Host "  Output:   $OutputDir"
Write-Host "  Elapsed:  $([math]::Round($elapsed.TotalSeconds, 1))s"
Write-Host ''

if ($outputZips.Count -gt 0 -or ($patcherExePath -and (Test-Path (Join-Path $OutputDir 'CoOptUIPatcher.exe')))) {
    Write-Host '  Artifacts:' -ForegroundColor Green
    foreach ($z in $outputZips) {
        $sizeKB = [math]::Round((Get-Item $z).Length / 1KB, 0)
        Write-Host "    $(Split-Path $z -Leaf) -- ${sizeKB} KB"
    }
    $standalonePatcher = Join-Path $OutputDir 'CoOptUIPatcher.exe'
    if (Test-Path $standalonePatcher) {
        $pSizeKB = [math]::Round((Get-Item $standalonePatcher).Length / 1KB, 0)
        Write-Host "    CoOptUIPatcher.exe (standalone) -- ${pSizeKB} KB"
    }
}

$changes = @()
if ($mqBuildChanged) { $changes += 'MQ build' }
if ($e3BuildChanged) { $changes += 'E3Next' }
if ($pluginChanged) { $changes += 'plugin' }
if ($cooptuiChanged) { $changes += 'CoOptUI' }
if ($patcherChanged) { $changes += 'patcher' }
if ($changes.Count -eq 0) { $changes += 'none (all cached)' }
Write-Host "  Changed:  $($changes -join ', ')"
Write-Host ''
