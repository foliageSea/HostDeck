param(
  [string]$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = 'Stop'

$buildDir = Join-Path $RootDir 'build\server'
$uiDir = Join-Path $RootDir 'ssh-tool-ui'

Write-Host 'Building frontend...'
pnpm --dir "$uiDir" install
pnpm --dir "$uiDir" build

Write-Host 'Resolving Dart dependencies...'
flutter pub get

Write-Host 'Building Dart CLI bundle...'
if (Test-Path $buildDir) {
  Remove-Item $buildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $buildDir | Out-Null
dart build cli --target "$RootDir\bin\server.dart" -o $buildDir

$targetWebDir = Join-Path $buildDir 'bundle\web'
if (Test-Path $targetWebDir) {
  Remove-Item $targetWebDir -Recurse -Force
}
New-Item -ItemType Directory -Path $targetWebDir | Out-Null

Write-Host 'Copying web assets...'
Copy-Item "$uiDir\dist\*" $targetWebDir -Recurse

Write-Host "Done. Output directory: $buildDir"
