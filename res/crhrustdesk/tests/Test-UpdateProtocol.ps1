$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../updater/Update-Protocol.ps1')
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(3072)
$rsa.PersistKeyInCsp = $false
try {
    $manifest = @{
        schema = 1; product = 'CrhRustDesk'; platform = 'windows-x64'; revision = 2L
        version = '1.5.3'; expires = [DateTime]::UtcNow.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
        url = 'https://172.16.1.83:8443/crhrustdesk/updates/releases/2/CrhRustDesk-Setup.exe'
        size = 123; sha256 = ('a' * 64); dll_sha256 = ('b' * 64)
    }
    function Sign-Envelope($value) {
        $payload = [Text.Encoding]::UTF8.GetBytes(($value | ConvertTo-Json -Compress))
        $json = @{ payload = [Convert]::ToBase64String($payload); signature = [Convert]::ToBase64String($rsa.SignData($payload, 'SHA256')) } | ConvertTo-Json -Compress
        return [Text.Encoding]::UTF8.GetBytes($json)
    }
    function Read-Release([byte[]]$bytes, [long]$revision = 1) {
        Read-CrhUpdate -EnvelopeBytes $bytes -PublicKeyXml $rsa.ToXmlString($false) -ApiServer 'https://172.16.1.83:8443' -InstalledRevision $revision
    }
    function Assert-Rejected([scriptblock]$action) {
        $rejected = $false
        try { & $action | Out-Null } catch { $rejected = $true }
        if (-not $rejected) { throw 'Invalid update was accepted' }
    }
    $valid = Sign-Envelope $manifest
    if ((Read-Release $valid).revision -ne 2 -or $null -ne (Read-Release $valid 2)) { throw 'Revision check failed' }
    Write-Output 'PASS: signed new revision accepted; already-applied revision skipped'
    $forged = [Text.Encoding]::UTF8.GetString($valid) | ConvertFrom-Json
    $forged.signature = [Convert]::ToBase64String((New-Object byte[] 384))
    Assert-Rejected { Read-Release ([Text.Encoding]::UTF8.GetBytes(($forged | ConvertTo-Json -Compress))) }
    Write-Output 'PASS: forged signature rejected'
    foreach ($case in @('origin', 'expiry', 'size')) {
        $invalid = $manifest.Clone()
        switch ($case) {
            'origin' { $invalid.url = 'https://untrusted.invalid/crhrustdesk/updates/releases/2/CrhRustDesk-Setup.exe' }
            'expiry' { $invalid.expires = [DateTime]::UtcNow.AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') }
            'size' { $invalid.size = 536870913L }
        }
        Assert-Rejected { Read-Release (Sign-Envelope $invalid) }
    }
    Write-Output 'PASS: signed invalid origin, expired release and oversized release rejected'
} finally { $rsa.Dispose() }
