$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('CrhRustDesk-update-roles-' + [Guid]::NewGuid().ToString('N'))
$testUpdater = Join-Path $testRoot 'updater'
$taskCalls = @{removed = 0; triggers = @()}

# Exercise role decisions without registering or deleting a real Windows task.
function Get-ScheduledTask {
    [CmdletBinding()]
    param([string]$TaskName)
    return @{TaskName = $TaskName}
}
function Unregister-ScheduledTask {
    param([string]$TaskName, [switch]$Confirm)
    $taskCalls.removed += 1
}
function Set-ScheduledTask {
    param([string]$TaskName, [object[]]$Trigger)
    $taskCalls.triggers = $Trigger
}

try {
    New-Item -ItemType Directory -Path $testUpdater -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../updater/Register-AutoUpdate.ps1') -Destination $testUpdater
    foreach ($file in @('update-public-key.xml', 'client-release.json')) {
        '{}' | Set-Content -LiteralPath (Join-Path $testRoot $file)
    }
    '{"role":"outgoing"}' | Set-Content -LiteralPath (Join-Path $testRoot 'connection-profile.json')
    & (Join-Path $testUpdater 'Register-AutoUpdate.ps1') -ScheduleOnly
    if ($taskCalls.removed -ne 1 -or $taskCalls.triggers.Count -ne 0) {
        throw 'IT role must remove its legacy automatic update task'
    }
    Write-Output 'PASS: IT role does not register an automatic installer task'

    '{"role":"incoming"}' | Set-Content -LiteralPath (Join-Path $testRoot 'connection-profile.json')
    & (Join-Path $testUpdater 'Register-AutoUpdate.ps1') -ScheduleOnly
    $periodic = @($taskCalls.triggers | Where-Object { $_.Repetition.Interval -eq 'PT5M' })
    $startup = @($taskCalls.triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' })
    if ($periodic.Count -ne 1 -or $startup.Count -ne 1 -or $taskCalls.triggers.Count -ne 2) {
        throw 'Endpoint role must check at startup and repeat every five minutes'
    }
    Write-Output 'PASS: endpoint schedule refresh preserves startup and adds five-minute checks'
} finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolved).StartsWith('CrhRustDesk-update-roles-')) {
        throw 'Refusing cleanup outside the test temporary directory'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
