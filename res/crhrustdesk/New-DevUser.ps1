[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ToolsRoot,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_-]{2,32}$')][string]$Username
)

$ErrorActionPreference = 'Stop'
if ($Username -eq 'admin') { throw 'Use a separate non-admin username' }
$root = [IO.Path]::GetFullPath((Join-Path $ToolsRoot 'dev-server'))
$admin = Import-Clixml -LiteralPath (Join-Path $root 'admin.credential.xml')
$body = @{username = $admin.UserName; password = $admin.GetNetworkCredential().Password; type = 'account'} | ConvertTo-Json
$login = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/login' -Method Post -ContentType 'application/json' -Body $body
if (-not $login.access_token) { throw 'Admin login failed' }
$headers = @{'api-token' = $login.access_token}
$list = Invoke-RestMethod -Uri "http://127.0.0.1:21114/api/admin/user/list?page=1&page_size=100&username=$Username" -Headers $headers
if ($list.code -ne 0) { throw 'Could not list users' }
$user = @($list.data.list | Where-Object { $_.username -eq $Username })
$credentialPath = Join-Path $root "$Username.credential.xml"
if ($user.Count -and -not (Test-Path -LiteralPath $credentialPath)) {
    throw 'This username already exists without a local credential. Its password was left unchanged.'
}
if (Test-Path -LiteralPath $credentialPath) {
    $credential = Import-Clixml -LiteralPath $credentialPath
} else {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $secret = ConvertTo-SecureString ([Convert]::ToBase64String($bytes)) -AsPlainText -Force
    $credential = [PSCredential]::new($Username, $secret)
    $credential | Export-Clixml -LiteralPath $credentialPath
}
if (-not $user.Count) {
    $body = @{username = $Username; nickname = $Username; group_id = 1; is_admin = $false; status = 1} | ConvertTo-Json
    $created = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/admin/user/create' -Method Post -Headers $headers -ContentType 'application/json' -Body $body
    if ($created.code -ne 0) { throw 'Could not create the dev user' }
    $list = Invoke-RestMethod -Uri "http://127.0.0.1:21114/api/admin/user/list?page=1&page_size=100&username=$Username" -Headers $headers
    if ($list.code -ne 0) { throw 'Could not read the created user' }
    $user = @($list.data.list | Where-Object { $_.username -eq $Username })
    if ($user.Count -ne 1 -or $user[0].is_admin) { throw 'Expected one non-admin user' }
    $body = @{id = $user[0].id; password = $credential.GetNetworkCredential().Password} | ConvertTo-Json
    $updated = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/admin/user/changePwd' -Method Post -Headers $headers -ContentType 'application/json' -Body $body
    if ($updated.code -ne 0) { throw 'Could not set the user password' }
}
if ($user.Count -ne 1 -or $user[0].is_admin) { throw 'Expected one non-admin user' }
$body = @{username = $Username; password = $credential.GetNetworkCredential().Password; type = 'account'} | ConvertTo-Json
$verified = Invoke-RestMethod -Uri 'http://127.0.0.1:21114/api/login' -Method Post -ContentType 'application/json' -Body $body
if (-not $verified.access_token -or $verified.user.name -ne $Username -or $verified.user.is_admin) {
    throw 'The non-admin account did not pass login verification'
}
Write-Host "Verified non-admin dev user: $Username"
Write-Host "Windows DPAPI credential: $credentialPath"
