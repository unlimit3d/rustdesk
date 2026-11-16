[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BundlePath,
    [Parameter(Mandatory = $true)][string]$SetupPath,
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [uri]$ApiServer = 'https://172.16.1.83:8443'
)
$ErrorActionPreference = 'Stop'
if ($ApiServer.Scheme -ne 'https' -or $ApiServer.UserInfo -or $ApiServer.Query -or $ApiServer.Fragment -or $ApiServer.AbsolutePath -ne '/') { throw 'Use an HTTPS server origin' }
$BundlePath = (Resolve-Path -LiteralPath $BundlePath).Path
$SetupPath = (Resolve-Path -LiteralPath $SetupPath).Path
$release = Get-Content -LiteralPath (Join-Path $BundlePath 'client-release.json') -Raw | ConvertFrom-Json
if ($release.revision -le 0 -or $release.version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw 'Invalid bundle release metadata' }
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
try {
    $rsa.PersistKeyInCsp = $false
    $rsa.FromXmlString((Get-Content -LiteralPath $PrivateKeyPath -Raw))
    $publicKey = Get-Content -LiteralPath (Join-Path $BundlePath 'update-public-key.xml') -Raw
    if ($rsa.KeySize -lt 3072 -or $rsa.ToXmlString($false) -cne $publicKey.Trim()) { throw 'Signing key does not match the client update trust key' }
    $manifest = [ordered]@{
        schema = 1; product = 'CrhRustDesk'; platform = 'windows-x64'
        revision = [long]$release.revision; version = $release.version
        expires = [DateTime]::UtcNow.AddDays(30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        url = $ApiServer.GetLeftPart([UriPartial]::Authority) + '/crhrustdesk/updates/releases/' + $release.revision + '/CrhRustDesk-Setup.exe'
        size = (Get-Item -LiteralPath $SetupPath).Length
        sha256 = (Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash.ToLowerInvariant()
        dll_sha256 = (Get-FileHash -LiteralPath (Join-Path $BundlePath 'librustdesk.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $payload = [Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Compress))
    $envelope = @{ payload = [Convert]::ToBase64String($payload); signature = [Convert]::ToBase64String($rsa.SignData($payload, 'SHA256')) }
} finally { $rsa.Dispose() }
$releaseDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ('releases/' + $release.revision)
if (Test-Path -LiteralPath $releaseDirectory) { throw 'This revision already exists; build a new revision' }
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
Copy-Item -LiteralPath $SetupPath -Destination (Join-Path $releaseDirectory 'CrhRustDesk-Setup.exe')
[IO.File]::WriteAllText((Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'latest.json'), ($envelope | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
Write-Output 'Signed update files prepared. Upload only latest.json and releases/ to the update server.'
