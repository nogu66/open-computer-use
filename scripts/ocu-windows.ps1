Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$rawScriptArgs = @($args)
$Serve = $false
$CliArgs = @()
if ($rawScriptArgs.Count -gt 0 -and $rawScriptArgs[0] -in @("-Serve", "--serve", "serve")) {
    $Serve = $true
    if ($rawScriptArgs.Count -gt 1) {
        $CliArgs = @($rawScriptArgs | Select-Object -Skip 1)
    }
} else {
    $CliArgs = $rawScriptArgs
}

function Write-OcuLog {
    param([string]$Message)
    [Console]::Error.WriteLine("[ocu-windows] $Message")
}

function Initialize-WindowsAutomation {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if (-not ("OCU.NativeMethods" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

namespace OCU {
    public static class NativeMethods {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

        [DllImport("user32.dll")]
        public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);
    }
}
'@
    }
}

Initialize-WindowsAutomation

$script:RefMap = @{}
$script:TreeNodeCount = 0
$script:FindVisited = 0
$script:KeyBuffer = ""

$script:BundleAliases = @{
    "com.google.chrome" = "chrome"
    "com.microsoft.edge" = "msedge"
    "com.microsoft.vscode" = "Code"
    "com.todesktop.230313mzl4w4u92" = "Cursor"
}

$script:TextSafetyRules = @(
    @{
        Rule = "unix-rm-recursive"
        Category = "delete"
        Pattern = '(?im)(^|[;&|\r\n])\s*(sudo\s+)?rm\s+-[A-Za-z]*[rf][A-Za-z]*\b'
        Reason = "recursive or forced rm command"
    },
    @{
        Rule = "unix-disk-format-or-raw-write"
        Category = "delete"
        Pattern = '(?im)(^|[;&|\r\n])\s*(sudo\s+)?(dd|mkfs|fdisk|parted)\b'
        Reason = "disk or partition modification command"
    },
    @{
        Rule = "unix-wide-permission-change"
        Category = "tamper"
        Pattern = '(?im)(^|[;&|\r\n])\s*(sudo\s+)?(chmod\s+-R\s+777|chown\s+-R)\b'
        Reason = "recursive ownership or permission modification"
    },
    @{
        Rule = "pipe-remote-script-to-shell"
        Category = "execution"
        Pattern = '(?im)\b(curl|wget)\b[^\r\n|]*\|\s*(sudo\s+)?(sh|bash|zsh|powershell|pwsh)\b'
        Reason = "remote script piped directly to a shell"
    },
    @{
        Rule = "git-destructive-cleanup"
        Category = "tamper"
        Pattern = '(?im)(^|[;&|\r\n])\s*git\s+(reset\s+--hard|clean\s+-[^\r\n]*[fd])\b'
        Reason = "destructive git cleanup command"
    },
    @{
        Rule = "windows-recursive-delete"
        Category = "delete"
        Pattern = '(?im)(^|[;&|\r\n])\s*(Remove-Item|del|erase|rd|rmdir)\b[^\r\n]*(\-Recurse|/s|/q)\b'
        Reason = "recursive or quiet Windows deletion command"
    },
    @{
        Rule = "windows-format-or-registry-delete"
        Category = "tamper"
        Pattern = '(?im)(^|[;&|\r\n])\s*(format\s+[A-Z]:|reg\s+delete|takeown\b|icacls\b[^\r\n]*\s/grant\b)'
        Reason = "format, registry deletion, ownership, or ACL modification"
    },
    @{
        Rule = "powershell-file-write"
        Category = "tamper"
        Pattern = '(?im)(^|[;&|\r\n])\s*(Set-Content|Add-Content|Out-File|New-Item|Move-Item|Copy-Item|Rename-Item)\b'
        Reason = "PowerShell file creation or modification command"
    },
    @{
        Rule = "unix-inplace-file-edit"
        Category = "tamper"
        Pattern = '(?im)(^|[;&|\r\n])\s*(sed\s+-i|perl\s+-pi)\b'
        Reason = "in-place file edit command"
    },
    @{
        Rule = "encoded-shell"
        Category = "execution"
        Pattern = '(?im)(powershell|pwsh)\b[^\r\n]*(\-EncodedCommand|\-enc)\b'
        Reason = "encoded shell command"
    }
)

$script:ClickSafetyRules = @(
    @{ Rule = "delete-like-ui-action"; Pattern = '(?i)\b(delete|remove|trash|uninstall|format|wipe|reset|destroy|discard)\b'; Reason = "destructive UI action label" },
    @{ Rule = "japanese-delete-like-ui-action"; Pattern = '(削除|消去|初期化|破棄|アンインストール)'; Reason = "destructive UI action label" }
)

function ConvertTo-Hashtable {
    param([object]$InputObject)
    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $table = @{}
        foreach ($key in $InputObject.Keys) {
            $table[[string]$key] = ConvertTo-Hashtable $InputObject[$key]
        }
        return $table
    }
    if ($InputObject -is [pscustomobject]) {
        $table = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-Hashtable $property.Value
        }
        return $table
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ,(ConvertTo-Hashtable $item)
        }
        return $list
    }
    return $InputObject
}

function New-ToolResult {
    param([string]$Text)
    return @{ content = @(@{ type = "text"; text = $Text }) }
}

function New-ImageResult {
    param([string]$Base64)
    return @{ content = @(@{ type = "image"; data = $Base64; mimeType = "image/png" }) }
}

function New-ToolError {
    param([string]$Message)
    return @{ content = @(@{ type = "text"; text = $Message }); isError = $true }
}

function ConvertTo-JsonLine {
    param([object]$Object)
    return ($Object | ConvertTo-Json -Depth 64 -Compress)
}

