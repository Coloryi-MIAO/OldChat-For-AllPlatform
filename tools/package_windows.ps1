[CmdletBinding()]
param(
  [ValidateSet("x64")]
  [string]$Architecture = "x64",
  [Parameter(Mandatory = $true)]
  [string]$Output
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location -LiteralPath $root

if ([string]::IsNullOrWhiteSpace($Output)) { throw "Output directory is required" }
$outputPath = [IO.Path]::GetFullPath($Output)
$archivePath = Join-Path $root "OldChatForAllPlatformwindows7$Architecture.zip"
$signScript = Join-Path $root "tools\sign_windows.ps1"
$flutterBundle = Join-Path $root "build\windows\x64\runner\Release"
$executableName = "OldChatForAllPlatformwindows7$Architecture.exe"

flutter clean
if ($LASTEXITCODE -ne 0) { throw "flutter clean failed with exit code $LASTEXITCODE" }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed with exit code $LASTEXITCODE" }
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed with exit code $LASTEXITCODE" }

if (-not (Test-Path -LiteralPath $flutterBundle -PathType Container)) {
  throw "Flutter release bundle was not produced: $flutterBundle"
}

if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Recurse -Force }
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
Copy-Item -Path (Join-Path $flutterBundle "*") -Destination $outputPath -Recurse -Force

$builtExecutables = @(Get-ChildItem -LiteralPath $outputPath -Filter "*.exe" -File)
if ($builtExecutables.Count -ne 1) {
  throw "Expected exactly one executable in $outputPath, found $($builtExecutables.Count)"
}
$targetExecutable = Join-Path $outputPath $executableName
if ($builtExecutables[0].FullName -ne $targetExecutable) {
  Move-Item -LiteralPath $builtExecutables[0].FullName -Destination $targetExecutable -Force
}

if (Test-Path -LiteralPath $signScript -PathType Leaf) {
  & $signScript -Output $outputPath
  if ($LASTEXITCODE -ne 0) { throw "Windows signing step failed with exit code $LASTEXITCODE" }
}

if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
Compress-Archive -Path (Join-Path $outputPath "*") -DestinationPath $archivePath -CompressionLevel Optimal -Force

if (-not (Test-Path -LiteralPath $targetExecutable -PathType Leaf)) { throw "Executable was not renamed correctly" }
if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Archive was not created" }
Write-Output "Executable: $targetExecutable"
Write-Output "Archive: $archivePath"
