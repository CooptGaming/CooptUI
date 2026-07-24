param(
    [string]$EqDir = 'C:\MIS\PerkyCrew-EQ - Copy',
    [string]$MqDir = 'C:\MIS\E3NextAndMQNextBinary-main'
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot

if (-not (Test-Path (Join-Path $EqDir 'uifiles'))) { throw "Not an EQ folder (no uifiles\): $EqDir" }
if (-not (Test-Path (Join-Path $MqDir 'lua')))     { throw "Not an MQ folder (no lua\): $MqDir" }

$skinDir = Join-Path $EqDir 'uifiles\coopt_poc'
New-Item -ItemType Directory -Force $skinDir | Out-Null
Copy-Item (Join-Path $src 'EQUI_MerchantWnd.xml') $skinDir -Force
Copy-Item (Join-Path $src 'coopt_poc.lua') (Join-Path $MqDir 'lua') -Force

Write-Host "Installed skin  -> $skinDir"
Write-Host "Installed lua   -> $(Join-Path $MqDir 'lua\coopt_poc.lua')"
Write-Host "In game: /loadskin coopt_poc   then   /lua run coopt_poc"
