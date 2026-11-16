[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$KeyDirectory)
$ErrorActionPreference = 'Stop'
$KeyDirectory = [IO.Path]::GetFullPath($KeyDirectory)
if (Test-Path -LiteralPath $KeyDirectory) { throw 'Use a new private directory; existing signing keys must not be overwritten' }
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl.SetOwner($owner)
foreach ($sid in @($owner.Value, 'S-1-5-18', 'S-1-5-32-544') | Select-Object -Unique) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
}
[IO.Directory]::CreateDirectory($KeyDirectory, $acl) | Out-Null
if ((Get-Item -LiteralPath $KeyDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-Acl -LiteralPath $KeyDirectory).GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $owner.Value) { throw 'The signing-key directory is not a private directory owned by this user' }
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new(3072)
try {
    $rsa.PersistKeyInCsp = $false
    [IO.File]::WriteAllText((Join-Path $KeyDirectory 'update-private-key.xml'), $rsa.ToXmlString($true))
    [IO.File]::WriteAllText((Join-Path $KeyDirectory 'update-public-key.xml'), $rsa.ToXmlString($false))
} finally { $rsa.Dispose() }
Write-Output 'Update signing keys created. Keep the private key offline and outside client/server packages.'
