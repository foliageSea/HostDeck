param(
  [string]$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = 'Stop'
$RootDir = (Resolve-Path -LiteralPath $RootDir).Path

function Invoke-Native {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  Push-Location -LiteralPath $RootDir
  try {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Command failed: $Command $($Arguments -join ' ')"
    }
  } finally {
    Pop-Location
  }
}

$buildDir = Join-Path $RootDir 'build\server'
$uiDir = Join-Path $RootDir 'host-deck-ui'

Write-Host 'Building frontend...'
Invoke-Native -Command pnpm -Arguments @('--dir', "$uiDir", 'install', '--frozen-lockfile')
Invoke-Native -Command pnpm -Arguments @('--dir', "$uiDir", 'build')

Write-Host 'Resolving Dart dependencies...'
Invoke-Native -Command dart -Arguments @('pub', 'get')

Write-Host 'Building Dart CLI bundle...'
$pubspecPath = Join-Path $RootDir 'pubspec.yaml'
$versionLine = Get-Content -LiteralPath $pubspecPath | Where-Object { $_ -match '^version:\s*[^\s#]+' } | Select-Object -First 1
if ($versionLine -notmatch '^version:\s*(?<version>[^\s#]+)') {
  throw "Unable to resolve the application version from $pubspecPath"
}
$appVersion = $Matches.version
if (Test-Path -LiteralPath $buildDir) {
  Remove-Item -LiteralPath $buildDir -Recurse -Force
}
Invoke-Native -Command dart -Arguments @('build', 'cli', '--target', 'bin/server.dart', '--output', $buildDir)
Invoke-Native -Command node -Arguments @((Join-Path $RootDir 'scripts\sidecar_assets.mjs'), 'stage', (Join-Path $buildDir 'bundle'))
Invoke-Native -Command node -Arguments @((Join-Path $RootDir 'scripts\build_ai.mjs'), (Join-Path $buildDir 'bundle'))
Set-Content -LiteralPath (Join-Path $buildDir 'bundle\VERSION') -Value $appVersion -NoNewline -Encoding ascii
Copy-Item (Join-Path $RootDir 'LICENSE') (Join-Path $buildDir 'bundle\LICENSE')
Copy-Item (Join-Path $RootDir 'THIRD_PARTY_NOTICES.md') (Join-Path $buildDir 'bundle\THIRD_PARTY_NOTICES.md')

$targetWebDir = Join-Path $buildDir 'bundle\web'
if (Test-Path $targetWebDir) {
  Remove-Item $targetWebDir -Recurse -Force
}
New-Item -ItemType Directory -Path $targetWebDir | Out-Null

Write-Host 'Copying web assets...'
Copy-Item "$uiDir\dist\*" $targetWebDir -Recurse

$startBatPath = Join-Path $buildDir 'start_server.bat'
$startBatContent = @'
@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "SERVER_EXE=%SCRIPT_DIR%bundle\bin\server.exe"
set "WEB_DIR=%SCRIPT_DIR%bundle\web"

if not exist "%SERVER_EXE%" (
  echo [ERROR] Server executable not found: %SERVER_EXE%
  exit /b 1
)

set "HOST=%~1"
if "%HOST%"=="" set "HOST=0.0.0.0"

set "PORT=%~2"
if "%PORT%"=="" set "PORT=8080"

set "DATA_DIR=%~3"
if "%DATA_DIR%"=="" set "DATA_DIR=%SCRIPT_DIR%data"

echo Starting server with:
echo   host     = %HOST%
echo   port     = %PORT%
echo   web-dir  = %WEB_DIR%
echo   data-dir = %DATA_DIR%
echo.

"%SERVER_EXE%" --host "%HOST%" --port "%PORT%" --web-dir "%WEB_DIR%" --data-dir "%DATA_DIR%"

endlocal
'@
Set-Content -Path $startBatPath -Value $startBatContent -Encoding Ascii

Write-Host "Done. Output directory: $buildDir"
