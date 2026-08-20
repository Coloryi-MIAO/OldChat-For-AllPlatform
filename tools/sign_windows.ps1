param(
  [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$certPath = Join-Path $Output 'OldChatForAllPlatform-CodeSigning.cer'
$pfxPath = Join-Path $Output 'OldChatForAllPlatform-CodeSigning.pfx'
$password = ConvertTo-SecureString 'oldchatlocalbuild' -AsPlainText -Force
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=OldChat For AllPlatform Release, O=Coloryi-MIAO' -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(100)
Export-Certificate -Cert $cert -FilePath $certPath | Out-Null
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $password | Out-Null
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits" -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $signtool) { throw 'signtool.exe was not found on the Windows runner.' }
Get-ChildItem $Output -Recurse -Filter *.exe | ForEach-Object {
  & $signtool.FullName sign /fd SHA256 /f $pfxPath /p oldchatlocalbuild $_.FullName
  if ($LASTEXITCODE -ne 0) { throw "Signing failed for $($_.FullName)" }
}
