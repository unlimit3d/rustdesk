[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ToolsRoot,
    [System.Net.IPAddress]$ServerAddress = '127.0.0.1'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($ServerAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'This dev server launcher requires an IPv4 address'
}
$publicHost = $ServerAddress.IPAddressToString
$ToolsRoot = [IO.Path]::GetFullPath($ToolsRoot)
$root = Join-Path $ToolsRoot 'dev-server'
New-Item -ItemType Directory -Path $root -Force | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls.exe $root /inheritance:r /grant:r "*${identity}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not restrict permissions on the server directory' }
$downloads = Join-Path $ToolsRoot 'downloads'
New-Item -ItemType Directory -Path $downloads -Force | Out-Null
$packages = @(
    @{
        Url = 'https://github.com/lejianwen/rustdesk-api/releases/download/v2.7/windows-amd64.zip'
        File = 'rustdesk-api-v2.7-windows-amd64.zip'
        Hash = 'ac6a54ed9ed5fec229f649802178f65d2f82d068d1e4711c7a27066fd2caabd9'
        Destination = 'api'
    },
    @{
        Url = 'https://github.com/lejianwen/rustdesk-server/releases/download/v0.1.2/rustdesk-server-windows-x86_64-unsigned.zip'
        File = 'rustdesk-server-v0.1.2-windows.zip'
        Hash = '97fa1a7040518f133f0ef56e1024c65a9aef59ee7fb4cdeec1b1d349a9914ddd'
        Destination = 'transport'
    }
)
$apiDir = Join-Path $root 'api/release'
$transportDir = Join-Path $root 'transport/x86_64'
$executables = @((Join-Path $apiDir 'apimain.exe'), (Join-Path $transportDir 'hbbs.exe'), (Join-Path $transportDir 'hbbr.exe'))
foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
    if ($process.Path -and $process.Path -in $executables) {
        throw 'A CrhRustDesk dev server process is already running. Stop it before restarting.'
    }
}
if (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in 21114..21119 }) {
    throw 'A required port in 21114-21119 is already listening. Existing services were left running.'
}
if (Get-NetUDPEndpoint -LocalPort 21116 -ErrorAction SilentlyContinue) {
    throw 'UDP port 21116 is already in use. Existing services were left running.'
}
foreach ($package in $packages) {
    $archive = Join-Path $downloads $package.File
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest -Uri $package.Url -OutFile $archive -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $package.Hash) {
        throw "Archive SHA256 mismatch: $($package.File)"
    }
    $destination = Join-Path $root $package.Destination
    if (-not (Test-Path -LiteralPath $destination)) {
        Expand-Archive -LiteralPath $archive -DestinationPath $destination
    }
}

function New-ProtectedCredential([string]$Name, [string]$Path) {
    if (Test-Path -LiteralPath $Path) { return Import-Clixml -LiteralPath $Path }
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $secret = ConvertTo-SecureString ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
    $credential = [PSCredential]::new($Name, $secret)
    $credential | Export-Clixml -LiteralPath $Path
    return $credential
}

