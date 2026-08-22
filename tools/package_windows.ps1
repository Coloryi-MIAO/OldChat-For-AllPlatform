param(
  [Parameter(Mandatory = $true)][ValidateSet('x64')][string]$Architecture,
  [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root
flutter build windows --release
$bundle = 'build/windows/x64/runner/Release'
if (-not (Test-Path $bundle)) { throw "Flutter Windows 7 bundle was not produced: $bundle" }
New-Item -ItemType Directory -Force -Path $Output | Out-Null
Copy-Item -Recurse -Force "$bundle\*" "$Output\"
$builtExecutables = @(Get-ChildItem -Path $Output -Filter '*.exe' -File)
if ($builtExecutables.Count -eq 0) { throw "Flutter Windows executable was not produced in: $Output" }
$namedExecutable = Join-Path $Output "OldChatForAllPlatformwindows7$Architecture.exe"
if ($builtExecutables[0].FullName -ne $namedExecutable) { Move-Item -Force $builtExecutables[0].FullName $namedExecutable }
& "$root\tools\sign_windows.ps1" -Output $Output
$zip = "OldChatForAllPlatformwindows7$Architecture.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$Output\*" -DestinationPath $zip -Force
Write-Output "Windows 7 package: $zip"
