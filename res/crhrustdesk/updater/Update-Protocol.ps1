$ErrorActionPreference = 'Stop'

function Read-CrhUpdate {
    param([byte[]]$EnvelopeBytes, [string]$PublicKeyXml, [uri]$ApiServer, [long]$InstalledRevision)
    if ($EnvelopeBytes.Length -gt 32768) { throw 'Update envelope is too large' }
    $envelope = [Text.Encoding]::UTF8.GetString($EnvelopeBytes) | ConvertFrom-Json
    $payload = [Convert]::FromBase64String($envelope.payload)
    $signature = [Convert]::FromBase64String($envelope.signature)
    $rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($PublicKeyXml)
        if ($rsa.KeySize -lt 3072 -or -not $rsa.VerifyData($payload, 'SHA256', $signature)) { throw 'Invalid update signature' }
    } finally { $rsa.Dispose() }
    $release = [Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json
    if ($release.schema -ne 1 -or $release.product -cne 'CrhRustDesk' -or $release.platform -cne 'windows-x64') { throw 'Wrong update product or platform' }
    if ($release.revision -isnot [long] -and $release.revision -isnot [int]) { throw 'Invalid update revision' }
    if ($release.revision -le 0 -or $release.sha256 -cnotmatch '^[a-f0-9]{64}$' -or $release.dll_sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid update hashes or revision' }
    if ($release.size -isnot [long] -and $release.size -isnot [int]) { throw 'Invalid update size' }
    if ($release.size -lt 1 -or $release.size -gt 536870912) { throw 'Update exceeds size limit' }
    if ($release.version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw 'Invalid update version' }
    $expires = [DateTimeOffset]::ParseExact($release.expires, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
    if ($expires -le [DateTimeOffset]::UtcNow -or $expires -gt [DateTimeOffset]::UtcNow.AddDays(32)) { throw 'Expired or invalid update lifetime' }
    $url = [uri]$release.url
    $expectedPath = '/crhrustdesk/updates/releases/' + $release.revision + '/CrhRustDesk-Setup.exe'
    if ($ApiServer.Scheme -ne 'https' -or $url.Scheme -ne 'https' -or $url.Authority -cne $ApiServer.Authority -or $url.UserInfo -or $url.Query -or $url.Fragment -or $url.AbsolutePath -cne $expectedPath) { throw 'Update URL is outside the configured server' }
    if ($release.revision -le $InstalledRevision) { return $null }
    return $release
}

function Get-CrhUpdateFile {
    param([uri]$Url, [string]$Destination, [long]$Limit)
    $request = [Net.HttpWebRequest]::Create($Url)
    $request.AllowAutoRedirect = $false
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 30000
    $response = $request.GetResponse()
    try {
        if ([int]$response.StatusCode -ne 200 -or $response.ContentLength -gt $Limit) { throw 'Invalid update response' }
        $inputStream = $response.GetResponseStream()
        $outputStream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $buffer = New-Object byte[] 65536
            $total = 0L
            while (($count = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $total += $count
                if ($total -gt $Limit) { throw 'Update download exceeds size limit' }
                $outputStream.Write($buffer, 0, $count)
            }
        } finally { $outputStream.Dispose(); $inputStream.Dispose() }
    } finally { $response.Dispose() }
}
