Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$server = Join-Path $PSScriptRoot "ocu-windows.ps1"
& $server serve
if ($null -ne (Get-Variable -Name LASTEXITCODE -ErrorAction SilentlyContinue)) {
    exit $LASTEXITCODE
}
exit 0
