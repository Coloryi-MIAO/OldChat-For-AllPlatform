param(
  [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
  [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
if ($Architecture -eq 'arm64') {
  flutter build windows --release --target-platform windows-arm64
  $bundle = 'build/windows/arm64/runner/Release'
} else {
  flutter build windows --release --target-platform windows-x64
  $bundle = 'build/windows/x64/runner/Release'
}
New-Item -ItemType Directory -Force -Path $Output | Out-Null
Copy-Item -Recurse -Force "$bundle\*" "$Output\"
$zip = "OldChatForAllPlatformwindows$Architecture.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$Output\*" -DestinationPath $zip -Force
Write-Output "Windows package: $zip"