function Get-ArgValue {
    param(
        [hashtable]$Arguments,
        [string[]]$Names,
        [object]$Default = $null
    )
    foreach ($name in $Names) {
        if ($Arguments.ContainsKey($name) -and $null -ne $Arguments[$name] -and [string]$Arguments[$name] -ne "") {
            return $Arguments[$name]
        }
    }
    return $Default
}

function Test-Truthy {
    param([object]$Value)
    if ($Value -is [bool]) {
        return $Value
    }
    $s = ([string]$Value).Trim().ToLowerInvariant()
    return @("1", "true", "yes", "y") -contains $s
}

function Test-SafetyOverride {
    param([hashtable]$Arguments)
    if ($env:OCU_ALLOW_UNSAFE_INPUT -ne "1") {
        return $false
    }
    if (-not $Arguments.ContainsKey("allow_unsafe")) {
        return $false
    }
    return Test-Truthy $Arguments["allow_unsafe"]
}

function Test-UnsafeText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @{ allowed = $true }
    }
    foreach ($rule in $script:TextSafetyRules) {
        if ([regex]::IsMatch($Text, $rule.Pattern)) {
            return @{
                allowed = $false
                rule = $rule.Rule
                category = $rule.Category
                reason = $rule.Reason
            }
        }
    }
    return @{ allowed = $true }
}

function Test-UnsafeClickLabel {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @{ allowed = $true }
    }
    foreach ($rule in $script:ClickSafetyRules) {
        if ([regex]::IsMatch($Text, $rule.Pattern)) {
            return @{
                allowed = $false
                rule = $rule.Rule
                category = "destructive-ui"
                reason = $rule.Reason
            }
        }
    }
    return @{ allowed = $true }
}

function New-SafetyBlockedResult {
    param(
        [hashtable]$Safety,
        [string]$Operation
    )
    $msg = "blocked by safety policy during ${Operation}: $($Safety.rule) ($($Safety.reason)). Set OCU_ALLOW_UNSAFE_INPUT=1 and pass allow_unsafe=true only after human review."
    return New-ToolError $msg
}

function Assert-SafeTextOrReturn {
    param(
        [string]$Text,
        [hashtable]$Arguments,
        [string]$Operation
    )
    $safety = Test-UnsafeText $Text
    if (-not $safety.allowed -and -not (Test-SafetyOverride $Arguments)) {
        return New-SafetyBlockedResult $safety $Operation
    }
    return $null
}

function Assert-SafeClickOrReturn {
    param(
        [string]$Text,
        [hashtable]$Arguments,
        [string]$Operation
    )
    $safety = Test-UnsafeClickLabel $Text
    if (-not $safety.allowed -and -not (Test-SafetyOverride $Arguments)) {
        return New-SafetyBlockedResult $safety $Operation
    }
    return $null
}

function Get-WindowTitle {
    param([IntPtr]$Handle)
    $buffer = New-Object System.Text.StringBuilder 2048
    [void][OCU.NativeMethods]::GetWindowText($Handle, $buffer, $buffer.Capacity)
    return $buffer.ToString()
}

function Get-ForegroundProcessId {
    $handle = [OCU.NativeMethods]::GetForegroundWindow()
    [uint32]$pid = 0
    [void][OCU.NativeMethods]::GetWindowThreadProcessId($handle, [ref]$pid)
    return [int]$pid
}

function Get-ProcessFromArguments {
    param([hashtable]$Arguments)
    $pidArg = Get-ArgValue $Arguments @("pid")
    if ($null -ne $pidArg) {
        return Get-Process -Id ([int]$pidArg) -ErrorAction Stop
    }

    $appId = Get-ArgValue $Arguments @("app_id", "process_name", "bundle_id")
    if ($null -eq $appId) {
        return $null
    }

    $appText = ([string]$appId).Trim()
    if ($appText -match '^pid:(\d+)$') {
        return Get-Process -Id ([int]$Matches[1]) -ErrorAction Stop
    }
    if ($appText -match '^\d+$') {
        return Get-Process -Id ([int]$appText) -ErrorAction Stop
    }

    $lookup = $appText.ToLowerInvariant()
    if ($script:BundleAliases.ContainsKey($lookup)) {
        $appText = $script:BundleAliases[$lookup]
    }
    $name = [System.IO.Path]::GetFileNameWithoutExtension($appText)
    $candidates = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne 0 -and $_.ProcessName.Equals($name, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($candidates.Count -eq 0) {
        $candidates = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne 0 -and $_.ProcessName.StartsWith($name, [StringComparison]::OrdinalIgnoreCase)
        })
    }
    if ($candidates.Count -eq 0) {
        throw "no running app matched '$appText'"
    }
    return ($candidates | Sort-Object StartTime -Descending | Select-Object -First 1)
}

