[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ToolsRoot,
    [string]$IdServer = '127.0.0.1',
    [string]$RelayServer = '127.0.0.1:21117',
    [string]$ApiServer = 'http://127.0.0.1:21114',
    [string]$PublicKey,
    [string]$PermitPublicKey,
    [string]$RootCertificate,
    [string]$UpdatePublicKey,
    [switch]$CheckOnly,
    [switch]$SkipCargo
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($ToolsRoot) {
    . (Join-Path $PSScriptRoot 'Initialize-BuildEnvironment.ps1') -ToolsRoot $ToolsRoot
}

$missing = [System.Collections.Generic.List[string]]::new()
$windowInjection = Join-Path $ToolsRoot 'sources/RustDeskTempTopMostWindow/WindowInjection/x64/Release/WindowInjection.dll'
if (-not (Test-Path -LiteralPath $windowInjection)) {
    $missing.Add('Build WindowInjection.dll from the source commit pinned in third-party-RustDeskTempTopMostWindow.yml')
}
foreach ($command in @('cargo', 'rustc', 'flutter', 'python', 'cmake', 'clang', 'nasm')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        $missing.Add("Tool not on PATH: $command")
    }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    $missing.Add('Visual Studio Installer/vswhere.exe is missing')
} elseif (-not (& $vswhere -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)) {
    $missing.Add('Visual Studio C++ x64 build tools are missing')
}
foreach ($file in @(
    'libs/hbb_common/Cargo.toml',
    'src/bridge_generated.rs',
    'src/bridge_generated.io.rs',
    'flutter/lib/generated_bridge.dart',
    'flutter/lib/generated_bridge.freezed.dart'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $file))) {
        $missing.Add("Required source or matching CI bridge artifact is missing: $file")
    }
}
if (-not $env:VCPKG_ROOT -or -not (Test-Path -LiteralPath (Join-Path $env:VCPKG_ROOT 'installed/x64-windows-static/lib'))) {
    $missing.Add('Set VCPKG_ROOT to the pinned vcpkg installation with x64-windows-static dependencies')
} else {
    foreach ($header in @('aom/aom.h', 'libavcodec/avcodec.h', 'vpx/vpx_decoder.h', 'libyuv.h', 'opus/opus.h')) {
        if (-not (Test-Path -LiteralPath (Join-Path $env:VCPKG_ROOT "installed/x64-windows-static/include/$header"))) {
            $missing.Add("vcpkg dependency is not installed yet: $header")
        }
    }
}
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterVersion = & flutter --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $flutterVersion.frameworkVersion -ne '3.24.5') {
        $missing.Add("Windows x64 requires the CI Flutter SDK 3.24.5; found $($flutterVersion.frameworkVersion)")
    }
}
if ($missing.Count) {
    foreach ($item in $missing) { Write-Host "MISSING: $item" }
    throw 'CrhRustDesk prerequisites are incomplete. No package was produced.'
}
if ($CheckOnly) {
    Write-Host 'CrhRustDesk build prerequisites are present. This does not verify compilation.'
    return
}

if (-not $PublicKey -and $ToolsRoot) {
    $PublicKey = (Get-Content -LiteralPath (Join-Path $ToolsRoot 'dev-server/transport/x86_64/id_ed25519.pub') -Raw).Trim()
}
if ($PublicKey -notmatch '^[A-Za-z0-9+/]{43}=$') { throw 'A valid Ed25519 server public key is required' }
$apiUri = [uri]$ApiServer
if (-not $apiUri.IsAbsoluteUri -or ($apiUri.Scheme -ne 'https' -and -not ($apiUri.Scheme -eq 'http' -and $apiUri.IsLoopback))) {
    throw 'The account API must use HTTPS, except for loopback development'
}
$env:CRHRUSTDESK_ID_SERVER = $IdServer
$env:CRHRUSTDESK_RELAY_SERVER = $RelayServer
$env:CRHRUSTDESK_API_SERVER = $ApiServer
$env:CRHRUSTDESK_SERVER_KEY = $PublicKey
if (-not $PermitPublicKey) {
    $permitKeyFile = Join-Path $ToolsRoot 'dev-server/permit-public-key.txt'
    if (-not (Test-Path -LiteralPath $permitKeyFile)) { throw 'A permit signing public key is required' }
    $PermitPublicKey = (Get-Content -LiteralPath $permitKeyFile -Raw).Trim()
}
$env:CRHRUSTDESK_PERMIT_PUBLIC_KEY = $PermitPublicKey
if ($env:CRHRUSTDESK_PERMIT_PUBLIC_KEY -notmatch '^[A-Za-z0-9+/]{43}=$') { throw 'Invalid permit signing public key' }
if (-not $UpdatePublicKey) { $UpdatePublicKey = Join-Path $ToolsRoot 'update-signing/update-public-key.xml' }
if (-not (Test-Path -LiteralPath $UpdatePublicKey)) { throw 'Create the offline update-signing key before building; pass only its public key here' }
$updateKeyXml = Get-Content -LiteralPath $UpdatePublicKey -Raw
if ($updateKeyXml -match '<(?:D|P|Q|DP|DQ|InverseQ)>') { throw 'The update public key file contains private parameters' }
$updateRsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
try {
    $updateRsa.PersistKeyInCsp = $false
    $updateRsa.FromXmlString($updateKeyXml)
    if ($updateRsa.KeySize -lt 3072) { throw 'The update signing key must be at least RSA 3072' }
} finally { $updateRsa.Dispose() }

