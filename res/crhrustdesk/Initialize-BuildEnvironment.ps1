[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ToolsRoot)

$ErrorActionPreference = 'Stop'
$ToolsRoot = (Resolve-Path -LiteralPath $ToolsRoot).Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $visualStudio) { throw 'Visual Studio C++ build tools are missing' }
Import-Module (Join-Path $visualStudio 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $visualStudio -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64'
$env:CARGO_HOME = Join-Path $ToolsRoot 'cargo'
$env:RUSTUP_HOME = Join-Path $ToolsRoot 'rustup'
$env:VCPKG_ROOT = Join-Path $ToolsRoot 'vcpkg'
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
$env:PUB_CACHE = Join-Path $ToolsRoot 'pub-cache'
$env:LLVM_PATH = Join-Path $ToolsRoot 'LLVM'
if (-not (Test-Path -LiteralPath $env:LLVM_PATH)) {
    $env:LLVM_PATH = Join-Path $env:ProgramFiles 'LLVM'
}
$env:LIBCLANG_PATH = Join-Path $env:LLVM_PATH 'bin'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$paths = @(
    (Join-Path $ToolsRoot 'cargo/bin'),
    (Join-Path $ToolsRoot 'flutter-3.24.5/bin'),
    (Join-Path $ToolsRoot 'frb-codegen-1.80.1'),
    $env:LIBCLANG_PATH,
    (Join-Path $ToolsRoot 'nasm/nasm-2.16.03'),
    (Join-Path $ToolsRoot 'cmake/cmake-4.3.0-windows-x86_64/bin')
)
$env:PATH = ($paths -join ';') + ';' + $env:PATH
