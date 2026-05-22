Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$server = Join-Path $root "scripts\mcp-server.ps1"

$messages = @(
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}',
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}',
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"safety_check","arguments":{"text":"rm -rf /"}}}',
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"safety_check","arguments":{"text":"echo hello"}}}',
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"type_text","arguments":{"text":"rm -rf /"}}}'
)

$output = ($messages -join "`n") | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $server
$lines = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($lines.Count -ne 5) {
    throw "expected 5 JSON-RPC responses, got $($lines.Count): $output"
}

$responses = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
if ($responses[0].result.serverInfo.name -ne "open-computer-use-windows") {
    throw "initialize response did not identify the Windows server"
}
if ($responses[1].result.tools.name -notcontains "safety_check") {
    throw "tools/list did not include safety_check"
}
$unsafe = $responses[2].result.content[0].text | ConvertFrom-Json
if ($unsafe.allowed -ne $false -or $unsafe.rule -ne "unix-rm-recursive") {
    throw "unsafe rm command was not detected"
}
$safe = $responses[3].result.content[0].text | ConvertFrom-Json
if ($safe.allowed -ne $true) {
    throw "safe text was blocked unexpectedly"
}
if ($responses[4].result.isError -ne $true) {
    throw "type_text did not block unsafe text"
}

Write-Output "windows smoke test passed"