function Get-TopLevelElementByTitle {
    param([string]$Title)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($root)
    while ($null -ne $child) {
        try {
            if ($child.Current.Name.IndexOf($Title, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $child
            }
        } catch {
        }
        $child = $walker.GetNextSibling($child)
    }
    throw "no top-level window title matched '$Title'"
}

function Resolve-AppElement {
    param([hashtable]$Arguments)
    $title = Get-ArgValue $Arguments @("title", "window_title")
    if ($null -ne $title) {
        return Get-TopLevelElementByTitle ([string]$title)
    }

    $proc = Get-ProcessFromArguments $Arguments
    if ($null -ne $proc) {
        if ($proc.MainWindowHandle -eq 0) {
            throw "process has no main window: $($proc.ProcessName) PID=$($proc.Id)"
        }
        return [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
    }

    $foreground = [OCU.NativeMethods]::GetForegroundWindow()
    if ($foreground -eq [IntPtr]::Zero) {
        throw "no foreground window"
    }
    return [System.Windows.Automation.AutomationElement]::FromHandle($foreground)
}

function Get-ControlTypeName {
    param([System.Windows.Automation.AutomationElement]$Element)
    try {
        return ($Element.Current.ControlType.ProgrammaticName -replace '^ControlType\.', '')
    } catch {
        return "?"
    }
}

function Get-ElementDescriptor {
    param([System.Windows.Automation.AutomationElement]$Element)
    try {
        $current = $Element.Current
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add((Get-ControlTypeName $Element))
        if (-not [string]::IsNullOrWhiteSpace($current.Name)) { $parts.Add(('"{0}"' -f $current.Name)) }
        if (-not [string]::IsNullOrWhiteSpace($current.AutomationId)) { $parts.Add(("AutomationId={0}" -f $current.AutomationId)) }
        if (-not [string]::IsNullOrWhiteSpace($current.ClassName)) { $parts.Add(("Class={0}" -f $current.ClassName)) }
        if (-not [string]::IsNullOrWhiteSpace($current.LocalizedControlType)) { $parts.Add(("Type={0}" -f $current.LocalizedControlType)) }
        $rect = $current.BoundingRectangle
        if ($rect.Width -gt 0 -and $rect.Height -gt 0) {
            $parts.Add(("Bounds=({0},{1},{2},{3})" -f [int]$rect.Left, [int]$rect.Top, [int]$rect.Width, [int]$rect.Height))
        }
        return ($parts -join " ")
    } catch {
        return "<unavailable element>"
    }
}

function Get-ElementInfo {
    param([System.Windows.Automation.AutomationElement]$Element)
    $current = $Element.Current
    $rect = $current.BoundingRectangle
    return [ordered]@{
        role = Get-ControlTypeName $Element
        name = $current.Name
        automationId = $current.AutomationId
        className = $current.ClassName
        localizedControlType = $current.LocalizedControlType
        processId = $current.ProcessId
        isEnabled = $current.IsEnabled
        bounds = [ordered]@{
            left = [int]$rect.Left
            top = [int]$rect.Top
            width = [int]$rect.Width
            height = [int]$rect.Height
        }
    }
}

function Get-ElementSearchText {
    param([System.Windows.Automation.AutomationElement]$Element)
    try {
        $current = $Element.Current
        return @(
            $current.Name,
            $current.AutomationId,
            $current.ClassName,
            $current.LocalizedControlType,
            $current.ControlType.ProgrammaticName
        ) -join "`n"
    } catch {
        return ""
    }
}

function Test-ElementMatches {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [string]$Query
    )
    $text = Get-ElementSearchText $Element
    return $text.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-ChildElements {
    param([System.Windows.Automation.AutomationElement]$Element)
    $items = New-Object System.Collections.Generic.List[object]
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($Element)
    while ($null -ne $child) {
        [void]$items.Add($child)
        $child = $walker.GetNextSibling($child)
    }
    return $items.ToArray()
}

function Add-TreeText {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxNodes,
        [System.Text.StringBuilder]$Builder
    )
    if ($script:TreeNodeCount -ge $MaxNodes) {
        return
    }
    $script:TreeNodeCount += 1
    $ref = $script:TreeNodeCount
    $script:RefMap[$ref] = $Element
    [void]$Builder.AppendLine(("{0}@e{1} {2}" -f ("  " * $Depth), $ref, (Get-ElementDescriptor $Element)))
    if ($Depth -ge $MaxDepth) {
        return
    }
    foreach ($child in (Get-ChildElements $Element)) {
        Add-TreeText $child ($Depth + 1) $MaxDepth $MaxNodes $Builder
        if ($script:TreeNodeCount -ge $MaxNodes) {
            [void]$Builder.AppendLine(("{0}... truncated at max_nodes={1}" -f ("  " * ($Depth + 1)), $MaxNodes))
            return
        }
    }
}

function Convert-ElementTreeToJson {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxNodes
    )
    if ($script:TreeNodeCount -ge $MaxNodes) {
        return $null
    }
    $script:TreeNodeCount += 1
    $ref = $script:TreeNodeCount
    $script:RefMap[$ref] = $Element
    $info = Get-ElementInfo $Element
    $node = [ordered]@{
        ref = $ref
        role = $info.role
        name = $info.name
        automationId = $info.automationId
        className = $info.className
        localizedControlType = $info.localizedControlType
        processId = $info.processId
        bounds = $info.bounds
    }
    if ($Depth -lt $MaxDepth) {
        $children = @()
        foreach ($child in (Get-ChildElements $Element)) {
            $childNode = Convert-ElementTreeToJson $child ($Depth + 1) $MaxDepth $MaxNodes
            if ($null -ne $childNode) {
                $children += ,$childNode
            }
            if ($script:TreeNodeCount -ge $MaxNodes) {
                break
            }
        }
        if ($children.Count -gt 0) {
            $node.children = $children
        }
    }
    return $node
}

function Search-ElementRecursive {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [string]$Query,
        [int]$Depth,
        [int]$MaxDepth,
        [int]$MaxNodes
    )
    if ($script:FindVisited -ge $MaxNodes -or $Depth -gt $MaxDepth) {
        return $null
    }
    $script:FindVisited += 1
    if (Test-ElementMatches $Element $Query) {
        return $Element
    }
    foreach ($child in (Get-ChildElements $Element)) {
        $hit = Search-ElementRecursive $child $Query ($Depth + 1) $MaxDepth $MaxNodes
        if ($null -ne $hit) {
            return $hit
        }
    }
    return $null
}

function Find-ElementByQuery {
    param(
        [System.Windows.Automation.AutomationElement]$Root,
        [string]$Query,
        [int]$MaxDepth = 30,
        [int]$MaxNodes = 1200
    )
    $script:FindVisited = 0
    return Search-ElementRecursive $Root $Query 0 $MaxDepth $MaxNodes
}

