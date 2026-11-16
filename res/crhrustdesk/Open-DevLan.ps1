[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ToolsRoot,
    [Parameter(Mandatory = $true)][System.Net.IPAddress]$ClientAddress
)

$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an Administrator PowerShell session on the dev server'
}
if (-not (Get-NetFirewallProfile -Name Private).Enabled) {
    throw 'The Private firewall profile is disabled. Have the administrator restore the host firewall policy before adding these rules.'
}
$root = [IO.Path]::GetFullPath((Join-Path $ToolsRoot 'dev-server'))
$rules = @(
    @{Name = 'CrhRustDesk-Dev-ID-TCP'; Program = 'transport/x86_64/hbbs.exe'; Protocol = 'TCP'; Ports = @(21115, 21116)},
    @{Name = 'CrhRustDesk-Dev-ID-UDP'; Program = 'transport/x86_64/hbbs.exe'; Protocol = 'UDP'; Ports = @(21116)},
    @{Name = 'CrhRustDesk-Dev-Relay'; Program = 'transport/x86_64/hbbr.exe'; Protocol = 'TCP'; Ports = @(21117)},
    @{Name = 'CrhRustDesk-Dev-HTTPS'; Program = 'proxy/caddy.exe'; Protocol = 'TCP'; Ports = @(8443)}
)
foreach ($rule in $rules) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $rule.Program))) { throw "Missing executable for $($rule.Name)" }
    if (Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue) { throw "Firewall rule already exists; review it before changing it: $($rule.Name)" }
}
foreach ($rule in $rules) {
    New-NetFirewallRule -Name $rule.Name -DisplayName $rule.Name -Direction Inbound -Action Allow -Program (Join-Path $root $rule.Program) -Protocol $rule.Protocol -LocalPort $rule.Ports -RemoteAddress $ClientAddress.IPAddressToString -Profile Private | Out-Null
}
Write-Host "Added Private-profile rules for the specified server programs from $ClientAddress only."
Write-Host 'Other existing firewall rules and all profile enablement settings were left unchanged.'
