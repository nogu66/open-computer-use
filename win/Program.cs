using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Automation;
using Forms = System.Windows.Forms;

namespace WinComputerUse;

internal static class Program
{
    private const string Version = "0.1.0";
    private const string ServerName = "win-computer-use";
    private static readonly Dictionary<int, AutomationElement> RefMap = new();
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web) { WriteIndented = false };

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] != "serve")
        {
            return CliMain(args);
        }

        Log($"{ServerName} MCP server started (stdio) v{Version}");
        string? line;
        while ((line = Console.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            try
            {
                var msg = JsonNode.Parse(line)?.AsObject();
                if (msg is null) continue;
                var method = msg["method"]?.GetValue<string>() ?? string.Empty;
                var id = msg["id"];
                var parameters = msg["params"]?.AsObject();

                switch (method)
                {
                    case "initialize":
                        Respond(id, new JsonObject
                        {
                            ["protocolVersion"] = "2024-11-05",
                            ["capabilities"] = new JsonObject { ["tools"] = new JsonObject() },
                            ["serverInfo"] = new JsonObject { ["name"] = ServerName, ["version"] = Version }
                        });
                        break;
                    case "notifications/initialized":
                        break;
                    case "tools/list":
                        Respond(id, new JsonObject { ["tools"] = ToolsList() });
                        break;
                    case "tools/call":
                        var name = parameters?["name"]?.GetValue<string>() ?? string.Empty;
                        var toolArgs = parameters?["arguments"]?.AsObject() ?? new JsonObject();
                        Respond(id, HandleTool(name, toolArgs));
                        break;
                    case "ping":
                        Respond(id, new JsonObject());
                        break;
                    default:
                        if (id is not null) RespondError(id, -32601, $"method not found: {method}");
                        break;
                }
            }
            catch (Exception ex)
            {
                Log(ex.ToString());
            }
        }
        return 0;
    }

    private static JsonArray ToolsList() => new()
    {
        Tool("list_apps", "List running Windows GUI applications with process names, PIDs, and top-level window titles.", new JsonObject { ["type"] = "object", ["properties"] = new JsonObject() }),
        Tool("get_ax_tree", "Get the UI Automation tree of a running app's main/focused window. Returns numbered text tree. Use refs with click_ref.", Schema(new() { ["bundle_id"] = Str("Process name, pid:1234, or window title substring"), ["max_depth"] = Int(12), ["scope"] = Enum(new[] { "window", "app" }, "window") }, "bundle_id")),
        Tool("ax_tree_json", "Like get_ax_tree but returns JSON tree with ref/name/control_type/automation_id/value/rectangle/children.", Schema(new() { ["bundle_id"] = Str("Process name, pid:1234, or window title substring"), ["max_depth"] = Int(12), ["scope"] = Enum(new[] { "window", "app" }, "window") }, "bundle_id")),
        Tool("find_element", "Find first UIA element matching a substring in name, automation id, class, value, or control type.", Schema(new() { ["bundle_id"] = Str(), ["query"] = Str() }, "bundle_id", "query")),
        Tool("click_element", "Find element by query and click it. Prefers InvokePattern, falls back to center click.", Schema(new() { ["bundle_id"] = Str(), ["query"] = Str() }, "bundle_id", "query")),
        Tool("click_ref", "Click an element by its @e ref number from the last get_ax_tree/ax_tree_json call.", Schema(new() { ["ref"] = Int() }, "ref")),
        Tool("activate", "Bring an app/window to the foreground. Call before sending text or keys.", Schema(new() { ["bundle_id"] = Str() }, "bundle_id")),
        Tool("type_text", "Type Unicode text into the currently focused field. Uses clipboard paste for reliability.", Schema(new() { ["text"] = Str() }, "text")),
        Tool("key_press", "Send one key, optionally with modifiers. Example: key=l modifiers=[ctrl] focuses browser address bar.", Schema(new() { ["key"] = Str(), ["modifiers"] = ArrStr() }, "key")),
        Tool("wait_for", "Poll until an element matching query appears or timeout expires.", Schema(new() { ["bundle_id"] = Str(), ["query"] = Str(), ["timeout"] = Num(10) }, "bundle_id", "query")),
        Tool("scroll", "Send mouse wheel event. With bundle_id+query, scrolls over that element; otherwise at current cursor.", Schema(new() { ["bundle_id"] = Str(), ["query"] = Str(), ["dx"] = Int(0), ["dy"] = Int(0) })),
        Tool("right_click", "Right-click an element matching query.", Schema(new() { ["bundle_id"] = Str(), ["query"] = Str() }, "bundle_id", "query")),
        Tool("screenshot", "Capture PNG screenshot. If bundle_id is given, captures that window rectangle; otherwise full virtual screen.", Schema(new() { ["bundle_id"] = Str(), ["return"] = Enum(new[] { "path", "base64" }, "path") })),
        Tool("menu", "Best-effort: find a MenuItem by slash-separated path's last segment and invoke it.", Schema(new() { ["bundle_id"] = Str(), ["path"] = Str() }, "bundle_id", "path")),
        Tool("clip_get", "Read clipboard text.", new JsonObject { ["type"] = "object", ["properties"] = new JsonObject() }),
        Tool("clip_set", "Write clipboard text.", Schema(new() { ["text"] = Str() }, "text"))
    };

    private static JsonObject Tool(string name, string description, JsonObject schema) => new() { ["name"] = name, ["description"] = description, ["inputSchema"] = schema };
    private static JsonObject Str(string description = "") => string.IsNullOrEmpty(description) ? new JsonObject { ["type"] = "string" } : new JsonObject { ["type"] = "string", ["description"] = description };
    private static JsonObject Int(int? def = null) { var o = new JsonObject { ["type"] = "integer" }; if (def.HasValue) o["default"] = def.Value; return o; }
    private static JsonObject Num(double def) => new() { ["type"] = "number", ["default"] = def };
    private static JsonObject ArrStr() => new() { ["type"] = "array", ["items"] = new JsonObject { ["type"] = "string" } };
    private static JsonObject Enum(string[] values, string def) => new() { ["type"] = "string", ["enum"] = new JsonArray(values.Select(v => JsonValue.Create(v)).ToArray<JsonNode?>()), ["default"] = def };
    private static JsonObject Schema(Dictionary<string, JsonObject> props, params string[] required) => new() { ["type"] = "object", ["properties"] = new JsonObject(props.Select(kv => KeyValuePair.Create<string, JsonNode?>(kv.Key, kv.Value)).ToArray()), ["required"] = new JsonArray(required.Select(v => JsonValue.Create(v)).ToArray<JsonNode?>()) };

    private static JsonObject HandleTool(string name, JsonObject args)
    {
        try
        {
            return name switch
            {
                "list_apps" => TListApps(),
                "get_ax_tree" => TAxTree(args, asJson: false),
                "ax_tree_json" => TAxTree(args, asJson: true),
                "find_element" => TFindElement(args),
                "click_element" => TClickElement(args),
                "click_ref" => TClickRef(args),
                "activate" => TActivate(args),
                "type_text" => TTypeText(args),
                "key_press" => TKeyPress(args),
                "wait_for" => TWaitFor(args),
                "scroll" => TScroll(args),
                "right_click" => TRightClick(args),
                "screenshot" => TScreenshot(args),
                "menu" => TMenu(args),
                "clip_get" => TClipGet(),
                "clip_set" => TClipSet(args),
                _ => ToolError($"unknown tool: {name}")
            };
        }
        catch (ElementNotAvailableException ex) { return ToolError($"UI element is no longer available: {ex.Message}"); }
        catch (Exception ex) { return ToolError(ex.Message); }
    }

    private static JsonObject TListApps()
    {
        var rows = new List<string>();
        foreach (var win in WindowInfo.EnumerateTopLevelWindows())
        {
            try
            {
                var p = Process.GetProcessById(win.Pid);
                rows.Add($"{p.ProcessName}\tPID={win.Pid}\tHWND=0x{win.Hwnd.ToInt64():X}\t{win.Title}");
            }
            catch { }
        }
        return ToolResult(string.Join('\n', rows));
    }

    private static JsonObject TAxTree(JsonObject args, bool asJson)
    {
        var root = ResolveElement(Required(args, "bundle_id"));
        var maxDepth = GetInt(args, "max_depth", 12);
        RefMap.Clear();
        var counter = 0;
        if (asJson)
        {
            var node = WalkJson(root, maxDepth, 0, ref counter);
            return ToolResult(node.ToJsonString(JsonOptions));
        }
        var sb = new StringBuilder();
        WalkText(root, maxDepth, 0, ref counter, sb);
        return ToolResult(sb.ToString());
    }

    private static JsonObject TFindElement(JsonObject args)
    {
        var root = ResolveElement(Required(args, "bundle_id"));
        var query = Required(args, "query");
        var hit = FindElement(root, query) ?? throw new InvalidOperationException($"not found: {query}");
        return ToolResult(DescribeElement(hit, includeRect: true, includePatterns: true));
    }

    private static JsonObject TClickElement(JsonObject args)
    {
        var root = ResolveElement(Required(args, "bundle_id"));
        var query = Required(args, "query");
        var hit = FindElement(root, query) ?? throw new InvalidOperationException($"not found: {query}");
        return ClickAutomationElement(hit, $"clicked element matching '{query}'");
    }

    private static JsonObject TClickRef(JsonObject args)
    {
        var refNo = GetInt(args, "ref", -1);
        if (!RefMap.TryGetValue(refNo, out var element)) return ToolError($"ref @e{refNo} not in map. call get_ax_tree first");
        return ClickAutomationElement(element, $"clicked @e{refNo}");
    }

    private static JsonObject TActivate(JsonObject args)
    {
        var win = ResolveWindow(Required(args, "bundle_id"));
        if (IsIconic(win.Hwnd)) ShowWindow(win.Hwnd, 9);
        SetForegroundWindow(win.Hwnd);
        return ToolResult($"activated PID={win.Pid} HWND=0x{win.Hwnd.ToInt64():X} {win.Title}");
    }

    private static JsonObject TTypeText(JsonObject args)
    {
        var text = Required(args, "text");
        Forms.Clipboard.SetText(text);
        SendModifiedKey("v", new[] { "ctrl" });
        return ToolResult($"pasted {text.Length} chars");
    }

    private static JsonObject TKeyPress(JsonObject args)
    {
        var key = Required(args, "key");
        var mods = GetStringArray(args, "modifiers");
        SendModifiedKey(key, mods);
        return ToolResult($"key {key} sent");
    }

    private static JsonObject TWaitFor(JsonObject args)
    {
        var spec = Required(args, "bundle_id");
        var query = Required(args, "query");
        var timeout = GetDouble(args, "timeout", 10.0);
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < timeout)
        {
            try
            {
                var root = ResolveElement(spec);
                if (FindElement(root, query) is not null) return ToolResult($"found after {sw.Elapsed.TotalSeconds:F2}s");
            }
            catch { }
            Thread.Sleep(300);
        }
        return ToolError($"timeout after {timeout}s waiting for: {query}");
    }

    private static JsonObject TScroll(JsonObject args)
    {
        var dx = GetInt(args, "dx", 0);
        var dy = GetInt(args, "dy", 0);
        if (dx == 0 && dy == 0) return ToolError("dx and/or dy required");
        if (args["bundle_id"] is not null && args["query"] is not null)
        {
            var root = ResolveElement(Required(args, "bundle_id"));
            var hit = FindElement(root, Required(args, "query")) ?? throw new InvalidOperationException("target element not found");
            var c = Center(hit.Current.BoundingRectangle);
            SetCursorPos((int)c.X, (int)c.Y);
        }
        SendWheel(dx, dy);
        return ToolResult($"scrolled dx={dx} dy={dy}");
    }

    private static JsonObject TRightClick(JsonObject args)
    {
        var root = ResolveElement(Required(args, "bundle_id"));
        var hit = FindElement(root, Required(args, "query")) ?? throw new InvalidOperationException("target element not found");
        var c = Center(hit.Current.BoundingRectangle);
        MouseClick((int)c.X, (int)c.Y, right: true);
        return ToolResult($"right-clicked at ({c.X:F0},{c.Y:F0})");
    }

    private static JsonObject TScreenshot(JsonObject args)
    {
        Rectangle rect;
        if (args["bundle_id"] is not null)
        {
            var win = ResolveWindow(Required(args, "bundle_id"));
            GetWindowRect(win.Hwnd, out var r);
            rect = Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom);
        }
        else
        {
            rect = Forms.SystemInformation.VirtualScreen;
        }
        var path = Path.Combine(Path.GetTempPath(), $"wcu-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.png");
        using var bmp = new Bitmap(rect.Width, rect.Height);
        using (var g = Graphics.FromImage(bmp)) g.CopyFromScreen(rect.Left, rect.Top, 0, 0, rect.Size);
        bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        if (GetString(args, "return", "path") == "base64")
        {
            var b64 = Convert.ToBase64String(File.ReadAllBytes(path));
            return new JsonObject { ["content"] = new JsonArray(new JsonObject { ["type"] = "image", ["data"] = b64, ["mimeType"] = "image/png" }) };
        }
        return ToolResult(path);
    }

    private static JsonObject TMenu(JsonObject args)
    {
        var last = Required(args, "path").Split('/', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault();
        if (string.IsNullOrWhiteSpace(last)) return ToolError("empty menu path");
        var root = ResolveElement(Required(args, "bundle_id"));
        var condition = new AndCondition(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.MenuItem), new PropertyCondition(AutomationElement.NameProperty, last));
        var item = root.FindFirst(TreeScope.Descendants, condition) ?? FindElement(root, last);
        if (item is null) return ToolError($"menu item not found: {last}");
        return ClickAutomationElement(item, $"pressed menu item: {last}");
    }

    private static JsonObject TClipGet()
    {
        return Forms.Clipboard.ContainsText() ? ToolResult(Forms.Clipboard.GetText()) : ToolError("clipboard empty or not text");
    }

    private static JsonObject TClipSet(JsonObject args)
    {
        var text = Required(args, "text");
        Forms.Clipboard.SetText(text);
        return ToolResult($"set clipboard: {text.Length} chars");
    }

    private static void WalkText(AutomationElement e, int maxDepth, int depth, ref int counter, StringBuilder sb)
    {
        counter++;
        RefMap[counter] = e;
        sb.Append(' ', depth * 2).Append("@e").Append(counter).Append(' ').AppendLine(DescribeElement(e, includeRect: false, includePatterns: false));
        if (depth >= maxDepth) return;
        foreach (AutomationElement child in SafeChildren(e)) WalkText(child, maxDepth, depth + 1, ref counter, sb);
    }

    private static JsonObject WalkJson(AutomationElement e, int maxDepth, int depth, ref int counter)
    {
        counter++;
        RefMap[counter] = e;
        var c = e.Current;
        var o = new JsonObject
        {
            ["ref"] = counter,
            ["name"] = c.Name,
            ["control_type"] = ShortControlType(c.ControlType),
            ["automation_id"] = c.AutomationId,
            ["class_name"] = c.ClassName,
            ["process_id"] = c.ProcessId
        };
        TryAddValue(e, o);
        if (!c.BoundingRectangle.IsEmpty) o["rectangle"] = new JsonObject { ["x"] = c.BoundingRectangle.X, ["y"] = c.BoundingRectangle.Y, ["width"] = c.BoundingRectangle.Width, ["height"] = c.BoundingRectangle.Height };
        if (depth < maxDepth)
        {
            var arr = new JsonArray();
            foreach (AutomationElement child in SafeChildren(e)) arr.Add(WalkJson(child, maxDepth, depth + 1, ref counter));
            if (arr.Count > 0) o["children"] = arr;
        }
        return o;
    }

    private static IEnumerable<AutomationElement> SafeChildren(AutomationElement e)
    {
        AutomationElementCollection? children = null;
        try { children = e.FindAll(TreeScope.Children, Condition.TrueCondition); } catch { }
        if (children is null) yield break;
        foreach (AutomationElement child in children) yield return child;
    }

    private static AutomationElement? FindElement(AutomationElement root, string query)
    {
        query = query.Trim();
        if (Matches(root, query)) return root;
        var walker = new Queue<AutomationElement>(SafeChildren(root));
        var visited = 0;
        while (walker.Count > 0 && visited++ < 5000)
        {
            var e = walker.Dequeue();
            if (Matches(e, query)) return e;
            foreach (var child in SafeChildren(e)) walker.Enqueue(child);
        }
        return null;
    }

    private static bool Matches(AutomationElement e, string q)
    {
        try
        {
            var c = e.Current;
            var fields = new[] { c.Name, c.AutomationId, c.ClassName, ShortControlType(c.ControlType), TryGetValue(e) };
            return fields.Any(v => !string.IsNullOrEmpty(v) && v.Contains(q, StringComparison.OrdinalIgnoreCase));
        }
        catch { return false; }
    }

    private static JsonObject ClickAutomationElement(AutomationElement e, string okPrefix)
    {
        if (TryInvoke(e)) return ToolResult($"{okPrefix} via InvokePattern");
        if (TrySelect(e)) return ToolResult($"{okPrefix} via SelectionItemPattern");
        if (TryExpandCollapse(e)) return ToolResult($"{okPrefix} via ExpandCollapsePattern");
        var rect = e.Current.BoundingRectangle;
        if (rect.IsEmpty) return ToolError("element has no invokable pattern and no geometry");
        var c = Center(rect);
        MouseClick((int)c.X, (int)c.Y, right: false);
        return ToolResult($"{okPrefix} at ({c.X:F0},{c.Y:F0})");
    }

    private static bool TryInvoke(AutomationElement e) { try { if (e.TryGetCurrentPattern(InvokePattern.Pattern, out var p)) { ((InvokePattern)p).Invoke(); return true; } } catch { } return false; }
    private static bool TrySelect(AutomationElement e) { try { if (e.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var p)) { ((SelectionItemPattern)p).Select(); return true; } } catch { } return false; }
    private static bool TryExpandCollapse(AutomationElement e) { try { if (e.TryGetCurrentPattern(ExpandCollapsePattern.Pattern, out var p)) { var ep = (ExpandCollapsePattern)p; if (ep.Current.ExpandCollapseState == ExpandCollapseState.Collapsed) ep.Expand(); else ep.Collapse(); return true; } } catch { } return false; }

    private static string DescribeElement(AutomationElement e, bool includeRect, bool includePatterns)
    {
        var c = e.Current;
        var parts = new List<string> { ShortControlType(c.ControlType) };
        if (!string.IsNullOrWhiteSpace(c.Name)) parts.Add($"\"{Short(c.Name)}\"");
        if (!string.IsNullOrWhiteSpace(c.AutomationId)) parts.Add($"AutomationId:{c.AutomationId}");
        if (!string.IsNullOrWhiteSpace(c.ClassName)) parts.Add($"Class:{c.ClassName}");
        var value = TryGetValue(e);
        if (!string.IsNullOrWhiteSpace(value)) parts.Add($"Value:{Short(value)}");
        if (includeRect && !c.BoundingRectangle.IsEmpty) parts.Add($"Rect:({c.BoundingRectangle.X:F0},{c.BoundingRectangle.Y:F0},{c.BoundingRectangle.Width:F0},{c.BoundingRectangle.Height:F0})");
        if (includePatterns) parts.Add("Patterns:" + string.Join(',', e.GetSupportedPatterns().Select(p => p.ProgrammaticName.Replace("PatternIdentifiers.", ""))));
        return string.Join(' ', parts);
    }

    private static string ShortControlType(ControlType t) => t.ProgrammaticName.Replace("ControlType.", "");
    private static string Short(string s) => s.Length > 120 ? s[..120] + "..." : s.Trim();
    private static string? TryGetValue(AutomationElement e) { try { return e.TryGetCurrentPattern(ValuePattern.Pattern, out var p) ? ((ValuePattern)p).Current.Value : null; } catch { return null; } }
    private static void TryAddValue(AutomationElement e, JsonObject o) { var v = TryGetValue(e); if (!string.IsNullOrEmpty(v)) o["value"] = v; }

    private static AutomationElement ResolveElement(string spec) => AutomationElement.FromHandle(ResolveWindow(spec).Hwnd);

    private static WindowInfo ResolveWindow(string spec)
    {
        var windows = WindowInfo.EnumerateTopLevelWindows().ToList();
        if (spec.StartsWith("pid:", StringComparison.OrdinalIgnoreCase) && int.TryParse(spec[4..], out var pid))
        {
            var byPid = windows.FirstOrDefault(w => w.Pid == pid);
            if (byPid.Hwnd != IntPtr.Zero) return byPid;
        }
        foreach (var w in windows)
        {
            try
            {
                var p = Process.GetProcessById(w.Pid);
                if (string.Equals(p.ProcessName, spec, StringComparison.OrdinalIgnoreCase)) return w;
            }
            catch { }
        }
        var byTitle = windows.FirstOrDefault(w => w.Title.Contains(spec, StringComparison.OrdinalIgnoreCase));
        if (byTitle.Hwnd != IntPtr.Zero) return byTitle;
        throw new InvalidOperationException($"not running or no visible top-level window: {spec}");
    }

    private static int CliMain(string[] args)
    {
        if (args.Length == 0 || args[0] is "--help" or "-h" or "help") { PrintHelp(); return 0; }
        if (args[0] is "--version" or "-v" or "version") { Console.WriteLine($"wcu {Version}"); return 0; }
        var parsed = ParseArgs(args.Skip(1).ToArray());
        var toolArgs = new JsonObject();
        MapOpt(parsed, toolArgs, "bundle-id", "bundle_id"); MapOpt(parsed, toolArgs, "query", "query"); MapOpt(parsed, toolArgs, "text", "text"); MapOpt(parsed, toolArgs, "key", "key"); MapOpt(parsed, toolArgs, "path", "path"); MapOpt(parsed, toolArgs, "scope", "scope"); MapOpt(parsed, toolArgs, "out", "out");
        if (parsed.Opts.TryGetValue("depth", out var depth) && int.TryParse(depth, out var d)) toolArgs["max_depth"] = d;
        if (parsed.Opts.TryGetValue("ref", out var rf) && int.TryParse(rf, out var r)) toolArgs["ref"] = r;
        if (parsed.Opts.TryGetValue("dx", out var dx) && int.TryParse(dx, out var x)) toolArgs["dx"] = x;
        if (parsed.Opts.TryGetValue("dy", out var dy) && int.TryParse(dy, out var y)) toolArgs["dy"] = y;
        if (parsed.Opts.TryGetValue("timeout", out var to) && double.TryParse(to, out var t)) toolArgs["timeout"] = t;
        if (parsed.Opts.TryGetValue("mods", out var mods)) toolArgs["modifiers"] = new JsonArray(mods.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).Select(v => JsonValue.Create(v)).ToArray<JsonNode?>());
        if (parsed.Flags.Contains("json")) toolArgs["return"] = "base64";

        var result = args[0] switch
        {
            "apps" => TListApps(),
            "activate" => TActivate(toolArgs),
            "tree" => TAxTree(toolArgs, parsed.Flags.Contains("json")),
            "find" => TFindElement(toolArgs),
            "click" => TClickElement(toolArgs),
            "rclick" => TRightClick(toolArgs),
            "type" => TTypeText(toolArgs),
            "key" => TKeyPress(toolArgs),
            "wait" => TWaitFor(toolArgs),
            "scroll" => TScroll(toolArgs),
            "menu" => TMenu(toolArgs),
            "shot" => TScreenshot(toolArgs),
            "clip" when parsed.Positional.FirstOrDefault() == "get" => TClipGet(),
            "clip" when parsed.Positional.FirstOrDefault() == "set" => TClipSet(toolArgs),
            _ => ToolError($"unknown subcommand: {args[0]}")
        };
        var isError = result["isError"]?.GetValue<bool>() ?? false;
        Console.WriteLine(ExtractText(result));
        return isError ? 1 : 0;
    }

    private static void MapOpt(ParsedArgs parsed, JsonObject o, string opt, string key) { if (parsed.Opts.TryGetValue(opt, out var v)) o[key] = v; }
    private static ParsedArgs ParseArgs(string[] args)
    {
        var p = new ParsedArgs();
        for (var i = 0; i < args.Length;)
        {
            if (args[i].StartsWith("--"))
            {
                var k = args[i][2..];
                if (i + 1 < args.Length && !args[i + 1].StartsWith("--")) { p.Opts[k] = args[i + 1]; i += 2; }
                else { p.Flags.Add(k); i++; }
            }
            else { p.Positional.Add(args[i]); i++; }
        }
        return p;
    }

    private sealed class ParsedArgs { public List<string> Positional { get; } = new(); public Dictionary<string, string> Opts { get; } = new(); public HashSet<string> Flags { get; } = new(); }

    private static void PrintHelp() => Console.WriteLine($"""
win-computer-use (wcu) v{Version} — Windows computer use via UI Automation + SendInput.

USAGE:
  wcu serve
  wcu apps
  wcu activate --bundle-id <process|pid:123|title>
  wcu tree --bundle-id <target> [--depth N] [--json]
  wcu find --bundle-id <target> --query <text>
  wcu click --bundle-id <target> --query <text>
  wcu type --text <text>
  wcu key --key <name> [--mods ctrl,shift,alt,win]
  wcu scroll [--bundle-id <target> --query <text>] [--dx N] [--dy N]
  wcu shot [--bundle-id <target>]
  wcu clip get | clip set --text <text>

EXAMPLES:
  wcu apps
  wcu activate --bundle-id chrome
  wcu key --key l --mods ctrl
  wcu type --text https://example.com
  wcu key --key enter
""");

    private static JsonObject ToolResult(string text) => new() { ["content"] = new JsonArray(new JsonObject { ["type"] = "text", ["text"] = text }) };
    private static JsonObject ToolError(string text) => new() { ["content"] = new JsonArray(new JsonObject { ["type"] = "text", ["text"] = text }), ["isError"] = true };
    private static string ExtractText(JsonObject result) => string.Join('\n', result["content"]?.AsArray().Select(x => x?["text"]?.GetValue<string>()).Where(x => x is not null) ?? Array.Empty<string>());
    private static string Required(JsonObject args, string key) => args[key]?.GetValue<string>() ?? throw new ArgumentException($"{key} required");
    private static string GetString(JsonObject args, string key, string def) => args[key]?.GetValue<string>() ?? def;
    private static int GetInt(JsonObject args, string key, int def) => args[key]?.GetValue<int>() ?? def;
    private static double GetDouble(JsonObject args, string key, double def) => args[key]?.GetValue<double>() ?? def;
    private static string[] GetStringArray(JsonObject args, string key) => args[key]?.AsArray().Select(x => x?.GetValue<string>() ?? "").Where(x => x.Length > 0).ToArray() ?? Array.Empty<string>();
    private static void Respond(JsonNode? id, JsonNode result) { var o = new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id?.DeepClone(), ["result"] = result }; Console.WriteLine(o.ToJsonString(JsonOptions)); Console.Out.Flush(); }
    private static void RespondError(JsonNode? id, int code, string message) { var o = new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id?.DeepClone(), ["error"] = new JsonObject { ["code"] = code, ["message"] = message } }; Console.WriteLine(o.ToJsonString(JsonOptions)); Console.Out.Flush(); }
    private static void Log(string message) => Console.Error.WriteLine($"[wcu] {message}");

    private static PointF Center(System.Windows.Rect r) => new((float)(r.X + r.Width / 2), (float)(r.Y + r.Height / 2));

    private static void SendModifiedKey(string key, IEnumerable<string> mods)
    {
        var prefix = string.Concat(mods.Select(m => m.ToLowerInvariant() switch { "ctrl" or "control" => "^", "shift" => "+", "alt" or "option" => "%", "win" or "windows" => "", _ => "" }));
        var normalized = key.ToLowerInvariant() switch { "return" or "enter" => "{ENTER}", "escape" or "esc" => "{ESC}", "tab" => "{TAB}", "space" => " ", "left" => "{LEFT}", "right" => "{RIGHT}", "up" => "{UP}", "down" => "{DOWN}", "delete" or "del" => "{DEL}", "backspace" => "{BACKSPACE}", _ => key.Length == 1 ? key : "{" + key.ToUpperInvariant() + "}" };
        Forms.SendKeys.SendWait(prefix + normalized);
    }

    private static void MouseClick(int x, int y, bool right)
    {
        SetCursorPos(x, y);
        var down = right ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_LEFTDOWN;
        var up = right ? MOUSEEVENTF_RIGHTUP : MOUSEEVENTF_LEFTUP;
        mouse_event(down, 0, 0, 0, UIntPtr.Zero);
        mouse_event(up, 0, 0, 0, UIntPtr.Zero);
    }

    private static void SendWheel(int dx, int dy)
    {
        if (dy != 0) mouse_event(MOUSEEVENTF_WHEEL, 0, 0, dy, UIntPtr.Zero);
        if (dx != 0) mouse_event(MOUSEEVENTF_HWHEEL, 0, 0, dx, UIntPtr.Zero);
    }

    private readonly record struct WindowInfo(IntPtr Hwnd, int Pid, string Title)
    {
        public static IEnumerable<WindowInfo> EnumerateTopLevelWindows()
        {
            var list = new List<WindowInfo>();
            EnumWindows((hwnd, _) =>
            {
                if (!IsWindowVisible(hwnd)) return true;
                var len = GetWindowTextLength(hwnd);
                if (len <= 0) return true;
                var sb = new StringBuilder(len + 1);
                GetWindowText(hwnd, sb, sb.Capacity);
                var title = sb.ToString();
                if (string.IsNullOrWhiteSpace(title)) return true;
                GetWindowThreadProcessId(hwnd, out var pid);
                list.Add(new WindowInfo(hwnd, (int)pid, title));
                return true;
            }, IntPtr.Zero);
            return list;
        }
    }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] private static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);

    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;
    private const uint MOUSEEVENTF_HWHEEL = 0x01000;

    [StructLayout(LayoutKind.Sequential)] private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
