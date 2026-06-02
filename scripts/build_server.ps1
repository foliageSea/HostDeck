param(
  [string]$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = 'Stop'

function Invoke-Native {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
  )

  & $Command @Args
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed: $Command $($Args -join ' ')"
  }
}

$buildDir = Join-Path $RootDir 'build\server'
$uiDir = Join-Path $RootDir 'host-deck-ui'

Write-Host 'Building frontend...'
Invoke-Native -Command pnpm -Args @('--dir', "$uiDir", 'install')
Invoke-Native -Command pnpm -Args @('--dir', "$uiDir", 'build')

Write-Host 'Resolving Dart dependencies...'
Invoke-Native -Command flutter -Args @('pub', 'get')

Write-Host 'Building Dart CLI bundle...'
if (Test-Path $buildDir) {
  Remove-Item $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $buildDir | Out-Null
Invoke-Native -Command dart -Args @('build', 'cli', '--target', "$RootDir\bin\server.dart", '--output', "$buildDir")

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
