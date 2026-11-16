[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [string]$OutputDirectory,
    [long]$ReleaseRevision = [long]([DateTime]::UtcNow.ToString('yyyyMMddHHmmss')),
    [string]$Iscc = 'C:/Program Files (x86)/Inno Setup 6/ISCC.exe',
    [ValidatePattern('^[A-Za-z0-9.:-]+$')][string]$IdServer = '172.29.0.96',
    [ValidatePattern('^[A-Za-z0-9.:-]+$')][string]$RelayServer = '172.29.0.96:21117',
    [ValidatePattern('^\d{1,3}(\.\d{1,3}){3}$')][string]$ControllerAddress = '172.29.0.96',
    [uri]$ApiServer = 'https://172.29.0.96:8443'
)

$ErrorActionPreference = 'Stop'
$BundlePath = (Resolve-Path -LiteralPath $BundlePath).Path
if (-not (Test-Path -LiteralPath $Iscc)) { throw 'Install Inno Setup with ISCC.exe before building this package' }
$compilerLicense = Join-Path (Split-Path -Parent $Iscc) 'license.txt'
if (-not (Test-Path -LiteralPath $compilerLicense)) { throw 'Inno Setup license.txt is missing' }
if (-not $ApiServer.IsAbsoluteUri -or $ApiServer.Scheme -ne 'https' -or $ApiServer.UserInfo -or $ApiServer.Port -eq 21114) {
    throw 'Use an HTTPS API URL without credentials, on port 443 or a reverse-proxy port such as 8443'
}
foreach ($file in @('CrhRustDesk.exe', 'CrhRustDesk.ico', 'librustdesk.dll', 'flutter_windows.dll', 'data/app.so', 'data/icudtl.dat', 'WindowInjection.dll', 'CrhRustDesk-dev-root.crt', 'server-public-key.txt', 'permit-public-key.txt', 'LICENCE')) {
    if (-not (Test-Path -LiteralPath (Join-Path $BundlePath $file))) { throw "Required bundle file is missing: $file" }
}
$privateFiles = Get-ChildItem -LiteralPath $BundlePath -Recurse -File | Where-Object {
    $_.Name -in @('root.key', 'intermediate.key', 'id_ed25519', 'permit.key', 'rustdeskapi.db', 'update-private-key.xml') -or $_.Name -like '*.credential.xml'
}
if ($privateFiles) { throw 'A client setup must not contain private server files' }
$clientStrings = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $BundlePath 'librustdesk.dll')))
if (-not $clientStrings.Contains('crhrustdesk-role')) { throw 'Build the client with installation-role support before packaging this installer' }
if (-not $clientStrings.Contains('crhrustdesk-update-ready')) { throw 'Build the client with managed-update readiness support before packaging' }
$clientStrings = $null
foreach ($file in @('update-public-key.xml', 'updater/Invoke-ClientUpdate.ps1', 'updater/Register-AutoUpdate.ps1', 'updater/Update-Protocol.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $BundlePath $file))) { throw "Missing auto-update component: $file" }
}
if ($ReleaseRevision -le 0) { throw 'Release revision must be positive and greater than previously published revisions' }
$key = (Get-Content -LiteralPath (Join-Path $BundlePath 'server-public-key.txt') -Raw).Trim()
if ($key -notmatch '^[A-Za-z0-9+/]{43}=$') { throw 'Invalid Ed25519 server public key' }
$hash = (Get-FileHash -LiteralPath (Join-Path $BundlePath 'CrhRustDesk-dev-root.crt') -Algorithm SHA256).Hash
$version = (Get-Item -LiteralPath (Join-Path $BundlePath 'CrhRustDesk.exe')).VersionInfo.ProductVersion
if ($version -notmatch '^(\d+\.\d+\.\d+)') { throw 'Could not read the client version' }
$appVersion = $Matches[1]
$releaseJson = @{ schema = 1; revision = $ReleaseRevision; version = $appVersion } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $BundlePath 'client-release.json'), $releaseJson, [Text.UTF8Encoding]::new($false))
$updateKeyHash = (Get-FileHash -LiteralPath (Join-Path $BundlePath 'update-public-key.xml') -Algorithm SHA256).Hash
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $repo 'target/CrhRustDesk-EasySetup' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'installer/CrhRustDesk.iss'))
$script = Join-Path $output 'CrhRustDesk.generated.iss'
[IO.File]::WriteAllText($script, $source, [Text.UTF8Encoding]::new($true))
& $Iscc "/DBundleRoot=$BundlePath" "/DAppVersion=$appVersion" "/DCertificateHash=$hash" "/DUpdateKeyHash=$updateKeyHash" "/DServerKey=$key" "/DIdServer=$IdServer" "/DRelayServer=$RelayServer" "/DControllerAddress=$ControllerAddress" "/DApiServer=$($ApiServer.AbsoluteUri.TrimEnd('/'))" "/O$output" $script
if ($LASTEXITCODE -ne 0) { throw 'CrhRustDesk setup compilation failed' }
$setup = Join-Path $output 'CrhRustDesk-Setup.exe'
if (-not (Test-Path -LiteralPath $setup)) { throw 'The setup executable was not created' }
$setupHash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
"$setupHash  CrhRustDesk-Setup.exe" | Set-Content -LiteralPath "$setup.sha256" -Encoding ASCII
Copy-Item -LiteralPath $compilerLicense -Destination (Join-Path $output 'INNO-LICENSE.txt') -Force
foreach ($document in @('INSTALL-EASY-TH.md', 'LAN-SETUP-TH.md', 'Build-EasySetup.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $document) -Destination $output -Force
}
New-Item -ItemType Directory -Path (Join-Path $output 'installer') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'installer/CrhRustDesk.iss') -Destination (Join-Path $output 'installer') -Force
Write-Host "Easy installer: $setup"
