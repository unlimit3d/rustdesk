[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9.:-]+$')][string]$IdServer,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9.:-]+$')][string]$RelayServer,
    [Parameter(Mandatory = $true)][uri]$ApiServer,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9+/]{43}=$')][string]$PublicKey
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this installer from an Administrator PowerShell session on the target computer'
}
if (-not $ApiServer.IsAbsoluteUri -or ($ApiServer.Scheme -ne 'https' -and -not ($ApiServer.Scheme -eq 'http' -and $ApiServer.IsLoopback))) {
    throw 'Use HTTPS for the account API. Plain HTTP is allowed only for loopback development.'
}
if ($ApiServer.Scheme -eq 'https' -and $ApiServer.Port -eq 21114) {
    throw 'Use a TLS reverse proxy on port 443 or another port; the client strips 21114 from HTTPS API URLs'
}
$bundleExecutable = Join-Path $PSScriptRoot 'CrhRustDesk.exe'
if (-not (Test-Path -LiteralPath $bundleExecutable)) {
    throw 'Run Install.ps1 from the complete CrhRustDesk release bundle'
}
$installedExecutable = Join-Path $env:ProgramFiles 'CrhRustDesk/CrhRustDesk.exe'
if (Test-Path -LiteralPath $installedExecutable) {
    throw 'CrhRustDesk is already installed. Existing settings were left unchanged.'
}
$install = Start-Process -FilePath $bundleExecutable -ArgumentList '--silent-install' -Wait -PassThru
if ($install.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $installedExecutable)) {
    throw 'CrhRustDesk installation did not complete'
}
$options = [ordered]@{
    'custom-rendezvous-server' = $IdServer
    'relay-server' = $RelayServer
    'api-server' = $ApiServer.AbsoluteUri.TrimEnd('/')
    'key' = $PublicKey
    'direct-server' = 'N'
    'approve-mode' = 'click'
}
foreach ($option in $options.GetEnumerator()) {
    $command = Start-Process -FilePath $installedExecutable -ArgumentList @('--option', $option.Key, $option.Value) -Wait -PassThru
    if ($command.ExitCode -ne 0) { throw "Could not apply option: $($option.Key)" }
}
Write-Host 'CrhRustDesk is installed and configured to use the supplied servers.'
Write-Host 'Sign in to the central account in the app. Incoming sessions require local approval.'
Write-Host 'A real connection must still verify the server key, encryption, and target approval.'