function Get-ElementCenter {
    param([System.Windows.Automation.AutomationElement]$Element)
    $rect = $Element.Current.BoundingRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) {
        throw "element has no usable bounding rectangle"
    }
    return New-Object System.Drawing.Point ([int]($rect.Left + ($rect.Width / 2))), ([int]($rect.Top + ($rect.Height / 2)))
}

function Invoke-MouseClick {
    param(
        [System.Drawing.Point]$Point,
        [switch]$Right
    )
    [System.Windows.Forms.Cursor]::Position = $Point
    Start-Sleep -Milliseconds 30
    if ($Right) {
        [OCU.NativeMethods]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero)
        [OCU.NativeMethods]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero)
    } else {
        [OCU.NativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        [OCU.NativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    }
}

function Invoke-ElementClick {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [hashtable]$Arguments,
        [switch]$Right
    )
    $label = Get-ElementSearchText $Element
    $blocked = Assert-SafeClickOrReturn $label $Arguments "click"
    if ($null -ne $blocked) {
        return $blocked
    }

    if (-not $Right) {
        $pattern = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            $pattern.Invoke()
            return New-ToolResult "InvokePattern ok"
        }
    }
    $point = Get-ElementCenter $Element
    Invoke-MouseClick $point -Right:$Right
    if ($Right) {
        return New-ToolResult ("right-clicked at ({0},{1})" -f $point.X, $point.Y)
    }
    return New-ToolResult ("clicked at ({0},{1})" -f $point.X, $point.Y)
}

function Invoke-ListApps {
    $rows = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } |
        Sort-Object ProcessName, Id |
        ForEach-Object {
            "{0}`tapp_id={0}`tPID={1}`tTitle={2}" -f $_.ProcessName, $_.Id, $_.MainWindowTitle
        })
    return New-ToolResult ($rows -join "`n")
}

function Invoke-GetTree {
    param([hashtable]$Arguments)
    $maxDepth = [int](Get-ArgValue $Arguments @("max_depth", "depth") 12)
    $maxNodes = [int](Get-ArgValue $Arguments @("max_nodes") 350)
    $root = Resolve-AppElement $Arguments
    $script:RefMap = @{}
    $script:TreeNodeCount = 0
    $builder = New-Object System.Text.StringBuilder
    Add-TreeText $root 0 $maxDepth $maxNodes $builder
    return New-ToolResult $builder.ToString()
}

function Invoke-GetTreeJson {
    param([hashtable]$Arguments)
    $maxDepth = [int](Get-ArgValue $Arguments @("max_depth", "depth") 12)
    $maxNodes = [int](Get-ArgValue $Arguments @("max_nodes") 350)
    $root = Resolve-AppElement $Arguments
    $script:RefMap = @{}
    $script:TreeNodeCount = 0
    $node = Convert-ElementTreeToJson $root 0 $maxDepth $maxNodes
    return New-ToolResult (ConvertTo-JsonLine $node)
}

function Invoke-FindElement {
    param([hashtable]$Arguments)
    $query = [string](Get-ArgValue $Arguments @("query"))
    if ([string]::IsNullOrWhiteSpace($query)) {
        return New-ToolError "query required"
    }
    $root = Resolve-AppElement $Arguments
    $hit = Find-ElementByQuery $root $query
    if ($null -eq $hit) {
        return New-ToolError "not found: $query"
    }
    $info = Get-ElementInfo $hit
    return New-ToolResult (ConvertTo-JsonLine $info)
}

function Invoke-ClickElementTool {
    param(
        [hashtable]$Arguments,
        [switch]$Right
    )
    $query = [string](Get-ArgValue $Arguments @("query"))
    if ([string]::IsNullOrWhiteSpace($query)) {
        return New-ToolError "query required"
    }
    $blocked = Assert-SafeClickOrReturn $query $Arguments "click query"
    if ($null -ne $blocked) {
        return $blocked
    }
    $root = Resolve-AppElement $Arguments
    $hit = Find-ElementByQuery $root $query
    if ($null -eq $hit) {
        return New-ToolError "not found: $query"
    }
    return Invoke-ElementClick $hit $Arguments -Right:$Right
}

function Invoke-ClickRef {
    param([hashtable]$Arguments)
    $ref = [int](Get-ArgValue $Arguments @("ref"))
    if (-not $script:RefMap.ContainsKey($ref)) {
        return New-ToolError "ref @e$ref not in map. call get_ax_tree first"
    }
    return Invoke-ElementClick $script:RefMap[$ref] $Arguments
}

function Invoke-Activate {
    param([hashtable]$Arguments)
    $proc = Get-ProcessFromArguments $Arguments
    if ($null -eq $proc) {
        $root = Resolve-AppElement $Arguments
        $pid = $root.Current.ProcessId
        $proc = Get-Process -Id $pid -ErrorAction Stop
    }
    if ($proc.MainWindowHandle -eq 0) {
        return New-ToolError "process has no main window: $($proc.ProcessName) PID=$($proc.Id)"
    }
    [void][OCU.NativeMethods]::ShowWindow($proc.MainWindowHandle, 9)
    $ok = [OCU.NativeMethods]::SetForegroundWindow($proc.MainWindowHandle)
    Start-Sleep -Milliseconds 200
    if ($ok) {
        return New-ToolResult "activated $($proc.ProcessName) PID=$($proc.Id)"
    }
    return New-ToolError "failed to activate $($proc.ProcessName) PID=$($proc.Id)"
}

function Get-ClipboardTextSafe {
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            return [System.Windows.Forms.Clipboard]::GetText()
        }
    } catch {
    }
    return $null
}

