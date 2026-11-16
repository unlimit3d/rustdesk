[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ToolsRoot)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $ToolsRoot 'dev-server'))
$executables = @(
    (Join-Path $root 'proxy/caddy.exe'),
    (Join-Path $root 'api/release/apimain.exe'),
    (Join-Path $root 'transport/x86_64/hbbs.exe'),
    (Join-Path $root 'transport/x86_64/hbbr.exe')
    (Join-Path $ToolsRoot 'permit-python/Scripts/python.exe')
)
$permitScript = (Join-Path $PSScriptRoot 'account-server/server.py').Replace('\', '/')
foreach ($process in Get-CimInstance Win32_Process -Filter "Name = 'python.exe'") {
    $command = [string]$process.CommandLine
    if ($command.Replace('\', '/').Contains($permitScript) -and $command.Replace('\', '/').Contains($root.Replace('\', '/'))) {
        Stop-Process -Id $process.ProcessId -ErrorAction Continue
        Write-Host "Stopped CrhRustDesk permit worker PID $($process.ProcessId)"
    }
}
foreach ($process in Get-Process -ErrorAction SilentlyContinue) {
    if ($process.Path -and $process.Path -in $executables) {
        Stop-Process -Id $process.Id
        Write-Host "Stopped $($process.ProcessName) PID $($process.Id)"
    }
}
