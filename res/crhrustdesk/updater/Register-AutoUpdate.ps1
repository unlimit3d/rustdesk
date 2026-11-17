[CmdletBinding()]
param([switch]$ScheduleOnly)
$ErrorActionPreference = 'Stop'
$installRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$release = Join-Path $installRoot 'client-release.json'
foreach ($name in @('connection-profile.json', 'update-public-key.xml', 'client-release.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $installRoot $name))) { throw "Missing updater prerequisite: $name" }
}
$connectionProfile = Get-Content -LiteralPath (Join-Path $installRoot 'connection-profile.json') -Raw | ConvertFrom-Json
if ($connectionProfile.role -eq 'outgoing') {
    if (Test-Path -LiteralPath (Join-Path $installRoot 'CrhRustDeskIT.exe')) { return }
    if (Get-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate' -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate' -Confirm:$false
    }
    return
}
if ($connectionProfile.role -ne 'incoming') { throw 'Unknown installation role' }
$triggers = @((New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)))
if ($ScheduleOnly) {
    Set-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate' -Trigger $triggers | Out-Null
    return
}
$stateRoot = Join-Path $env:ProgramData 'CrhRustDesk-Updater'
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
$acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
if (-not (Test-Path -LiteralPath $stateRoot)) { [IO.Directory]::CreateDirectory($stateRoot, $acl) | Out-Null }
foreach ($entry in @((Get-Item -LiteralPath $stateRoot)) + @(Get-ChildItem -LiteralPath $stateRoot -Force)) {
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Updater state must not contain reparse points' }
    $existingAcl = Get-Acl -LiteralPath $entry.FullName
    if ($existingAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'Existing updater state is not administrator-owned' }
    foreach ($rule in $existingAcl.Access) {
        $writer = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        $writeRights = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
        if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writeRights) -and $writer -notin @('S-1-5-18', 'S-1-5-32-544')) { throw 'Existing updater state permits untrusted writes' }
    }
}
Set-Acl -LiteralPath $stateRoot -AclObject $acl
$registrationLock = [IO.File]::Open((Join-Path $stateRoot 'update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
try {
    Copy-Item -LiteralPath $release -Destination (Join-Path $stateRoot 'applied.json') -Force
    $stateAcl = Get-Acl -LiteralPath (Join-Path $stateRoot 'applied.json')
    $stateAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath (Join-Path $stateRoot 'applied.json') -AclObject $stateAcl
    $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $script = Join-Path $PSScriptRoot 'Invoke-ClientUpdate.ps1'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script + '"')
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
    Register-ScheduledTask -TaskName 'CrhRustDesk AutoUpdate' -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Force | Out-Null
} finally {
    $registrationLock.Dispose()
    $lockAcl = Get-Acl -LiteralPath (Join-Path $stateRoot 'update.lock')
    $lockAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath (Join-Path $stateRoot 'update.lock') -AclObject $lockAcl
}