function Set-ClipboardTextSafe {
    param([string]$Text)
    [System.Windows.Forms.Clipboard]::SetText($Text)
}

function Invoke-TypeText {
    param([hashtable]$Arguments)
    $text = [string](Get-ArgValue $Arguments @("text"))
    if ($null -eq $text) {
        return New-ToolError "text required"
    }
    $blocked = Assert-SafeTextOrReturn $text $Arguments "type_text"
    if ($null -ne $blocked) {
        return $blocked
    }

    $oldText = Get-ClipboardTextSafe
    Set-ClipboardTextSafe $text
    [System.Windows.Forms.SendKeys]::SendWait("^v")
    Start-Sleep -Milliseconds 80
    if ($null -ne $oldText) {
        Set-ClipboardTextSafe $oldText
    }
    $script:KeyBuffer += $text
    return New-ToolResult "typed $($text.Length) chars"
}

function Convert-KeyForSendKeys {
    param([string]$Key)
    switch ($Key.ToLowerInvariant()) {
        "return" { return "{ENTER}" }
        "enter" { return "{ENTER}" }
        "tab" { return "{TAB}" }
        "space" { return " " }
        "delete" { return "{DEL}" }
        "backspace" { return "{BACKSPACE}" }
        "escape" { return "{ESC}" }
        "esc" { return "{ESC}" }
        "left" { return "{LEFT}" }
        "right" { return "{RIGHT}" }
        "up" { return "{UP}" }
        "down" { return "{DOWN}" }
        default {
            if ($Key.Length -eq 1) {
                return $Key
            }
            return $null
        }
    }
}

function Get-ModifierPrefix {
    param([object[]]$Modifiers)
    $prefix = ""
    foreach ($modifier in $Modifiers) {
        switch (([string]$modifier).ToLowerInvariant()) {
            "ctrl" { $prefix += "^" }
            "control" { $prefix += "^" }
            "cmd" { $prefix += "^" }
            "command" { $prefix += "^" }
            "alt" { $prefix += "%" }
            "option" { $prefix += "%" }
            "shift" { $prefix += "+" }
        }
    }
    return $prefix
}

function Update-KeyBufferOrBlock {
    param(
        [string]$Key,
        [object[]]$Modifiers,
        [hashtable]$Arguments
    )
    $lower = $Key.ToLowerInvariant()
    $hasControlModifier = $false
    foreach ($modifier in $Modifiers) {
        if (@("ctrl", "control", "cmd", "command", "alt", "option") -contains ([string]$modifier).ToLowerInvariant()) {
            $hasControlModifier = $true
        }
    }

    if ($hasControlModifier -and $lower -eq "v") {
        $clip = Get-ClipboardTextSafe
        if ($null -ne $clip) {
            $blocked = Assert-SafeTextOrReturn $clip $Arguments "clipboard paste"
            if ($null -ne $blocked) {
                return $blocked
            }
        }
        return $null
    }

    if ($hasControlModifier) {
        return $null
    }

    if (@("return", "enter") -contains $lower) {
        $blocked = Assert-SafeTextOrReturn $script:KeyBuffer $Arguments "enter after typed command"
        if ($null -ne $blocked) {
            return $blocked
        }
        $script:KeyBuffer = ""
        return $null
    }
    if ($lower -eq "escape") {
        $script:KeyBuffer = ""
        return $null
    }
    if ($lower -eq "backspace") {
        if ($script:KeyBuffer.Length -gt 0) {
            $script:KeyBuffer = $script:KeyBuffer.Substring(0, $script:KeyBuffer.Length - 1)
        }
        return $null
    }
    if ($lower -eq "space") {
        $script:KeyBuffer += " "
        return $null
    }
    if ($Key.Length -eq 1) {
        $script:KeyBuffer += $Key
    }
    return $null
}

function Invoke-KeyPress {
    param([hashtable]$Arguments)
    $key = [string](Get-ArgValue $Arguments @("key"))
    if ([string]::IsNullOrWhiteSpace($key)) {
        return New-ToolError "key required"
    }
    $mods = @(Get-ArgValue $Arguments @("modifiers", "mods") @())
    if ($mods.Count -eq 1 -and $mods[0] -is [string] -and ([string]$mods[0]).Contains(",")) {
        $mods = ([string]$mods[0]).Split(",")
    }
    $blocked = Update-KeyBufferOrBlock $key $mods $Arguments
    if ($null -ne $blocked) {
        return $blocked
    }
    $token = Convert-KeyForSendKeys $key
    if ($null -eq $token) {
        return New-ToolError "unknown key: $key"
    }
    $sequence = (Get-ModifierPrefix $mods) + $token
    [System.Windows.Forms.SendKeys]::SendWait($sequence)
    return New-ToolResult "key $key sent"
}

function Invoke-WaitFor {
    param([hashtable]$Arguments)
    $query = [string](Get-ArgValue $Arguments @("query"))
    if ([string]::IsNullOrWhiteSpace($query)) {
        return New-ToolError "query required"
    }
    $timeout = [double](Get-ArgValue $Arguments @("timeout") 10)
    $start = Get-Date
    do {
        try {
            $root = Resolve-AppElement $Arguments
            $hit = Find-ElementByQuery $root $query
            if ($null -ne $hit) {
                $elapsed = ((Get-Date) - $start).TotalSeconds
                return New-ToolResult ("found after {0:N2}s" -f $elapsed)
            }
        } catch {
        }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $start).TotalSeconds -lt $timeout)
    return New-ToolError "timeout after ${timeout}s waiting for: $query"
}