$jwt = New-ProtectedCredential 'jwt' (Join-Path $root 'jwt.credential.xml')
$admin = New-ProtectedCredential 'admin' (Join-Path $root 'admin.credential.xml')
$newDatabase = -not (Test-Path -LiteralPath (Join-Path $apiDir 'data/rustdeskapi.db'))
$config = Join-Path $apiDir 'conf/crhrustdesk.yaml'
$template = Get-Content -LiteralPath (Join-Path $apiDir 'conf/config.yaml') -Raw -Encoding UTF8
$template = $template -replace 'lang: "zh-CN"', 'lang: "en"'
$template = $template -replace 'web-client: 1', 'web-client: 0'
$template = $template -replace 'title: "RustDesk API Admin"', 'title: "CrhRustDesk Admin"'
$template = $template -replace 'api-addr: "0.0.0.0:21114"', 'api-addr: "127.0.0.1:21114"'
$template = $template -replace '192.168.1.66', $publicHost
if (-not [Net.IPAddress]::IsLoopback($ServerAddress)) {
    $template = $template.Replace('api-server: "http://127.0.0.1:21114"', "api-server: `"https://${publicHost}:8443`"")
}
$template = $template -replace 'key-file: "/data/id_ed25519.pub"', ('key-file: "' + (Join-Path $transportDir 'id_ed25519.pub').Replace('\', '/') + '"')
$template = $template -replace '168h', '1h'
[IO.File]::WriteAllText($config, $template, [Text.UTF8Encoding]::new($false))
$previousJwt = $env:RUSTDESK_API_JWT_KEY
$previousRustLog = $env:RUST_LOG
$previousDatabase = $env:DB_URL
$launched = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
try {
    $env:RUSTDESK_API_JWT_KEY = $jwt.GetNetworkCredential().Password
    $env:RUST_LOG = 'info'
    $env:DB_URL = Join-Path $transportDir 'db_v2.sqlite3'
    $hbbs = Start-Process -FilePath $executables[1] -ArgumentList "-r ${publicHost}:21117 --must-login Y -k _" -WorkingDirectory $transportDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'hbbs.stdout.log') -RedirectStandardError (Join-Path $root 'hbbs.stderr.log') -PassThru
    $launched.Add($hbbs)
    $deadline = (Get-Date).AddSeconds(20)
    while (-not (Test-Path -LiteralPath (Join-Path $transportDir 'id_ed25519.pub'))) {
        if ($hbbs.HasExited -or (Get-Date) -gt $deadline) { throw 'hbbs did not generate its key. Inspect the server logs.' }
        Start-Sleep -Milliseconds 250
    }
    $hbbr = Start-Process -FilePath $executables[2] -ArgumentList '-k _' -WorkingDirectory $transportDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'hbbr.stdout.log') -RedirectStandardError (Join-Path $root 'hbbr.stderr.log') -PassThru
    $launched.Add($hbbr)
    if ($newDatabase) {
        Push-Location -LiteralPath $apiDir
        try {
            & $executables[0] --config $config reset-admin-pwd $admin.GetNetworkCredential().Password *> (Join-Path $root 'bootstrap.log')
            if ($LASTEXITCODE -ne 0) { throw 'API account bootstrap failed. Inspect bootstrap.log.' }
        } finally { Pop-Location }
    }
    $api = Start-Process -FilePath $executables[0] -ArgumentList "--config `"$config`"" -WorkingDirectory $apiDir -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'api.stdout.log') -RedirectStandardError (Join-Path $root 'api.stderr.log') -PassThru
    $launched.Add($api)
    $deadline = (Get-Date).AddSeconds(20)
    do {
        if ($api.HasExited -or (Get-Date) -gt $deadline) { throw 'The API did not become ready. Inspect the API logs.' }
        Start-Sleep -Milliseconds 250
        $ready = $false
        try {
            $response = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/' -TimeoutSec 2
            $ready = $response.code -eq 0
        } catch [System.Net.WebException] { $ready = $false }
    } until ($ready)
    if ($newDatabase) {
        $body = @{username = 'admin'; password = $admin.GetNetworkCredential().Password; type = 'account'} | ConvertTo-Json
        $login = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/login' -Method Post -ContentType 'application/json' -Body $body
        if (-not $login.access_token) { throw 'The configured admin account could not log in' }
    }
    foreach ($process in $launched) {
        $process.Refresh()
        if ($process.HasExited) { throw 'A server process exited during startup. Inspect its logs.' }
    }
    Write-Host 'CrhRustDesk dev API is ready at http://127.0.0.1:21114/_admin/'
    Write-Host "Admin credential is protected with Windows DPAPI at: $(Join-Path $root 'admin.credential.xml')"
    Write-Host 'Transport uses --must-login Y and the same non-empty JWT signing secret as the API.'
    Write-Host 'No firewall rules or client configurations were changed. LAN TLS and remote sessions remain unverified.'
} catch {
    foreach ($process in $launched) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -ErrorAction Continue }
    }
    throw
} finally {
    $env:RUSTDESK_API_JWT_KEY = $previousJwt
    $env:RUST_LOG = $previousRustLog
    $env:DB_URL = $previousDatabase
}
