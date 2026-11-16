[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ToolsRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_-]{2,32}$')][string]$Username,
    [ValidatePattern('^(\*|[0-9]{6,20})$')][string[]]$DeviceIds = @('*'),
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
if (Get-NetTCPConnection -LocalPort 21120 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Use CrhRustDesk Management while the permit server is running. This offline command must not write policy concurrently with Management.'
}
$path = Join-Path $ToolsRoot 'dev-server/unattended-users.json'
$policy = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Remove) {
    $policy.users.PSObject.Properties.Remove($Username)
} else {
    $policy.users | Add-Member -NotePropertyName $Username -NotePropertyValue @($DeviceIds) -Force
}
$temporary = "$path.new"
[IO.File]::WriteAllText($temporary, ($policy | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $path -Force
Write-Host "Updated central unattended policy for $Username. New permits use this policy immediately; existing permits expire within 60 seconds."