function Invoke-Scroll {
    param([hashtable]$Arguments)
    $dx = [int](Get-ArgValue $Arguments @("dx") 0)
    $dy = [int](Get-ArgValue $Arguments @("dy") 0)
    if ($dx -eq 0 -and $dy -eq 0) {
        return New-ToolError "dx and/or dy required"
    }
    $query = Get-ArgValue $Arguments @("query")
    if ($null -ne $query) {
        $root = Resolve-AppElement $Arguments
        $hit = Find-ElementByQuery $root ([string]$query)
        if ($null -eq $hit) {
            return New-ToolError "not found: $query"
        }
        [System.Windows.Forms.Cursor]::Position = (Get-ElementCenter $hit)
    }
    if ($dy -ne 0) {
        [OCU.NativeMethods]::mouse_event(0x0800, 0, 0, $dy, [UIntPtr]::Zero)
    }
    if ($dx -ne 0) {
        [OCU.NativeMethods]::mouse_event(0x01000, 0, 0, $dx, [UIntPtr]::Zero)
    }
    return New-ToolResult "scrolled dx=$dx dy=$dy"
}

function Invoke-ClipboardGet {
    $text = Get-ClipboardTextSafe
    if ($null -eq $text) {
        return New-ToolError "clipboard empty or not text"
    }
    return New-ToolResult $text
}

function Invoke-ClipboardSet {
    param([hashtable]$Arguments)
    $text = [string](Get-ArgValue $Arguments @("text"))
    if ($null -eq $text) {
        return New-ToolError "text required"
    }
    $blocked = Assert-SafeTextOrReturn $text $Arguments "clip_set"
    if ($null -ne $blocked) {
        return $blocked
    }
    Set-ClipboardTextSafe $text
    return New-ToolResult "set clipboard: $($text.Length) chars"
}

function Invoke-Screenshot {
    param([hashtable]$Arguments)
    $returnMode = [string](Get-ArgValue $Arguments @("return") "path")
    $outPath = [string](Get-ArgValue $Arguments @("out", "path") "")
    if ([string]::IsNullOrWhiteSpace($outPath)) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
        $outPath = Join-Path ([System.IO.Path]::GetTempPath()) "ocu-$stamp.png"
    }

    $hasTarget = $Arguments.ContainsKey("app_id") -or $Arguments.ContainsKey("process_name") -or $Arguments.ContainsKey("bundle_id") -or $Arguments.ContainsKey("pid") -or $Arguments.ContainsKey("title")
    if ($hasTarget) {
        $element = Resolve-AppElement $Arguments
        $rect = $element.Current.BoundingRectangle
        $bounds = New-Object System.Drawing.Rectangle ([int]$rect.Left), ([int]$rect.Top), ([int]$rect.Width), ([int]$rect.Height)
    } else {
        $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    }
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
        return New-ToolError "invalid screenshot bounds"
    }

    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
        $bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
    if ($returnMode -eq "base64") {
        return New-ImageResult ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($outPath)))
    }
    return New-ToolResult $outPath
}

function Invoke-Menu {
    param([hashtable]$Arguments)
    $path = [string](Get-ArgValue $Arguments @("path"))
    if ([string]::IsNullOrWhiteSpace($path)) {
        return New-ToolError "path required"
    }
    $parts = @($path.Split("/") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Count -eq 0) {
        return New-ToolError "empty path"
    }
    $root = Resolve-AppElement $Arguments
    $current = $root
    foreach ($part in $parts) {
        $hit = Find-ElementByQuery $current $part 10 500
        if ($null -eq $hit) {
            return New-ToolError "menu item not found: $part"
        }
        $current = $hit
    }
    return Invoke-ElementClick $current $Arguments
}

function Invoke-SafetyCheck {
    param([hashtable]$Arguments)
    $text = [string](Get-ArgValue $Arguments @("text"))
    $safety = Test-UnsafeText $text
    return New-ToolResult (ConvertTo-JsonLine $safety)
}

