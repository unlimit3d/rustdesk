[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ToolsRoot)

$ErrorActionPreference = 'Stop'
$root = Join-Path $ToolsRoot 'dev-server'
$python = Join-Path $ToolsRoot 'permit-python/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw 'Create permit-python venv and install account-server/requirements.txt first' }
if (Get-NetTCPConnection -LocalPort 21120 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Permit port 21120 is already listening. Existing services were left unchanged.'
}
$source = Join-Path $PSScriptRoot 'account-server/server.py'
& $python $source --root $root --initialize
if ($LASTEXITCODE -ne 0) { throw 'Permit key initialization failed' }
$process = Start-Process -FilePath $python -ArgumentList @('-u', "`"$source`"", '--root', "`"$root`"") -WindowStyle Hidden -WorkingDirectory $root -RedirectStandardOutput (Join-Path $root 'permit.stdout.log') -RedirectStandardError (Join-Path $root 'permit.stderr.log') -PassThru
Write-Host "Permit server PID $($process.Id), loopback port 21120. Publish only through the dev HTTPS proxy."