$previousBrand = $env:CRHRUSTDESK_BUILD
Push-Location -LiteralPath $repo
try {
    $env:CRHRUSTDESK_BUILD = '1'
    $buildArguments = @('--portable', '--flutter', '--skip-portable-pack', '--hwcodec')
    if ($SkipCargo) { $buildArguments += '--skip-cargo' }
    $nativeErrorPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & python ./build.py @buildArguments
        $buildExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $nativeErrorPreference
    }
    if ($buildExitCode -ne 0) { throw 'CrhRustDesk build failed' }
    $bundle = Join-Path $repo 'flutter/build/windows/x64/runner/Release'
    if (-not (Test-Path -LiteralPath (Join-Path $bundle 'rustdesk.exe'))) {
        throw 'The Windows release bundle is missing rustdesk.exe'
    }
    $package = Join-Path $repo ('target/CrhRustDesk-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (Test-Path -LiteralPath $package) { throw "Package directory already exists: $package" }
    Copy-Item -LiteralPath $bundle -Destination $package -Recurse
    Rename-Item -LiteralPath (Join-Path $package 'rustdesk.exe') -NewName 'CrhRustDesk.exe'
    Copy-Item -LiteralPath (Join-Path $repo 'LICENCE') -Destination $package
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Install.ps1') -Destination $package
    Copy-Item -LiteralPath $windowInjection -Destination $package
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'icon.ico') -Destination (Join-Path $package 'CrhRustDesk.ico')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'updater') -Destination (Join-Path $package 'updater') -Recurse
    Copy-Item -LiteralPath $UpdatePublicKey -Destination (Join-Path $package 'update-public-key.xml')
    $PublicKey | Set-Content -LiteralPath (Join-Path $package 'server-public-key.txt') -Encoding ASCII
    $env:CRHRUSTDESK_PERMIT_PUBLIC_KEY | Set-Content -LiteralPath (Join-Path $package 'permit-public-key.txt') -Encoding ASCII
    $devCA = if ($RootCertificate) { (Resolve-Path -LiteralPath $RootCertificate).Path } else { Join-Path $ToolsRoot 'dev-server/tls-data/pki/authorities/local/root.crt' }
    if (Test-Path -LiteralPath $devCA) {
        Copy-Item -LiteralPath $devCA -Destination (Join-Path $package 'CrhRustDesk-dev-root.crt')
    }
    & git rev-parse HEAD | Set-Content -LiteralPath (Join-Path $package 'SOURCE-COMMIT.txt') -Encoding ASCII
    if ($LASTEXITCODE -ne 0) { throw 'Could not record the source commit' }
    $patch = & git diff HEAD --binary
    if ($LASTEXITCODE -ne 0) { throw 'Could not record the source changes' }
    [IO.File]::WriteAllText((Join-Path $package 'SOURCE-CHANGES.patch'), ($patch -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
    $scriptFiles = & git ls-files --cached --others --exclude-standard -- res/crhrustdesk
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate public build scripts' }
    foreach ($scriptFile in $scriptFiles) {
        $relativeScript = $scriptFile.Substring('res/crhrustdesk/'.Length)
        $scriptDestination = Join-Path $package ('build-scripts/' + $relativeScript)
        New-Item -ItemType Directory -Path (Split-Path -Parent $scriptDestination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $scriptFile) -Destination $scriptDestination
    }
    Copy-Item -LiteralPath (Join-Path $repo 'src/crhrustdesk.rs') -Destination (Join-Path $package 'build-scripts/crhrustdesk.rs')
    Copy-Item -LiteralPath (Join-Path $repo 'src/server/connection/crhrustdesk.rs') -Destination (Join-Path $package 'build-scripts/connection-crhrustdesk.rs')
    Copy-Item -LiteralPath (Join-Path $repo 'src/crhrustdesk/role.rs') -Destination (Join-Path $package 'build-scripts/role.rs')
    Copy-Item -LiteralPath (Join-Path $repo 'src/crhrustdesk/update.rs') -Destination (Join-Path $package 'build-scripts/update.rs')
    Write-Host "Built bundle: $package"
    Write-Host 'Keep the complete bundle together. Use CrhRustDesk.exe --install on the target.'
} finally {
    $env:CRHRUSTDESK_BUILD = $previousBrand
    Pop-Location
}
