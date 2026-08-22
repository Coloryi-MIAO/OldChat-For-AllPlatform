param(
  [Parameter(Mandatory = $true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$certPath = Join-Path $Output 'OldChatForAllPlatformWindows7CodeSigning.cer'
$pfxPath = Join-Path ([IO.Path]::GetTempPath()) ("OldChatForAllPlatformWindows7-{0}.pfx" -f [guid]::NewGuid())
$password = ConvertTo-SecureString 'oldchatlocalbuild' -AsPlainText -Force
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=OldChat For AllPlatform Windows 7, O=Coloryi-MIAO' -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(100)
Export-Certificate -Cert $cert -FilePath $certPath | Out-Null
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $password | Out-Null
Import-Certificate -FilePath $certPath -CertStoreLocation Cert:\CurrentUser\TrustedPublisher | Out-Null
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits" -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $signtool) { throw '找不到 signtool.exe' }
try {
  $signed = @(Get-ChildItem $Output -Recurse -Include *.exe,*.dll)
  if ($signed.Count -eq 0) { throw '没有找到需要签名的 Windows 文件' }
  $signed | ForEach-Object {
    & $signtool.FullName sign /fd SHA256 /f $pfxPath /p oldchatlocalbuild $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "签名失败：$($_.FullName)" }
  }
  $statusPath = Join-Path $Output 'OldChatForAllPlatformWindows7签名信息.txt'
  "证书：OldChat For AllPlatform Windows 7`n主题：$($cert.Subject)`n指纹：$($cert.Thumbprint)`n已签名文件数：$($signed.Count)" | Set-Content $statusPath
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $pfxPath
}
