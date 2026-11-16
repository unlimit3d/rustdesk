[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$ToolsRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Initialize-BuildEnvironment.ps1') -ToolsRoot $ToolsRoot
if ((& flutter_rust_bridge_codegen --version) -ne 'flutter_rust_bridge_codegen 1.80.1') {
    throw 'This source requires flutter_rust_bridge_codegen 1.80.1'
}
if ((& cargo expand --version) -ne 'cargo-expand 1.0.95') {
    throw 'This source requires cargo-expand 1.0.95'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$previousRustLog = $env:RUST_LOG
Push-Location -LiteralPath $repo
try {
    $env:RUST_LOG = 'info'
    & flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output (Join-Path $ToolsRoot 'bridge_generated.h') --skip-add-mod-to-lib --llvm-path $env:LLVM_PATH
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Rust Bridge generation failed' }
} finally {
    $env:RUST_LOG = $previousRustLog
    Pop-Location
}
