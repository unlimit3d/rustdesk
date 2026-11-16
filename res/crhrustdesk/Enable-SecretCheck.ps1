[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Gitleaks)
$ErrorActionPreference = 'Stop'
$Gitleaks = (Resolve-Path -LiteralPath $Gitleaks).Path
$repo = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Run from the Git working tree' }
$hook = [IO.Path]::GetFullPath((& git rev-parse --git-path hooks/pre-commit).Trim())
$source = Join-Path $PSScriptRoot 'hooks/pre-commit'
if ((Test-Path -LiteralPath $hook) -and (Get-FileHash -LiteralPath $hook).Hash -ne (Get-FileHash -LiteralPath $source).Hash) {
    throw 'An existing pre-commit hook was left unchanged. Chain the secret check into it manually.'
}
& git config --local crhrustdesk.gitleaksPath $Gitleaks
if ($LASTEXITCODE -ne 0) { throw 'Could not configure Gitleaks' }
[IO.File]::WriteAllBytes($hook, [IO.File]::ReadAllBytes($source))
Write-Output 'Local pre-commit secret check enabled. No files were staged or committed.'