function Get-ToolsList {
    $appProperties = @{
        app_id = @{ type = "string"; description = "Windows process name, PID, or pid:<id>; bundle_id remains accepted as an alias" }
        process_name = @{ type = "string" }
        pid = @{ type = "integer" }
        title = @{ type = "string"; description = "substring of top-level window title" }
        bundle_id = @{ type = "string"; description = "compatibility alias for app_id on Windows" }
    }
    return @(
        @{ name = "list_apps"; description = "List running Windows GUI applications with app_id, PID, and window title"; inputSchema = @{ type = "object"; properties = @{} } },
        @{ name = "get_ax_tree"; description = "Get a numbered Microsoft UI Automation tree for a target window"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ max_depth = @{ type = "integer"; default = 12 }; max_nodes = @{ type = "integer"; default = 350 } }) } },
        @{ name = "ax_tree_json"; description = "Get the Microsoft UI Automation tree as JSON"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ max_depth = @{ type = "integer"; default = 12 }; max_nodes = @{ type = "integer"; default = 350 } }) } },
        @{ name = "find_element"; description = "Find the first UIA element matching query across name, automation id, class, and control type"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ query = @{ type = "string" } }); required = @("query") } },
        @{ name = "click_element"; description = "Find and click an element. Uses InvokePattern when available, with guarded pointer fallback."; inputSchema = @{ type = "object"; properties = ($appProperties + @{ query = @{ type = "string" }; allow_unsafe = @{ type = "boolean"; default = $false } }); required = @("query") } },
        @{ name = "click_ref"; description = "Click an @e ref from the most recent tree dump"; inputSchema = @{ type = "object"; properties = @{ ref = @{ type = "integer" }; allow_unsafe = @{ type = "boolean"; default = $false } }; required = @("ref") } },
        @{ name = "activate"; description = "Bring a Windows app to the foreground"; inputSchema = @{ type = "object"; properties = $appProperties } },
        @{ name = "type_text"; description = "Type Unicode text into the focused control. Blocks destructive shell or file modification text by default."; inputSchema = @{ type = "object"; properties = @{ text = @{ type = "string" }; allow_unsafe = @{ type = "boolean"; default = $false } }; required = @("text") } },
        @{ name = "key_press"; description = "Send one key with optional modifiers. Blocks unsafe paste or Enter after unsafe typed command."; inputSchema = @{ type = "object"; properties = @{ key = @{ type = "string" }; modifiers = @{ type = "array"; items = @{ type = "string" } }; allow_unsafe = @{ type = "boolean"; default = $false } }; required = @("key") } },
        @{ name = "wait_for"; description = "Poll until a UIA element matching query appears"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ query = @{ type = "string" }; timeout = @{ type = "number"; default = 10 } }); required = @("query") } },
        @{ name = "scroll"; description = "Send mouse wheel input, optionally over a matching element"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ query = @{ type = "string" }; dx = @{ type = "integer"; default = 0 }; dy = @{ type = "integer"; default = 0 } }) } },
        @{ name = "right_click"; description = "Right-click an element matching query, guarded against destructive labels"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ query = @{ type = "string" }; allow_unsafe = @{ type = "boolean"; default = $false } }); required = @("query") } },
        @{ name = "screenshot"; description = "Capture a PNG screenshot of the virtual screen or target window"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ return = @{ type = "string"; enum = @("path", "base64"); default = "path" }; out = @{ type = "string" } }) } },
        @{ name = "menu"; description = "Find slash-separated UIA menu labels and invoke the final item"; inputSchema = @{ type = "object"; properties = ($appProperties + @{ path = @{ type = "string" }; allow_unsafe = @{ type = "boolean"; default = $false } }); required = @("path") } },
        @{ name = "clip_get"; description = "Read Windows clipboard text"; inputSchema = @{ type = "object"; properties = @{} } },
        @{ name = "clip_set"; description = "Write Windows clipboard text, guarded against destructive shell or file modification text"; inputSchema = @{ type = "object"; properties = @{ text = @{ type = "string" }; allow_unsafe = @{ type = "boolean"; default = $false } }; required = @("text") } },
        @{ name = "safety_check"; description = "Check whether text would be blocked by the local command/file safety policy"; inputSchema = @{ type = "object"; properties = @{ text = @{ type = "string" } }; required = @("text") } }
    )
}

function Invoke-Tool {
    param(
        [string]$Name,
        [hashtable]$Arguments
    )
    try {
        switch ($Name) {
            "list_apps" { return Invoke-ListApps }
            "get_ax_tree" { return Invoke-GetTree $Arguments }
            "ax_tree_json" { return Invoke-GetTreeJson $Arguments }
            "find_element" { return Invoke-FindElement $Arguments }
            "click_element" { return Invoke-ClickElementTool $Arguments }
            "click_ref" { return Invoke-ClickRef $Arguments }
            "activate" { return Invoke-Activate $Arguments }
            "type_text" { return Invoke-TypeText $Arguments }
            "key_press" { return Invoke-KeyPress $Arguments }
            "wait_for" { return Invoke-WaitFor $Arguments }
            "scroll" { return Invoke-Scroll $Arguments }
            "right_click" { return Invoke-ClickElementTool $Arguments -Right }
            "screenshot" { return Invoke-Screenshot $Arguments }
            "menu" { return Invoke-Menu $Arguments }
            "clip_get" { return Invoke-ClipboardGet }
            "clip_set" { return Invoke-ClipboardSet $Arguments }
            "safety_check" { return Invoke-SafetyCheck $Arguments }
            default { return New-ToolError "unknown tool: $Name" }
        }
    } catch {
        return New-ToolError $_.Exception.Message
    }
}

function Send-JsonRpcResponse {
    param(
        [object]$Id,
        [object]$Result = $null,
        [hashtable]$ErrorObject = $null
    )
    $response = [ordered]@{ jsonrpc = "2.0" }
    if ($null -ne $Id) {
        $response.id = $Id
    }
    if ($null -ne $ErrorObject) {
        $response.error = $ErrorObject
    } else {
        $response.result = $Result
    }
    [Console]::Out.WriteLine((ConvertTo-JsonLine $response))
}

function Start-McpServer {
    Write-OcuLog "open-computer-use Windows MCP server started (stdio)"
    while ($null -ne ($line = [Console]::In.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $message = ConvertTo-Hashtable ($line | ConvertFrom-Json)
        } catch {
            continue
        }
        $method = [string](Get-ArgValue $message @("method") "")
        $id = Get-ArgValue $message @("id")
        $params = Get-ArgValue $message @("params") @{}
        if ($null -eq $params) {
            $params = @{}
        }
        switch ($method) {
            "initialize" {
                Send-JsonRpcResponse $id @{
                    protocolVersion = "2024-11-05"
                    capabilities = @{ tools = @{} }
                    serverInfo = @{ name = "open-computer-use-windows"; version = "0.1.0-windows" }
                }
            }
            "notifications/initialized" {
                continue
            }
            "tools/list" {
                Send-JsonRpcResponse $id @{ tools = Get-ToolsList }
            }
            "tools/call" {
                $name = [string](Get-ArgValue $params @("name") "")
                $arguments = Get-ArgValue $params @("arguments") @{}
                if ($null -eq $arguments) { $arguments = @{} }
                Send-JsonRpcResponse $id (Invoke-Tool $name $arguments)
            }
            "ping" {
                Send-JsonRpcResponse $id @{}
            }
            default {
                if ($null -ne $id) {
                    Send-JsonRpcResponse $id $null @{ code = -32601; message = "method not found: $method" }
                }
            }
        }
    }
}

