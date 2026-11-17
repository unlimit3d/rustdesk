[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$installRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$connectionProfile = Get-Content -LiteralPath (Join-Path $installRoot 'connection-profile.json') -Raw | ConvertFrom-Json
if ($connectionProfile.role -ne 'outgoing') {
    @{supported = $false} | ConvertTo-Json -Compress
    return
}
. (Join-Path $PSScriptRoot 'Update-Protocol.ps1')
$api = [uri]$connectionProfile.api_server
if ($api.Scheme -ne 'https' -or $api.UserInfo -or $api.Query -or $api.Fragment -or $api.AbsolutePath -ne '/') {
    throw 'Unsupported update server URL'
}
$installed = Get-Content -LiteralPath (Join-Path $installRoot 'client-release.json') -Raw | ConvertFrom-Json
$publicKey = Get-Content -LiteralPath (Join-Path $installRoot 'update-public-key.xml') -Raw
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('CrhRustDesk-update-check-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        Get-CrhUpdateFile -Url ($api.GetLeftPart([UriPartial]::Authority) + '/crhrustdesk/updates/latest.json') -Destination $temporary -Limit 32768
    } catch [Net.WebException] {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) {
            @{supported = $true; available = $false; installed_revision = $installed.revision} | ConvertTo-Json -Compress
            return
        }
        throw
    }
    $release = Read-CrhUpdate -EnvelopeBytes ([IO.File]::ReadAllBytes($temporary)) -PublicKeyXml $publicKey -ApiServer $api -InstalledRevision $installed.revision
    if ($null -eq $release) {
        @{supported = $true; available = $false; installed_revision = $installed.revision} | ConvertTo-Json -Compress
    } else {
        @{supported = $true; available = $true; version = $release.version; revision = $release.revision; url = $release.url; installed_revision = $installed.revision} | ConvertTo-Json -Compress
    }
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
