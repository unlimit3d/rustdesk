[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ToolsRoot,
    [Parameter(Mandatory = $true)][System.Net.IPAddress]$ServerAddress
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ($ServerAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'This dev TLS launcher requires an IPv4 address'
}
$root = [IO.Path]::GetFullPath((Join-Path $ToolsRoot 'dev-server'))
if (-not (Test-Path -LiteralPath (Join-Path $root 'api/release/apimain.exe'))) {
    throw 'Start the dev server before configuring TLS'
}
$probe = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/' -TimeoutSec 3
if ($probe.code -ne 0) { throw 'The dev API is not ready' }
if (Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Port 8443 is already listening. Existing services were left unchanged.'
}
$archive = Join-Path $ToolsRoot 'downloads/caddy_2.11.9_windows_amd64.zip'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -Uri 'https://github.com/caddyserver/caddy/releases/download/v2.11.9/caddy_2.11.9_windows_amd64.zip' -OutFile $archive -UseBasicParsing
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne 'ad93112d335ee687100c4c9f11bced16ca590377976b7fe7883882b9e797e472') {
    throw 'Caddy archive SHA256 mismatch'
}
$proxy = Join-Path $root 'proxy'
if (-not (Test-Path -LiteralPath $proxy)) {
    Expand-Archive -LiteralPath $archive -DestinationPath $proxy
}
$storage = (Join-Path $root 'tls-data').Replace('\', '/')
$config = Join-Path $proxy 'Caddyfile'
$contents = @"
{
    admin off
    persist_config off
    auto_https disable_redirects
    skip_install_trust
    storage file_system {
        root "$storage"
    }
}
https://${ServerAddress}:8443 {
    bind $ServerAddress
    tls internal
    @admin path /_admin* /api/admin/* /crhrustdesk/admin/*
    handle @admin {
        respond "Use the loopback admin console" 403
    }
    handle /crhrustdesk/* {
        reverse_proxy 127.0.0.1:21120
    }
    handle {
        reverse_proxy 127.0.0.1:21114
    }
}
"@
[IO.File]::WriteAllText($config, $contents, [Text.UTF8Encoding]::new($false))
$executable = Join-Path $proxy 'caddy.exe'
& $executable adapt --config $config --adapter caddyfile > (Join-Path $proxy 'adapted.json')
if ($LASTEXITCODE -ne 0) { throw 'Caddy configuration is invalid' }
$process = Start-Process -FilePath $executable -ArgumentList "run --config `"$config`" --adapter caddyfile" -WorkingDirectory $proxy -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'tls.stdout.log') -RedirectStandardError (Join-Path $root 'tls.stderr.log') -PassThru
$certificate = Join-Path $root 'tls-data/pki/authorities/local/root.crt'
$deadline = (Get-Date).AddSeconds(15)
while (-not (Test-Path -LiteralPath $certificate)) {
    if ($process.HasExited -or (Get-Date) -gt $deadline) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
        throw 'The dev TLS certificate was not created. Inspect tls.stderr.log.'
    }
    Start-Sleep -Milliseconds 250
}
Write-Host "Dev HTTPS endpoint: https://${ServerAddress}:8443"
Write-Host "Public development CA certificate: $certificate"
Write-Host 'No Windows trust-store or firewall changes were made. Keep the CA private key on this dev machine.'