function Parse-CliArgs {
    param([string[]]$InputArgs)
    if ($null -eq $InputArgs) {
        $InputArgs = @()
    }
    $items = @($InputArgs)
    $positional = New-Object System.Collections.Generic.List[string]
    $opts = @{}
    $flags = @{}
    $i = 0
    while ($i -lt $items.Count) {
        $arg = $items[$i]
        if ($arg.StartsWith("--")) {
            $key = $arg.Substring(2)
            if (($i + 1) -lt $items.Count -and -not $items[$i + 1].StartsWith("--")) {
                $opts[$key] = $items[$i + 1]
                $i += 2
            } else {
                $flags[$key] = $true
                $i += 1
            }
        } else {
            [void]$positional.Add($arg)
            $i += 1
        }
    }
    return @{ positional = $positional.ToArray(); opts = $opts; flags = $flags }
}

function Convert-CliToToolArgs {
    param([hashtable]$Parsed)
    $toolArgs = @{}
    foreach ($pair in @{
        "app-id" = "app_id"
        "process-name" = "process_name"
        "bundle-id" = "bundle_id"
        "pid" = "pid"
        "title" = "title"
        "query" = "query"
        "text" = "text"
        "key" = "key"
        "path" = "path"
        "out" = "out"
        "return" = "return"
        "depth" = "max_depth"
        "max-depth" = "max_depth"
        "max-nodes" = "max_nodes"
        "ref" = "ref"
        "dx" = "dx"
        "dy" = "dy"
        "timeout" = "timeout"
    }.GetEnumerator()) {
        if ($Parsed.opts.ContainsKey($pair.Key)) {
            $toolArgs[$pair.Value] = $Parsed.opts[$pair.Key]
        }
    }
    if ($Parsed.opts.ContainsKey("mods")) {
        $toolArgs.modifiers = $Parsed.opts["mods"].Split(",")
    }
    if ($Parsed.opts.ContainsKey("modifiers")) {
        $toolArgs.modifiers = $Parsed.opts["modifiers"].Split(",")
    }
    if ($Parsed.flags.ContainsKey("allow-unsafe")) {
        $toolArgs.allow_unsafe = $true
    }
    return $toolArgs
}

function Emit-CliResult {
    param(
        [hashtable]$Result,
        [bool]$Json
    )
    $isError = $Result.ContainsKey("isError") -and [bool]$Result.isError
    if ($Json) {
        $text = ""
        if ($Result.content.Count -gt 0 -and $Result.content[0].ContainsKey("text")) {
            $text = $Result.content[0].text
        }
        [Console]::Out.WriteLine((ConvertTo-JsonLine @{ ok = (-not $isError); text = $text }))
    } else {
        foreach ($item in $Result.content) {
            if ($item.ContainsKey("text")) {
                if ($isError) { [Console]::Error.WriteLine($item.text) } else { [Console]::Out.WriteLine($item.text) }
            }
        }
    }
    if ($isError) { exit 1 } else { exit 0 }
}

function Show-CliHelp {
    @"
open-computer-use Windows (PowerShell + Microsoft UI Automation)

Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 serve
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 apps
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 tree --app-id chrome --depth 6
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 click --app-id Cursor --query Save
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\ocu-windows.ps1 safety-check --text "rm -rf /"

Safety:
  Destructive shell text, recursive deletion, file write commands, registry deletion,
  and delete-like UI labels are blocked by default. Override requires both
  OCU_ALLOW_UNSAFE_INPUT=1 and --allow-unsafe.
"@ | Write-Output
}

function Start-Cli {
    param([string[]]$InputArgs)
    if ($null -eq $InputArgs) {
        $InputArgs = @()
    }
    $items = @($InputArgs)
    if ($items.Count -eq 0 -or $items[0] -in @("help", "--help", "-h")) {
        Show-CliHelp
        exit 0
    }
    if ($items[0] -eq "serve") {
        Start-McpServer
        exit 0
    }
    $sub = $items[0]
    $parsed = Parse-CliArgs @($items | Select-Object -Skip 1)
    $json = $parsed.flags.ContainsKey("json")
    $toolArgs = Convert-CliToToolArgs $parsed
    switch ($sub) {
        "apps" { Emit-CliResult (Invoke-ListApps) $json }
        "tree" { Emit-CliResult (Invoke-GetTree $toolArgs) $json }
        "find" { Emit-CliResult (Invoke-FindElement $toolArgs) $json }
        "click" { Emit-CliResult (Invoke-ClickElementTool $toolArgs) $json }
        "rclick" { Emit-CliResult (Invoke-ClickElementTool $toolArgs -Right) $json }
        "activate" { Emit-CliResult (Invoke-Activate $toolArgs) $json }
        "type" { Emit-CliResult (Invoke-TypeText $toolArgs) $json }
        "key" { Emit-CliResult (Invoke-KeyPress $toolArgs) $json }
        "wait" { Emit-CliResult (Invoke-WaitFor $toolArgs) $json }
        "scroll" { Emit-CliResult (Invoke-Scroll $toolArgs) $json }
        "shot" { Emit-CliResult (Invoke-Screenshot $toolArgs) $json }
        "menu" { Emit-CliResult (Invoke-Menu $toolArgs) $json }
        "safety-check" { Emit-CliResult (Invoke-SafetyCheck $toolArgs) $json }
        "clip" {
            $action = ""
            if ($parsed.positional.Count -gt 0) { $action = $parsed.positional[0] }
            switch ($action) {
                "get" { Emit-CliResult (Invoke-ClipboardGet) $json }
                "set" { Emit-CliResult (Invoke-ClipboardSet $toolArgs) $json }
                default { [Console]::Error.WriteLine("clip needs get or set"); exit 2 }
            }
        }
        default {
            [Console]::Error.WriteLine("unknown subcommand: $sub")
            Show-CliHelp
            exit 2
        }
    }
}

if ($Serve) {
    Start-McpServer
} else {
    Start-Cli $CliArgs
}
