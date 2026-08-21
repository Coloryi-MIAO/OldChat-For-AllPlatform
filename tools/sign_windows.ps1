param(
  [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$certPath = Join-Path $Output 'OldChatForAllPlatformCodeSigning.cer'
$pfxPath = Join-Path ([IO.Path]::GetTempPath()) ("OldChatForAllPlatform-{0}.pfx" -f [guid]::NewGuid())
$password = ConvertTo-SecureString 'oldchatlocalbuild' -AsPlainText -Force
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=OldChat For AllPlatform Release, O=Coloryi-MIAO' -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(100)
Export-Certificate -Cert $cert -FilePath $certPath | Out-Null
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $password | Out-Null
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits" -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $signtool) { throw 'signtool.exe was not found on the Windows runner.' }
try {
  $signed = @(Get-ChildItem $Output -Recurse -Include *.exe,*.dll)
  if ($signed.Count -eq 0) { throw 'No Windows executable was found to sign.' }
  $signed | ForEach-Object {
    & $signtool.FullName sign /fd SHA256 /f $pfxPath /p oldchatlocalbuild $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signing failed for $($_.FullName)" }
  }
  $statusPath = Join-Path $Output 'OldChatForAllPlatformwindows.signing.txt'
  "Certificate: OldChat For AllPlatform Release`nSubject: $($cert.Subject)`nThumbprint: $($cert.Thumbprint)`nFiles signed: $($signed.Count)" | Set-Content $statusPath
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $pfxPath
}
