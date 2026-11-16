[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$stateRoot = Join-Path $env:ProgramData 'CrhRustDesk-Updater'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -ne 'S-1-5-18') { throw 'The updater must run through its SYSTEM scheduled task' }
. (Join-Path $PSScriptRoot 'Update-Protocol.ps1')
$lock = $null
try {
    # The installer creates this directory with access restricted to SYSTEM and Administrators.
    if (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'applied.json'))) { throw 'Updater state has not been provisioned' }
    if ((Get-Item -LiteralPath $stateRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Updater state directory is a reparse point' }
    $lock = [IO.File]::Open((Join-Path $stateRoot 'update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $connectionProfile = Get-Content -LiteralPath (Join-Path $installRoot 'connection-profile.json') -Raw | ConvertFrom-Json
    $api = [uri]$connectionProfile.api_server
    if ($api.Scheme -ne 'https' -or $api.UserInfo -or $api.Query -or $api.Fragment -or $api.AbsolutePath -ne '/') { throw 'Unsupported update server URL' }
    $state = Get-Content -LiteralPath (Join-Path $stateRoot 'applied.json') -Raw | ConvertFrom-Json
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $manifestPath = Join-Path $stateRoot 'latest.json.part'
    if (Test-Path -LiteralPath $manifestPath) { Remove-Item -LiteralPath $manifestPath }
    try {
        Get-CrhUpdateFile -Url ($api.GetLeftPart([UriPartial]::Authority) + '/crhrustdesk/updates/latest.json') -Destination $manifestPath -Limit 32768
    } catch [Net.WebException] {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { Write-Output 'No managed release has been published'; exit 0 }
        throw
    }
    $publicKey = Get-Content -LiteralPath (Join-Path $installRoot 'update-public-key.xml') -Raw
    $release = Read-CrhUpdate -EnvelopeBytes ([IO.File]::ReadAllBytes($manifestPath)) -PublicKeyXml $publicKey -ApiServer $api -InstalledRevision $state.revision
    if ($null -eq $release) { exit 0 }
    function Test-ClientIdle {
        if ($connectionProfile.role -eq 'outgoing') {
            # Operator installations have no receiving service; wait until their UI is closed.
            $processes = @(Get-CimInstance Win32_Process -Filter "Name='CrhRustDesk.exe'")
            return $processes.Count -eq 0
        }
        if ($connectionProfile.role -ne 'incoming') { throw 'Unknown installation role' }
        $result = & (Join-Path $installRoot 'CrhRustDesk.exe') --crhrustdesk-update-ready
        return $LASTEXITCODE -eq 0 -and @($result).Contains('READY')
    }
    if (-not (Test-ClientIdle)) { Write-Output 'Update deferred: client is busy or its idle state cannot be verified'; exit 0 }
    $setup = Join-Path $stateRoot 'CrhRustDesk-Setup.exe'
    if (Test-Path -LiteralPath $setup) { Remove-Item -LiteralPath $setup }
    Get-CrhUpdateFile -Url $release.url -Destination $setup -Limit $release.size
    if ((Get-Item -LiteralPath $setup).Length -ne $release.size -or (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash -ine $release.sha256) { throw 'Downloaded installer does not match the signed release' }
    if (-not (Test-ClientIdle)) { Write-Output 'Update deferred: a session started during download'; exit 0 }
    $process = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CRHUPDATE=1' -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Update installer failed: $($process.ExitCode)" }
    if ((Get-FileHash -LiteralPath (Join-Path $installRoot 'librustdesk.dll') -Algorithm SHA256).Hash -ine $release.dll_sha256) { throw 'Installed client does not match the signed release' }
    $installed = Get-Content -LiteralPath (Join-Path $installRoot 'client-release.json') -Raw | ConvertFrom-Json
    if ($installed.revision -ne $release.revision) { throw 'Installed release revision does not match' }
    $newState = Join-Path $stateRoot 'applied.json.new'
    [IO.File]::WriteAllText($newState, ($release | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $newState -Destination (Join-Path $stateRoot 'applied.json') -Force
    Write-Output "CrhRustDesk updated to revision $($release.revision)"
} catch {
    Write-Error $_
    exit 1
} finally { if ($lock) { $lock.Dispose() } }
