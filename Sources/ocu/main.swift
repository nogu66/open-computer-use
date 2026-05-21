//
//  ocu — OpenComputerUse
//  https://github.com/nogu66/OpenComputerUse
//
//  Acts as either:
//    * an MCP stdio server (no args, or `ocu serve`), or
//    * a regular CLI (`ocu <subcommand>`).
//
//  Implements macOS computer use via:
//    * Accessibility API (AXUIElement)  — read UI tree, press actions
//    * CoreGraphics events (CGEvent)    — synthesize mouse / keyboard
//    * screencapture(1)                  — screenshots
//

import Foundation
import ApplicationServices
import AppKit
import OCUCore

// stdout は MCP JSON-RPC 専用。ログは stderr へ
func log(_ s: String) {
    FileHandle.standardError.write("[ocu] \(s)\n".data(using: .utf8)!)
}

// ====================== AX helpers ======================

func axAttr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}

func axRole(_ e: AXUIElement) -> String {
    return (axAttr(e, kAXRoleDescriptionAttribute as String) as? String)
        ?? (axAttr(e, kAXRoleAttribute as String) as? String) ?? "?"
}

func axString(_ e: AXUIElement, _ k: String) -> String? {
    if let s = axAttr(e, k) as? String, !s.isEmpty { return s }
    return nil
}

func enableEnhanced(_ axApp: AXUIElement) {
    AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue!)
    AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue!)
}

func findApp(_ bundleId: String) -> NSRunningApplication? {
    return NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleId }
}

func focusedWindow(of axApp: AXUIElement) -> AXUIElement {
    if let f = axAttr(axApp, kAXFocusedWindowAttribute as String), CFGetTypeID(f) == AXUIElementGetTypeID() {
        return f as! AXUIElement
    }
    if let m = axAttr(axApp, kAXMainWindowAttribute as String), CFGetTypeID(m) == AXUIElementGetTypeID() {
        return m as! AXUIElement
    }
    return axApp
}

func describe(_ e: AXUIElement) -> String {
    var parts = [axRole(e)]
    if let s = axString(e, kAXTitleAttribute as String) { parts.append("\"\(short(s))\"") }
    if let s = axString(e, kAXDescriptionAttribute as String) { parts.append("Description: \(short(s))") }
    if let v = axAttr(e, kAXValueAttribute as String) {
        let s = (v as? String) ?? (v as? NSNumber).map { $0.stringValue } ?? ""
        if !s.isEmpty { parts.append("Value: \(short(s))") }
    }
    if let s = axString(e, kAXHelpAttribute as String) { parts.append("Help: \(short(s))") }
    return parts.joined(separator: " ")
}

func short(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.count > 120 ? String(t.prefix(120)) + "..." : t
}

var refMap: [Int: AXUIElement] = [:]

func walkText(_ e: AXUIElement, maxDepth: Int, depth: Int = 0, counter: inout Int, out: inout String) {
    counter += 1
    refMap[counter] = e
    out += String(repeating: "  ", count: depth) + "@e\(counter) \(describe(e))\n"
    if depth >= maxDepth { return }
    if let cs = axAttr(e, kAXChildrenAttribute as String) as? [AXUIElement] {
        for c in cs { walkText(c, maxDepth: maxDepth, depth: depth + 1, counter: &counter, out: &out) }
    }
}

func matches(_ e: AXUIElement, _ q: String) -> Bool {
    for k in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXHelpAttribute,
              kAXRoleDescriptionAttribute, kAXRoleAttribute, kAXIdentifierAttribute] {
        if let s = axAttr(e, k as String) as? String, s.contains(q) { return true }
    }
    return false
}

func find(_ e: AXUIElement, _ q: String, depth: Int = 0) -> AXUIElement? {
    if depth > 30 { return nil }
    if matches(e, q) { return e }
    if let cs = axAttr(e, kAXChildrenAttribute as String) as? [AXUIElement] {
        for c in cs { if let h = find(c, q, depth: depth + 1) { return h } }
    }
    return nil
}

func elementCenter(_ e: AXUIElement) -> CGPoint? {
    guard let pos = axAttr(e, kAXPositionAttribute as String),
          let size = axAttr(e, kAXSizeAttribute as String) else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
}

// ====================== Permission helpers ======================

/// Returns nil if Accessibility permission OK, otherwise an error message.
func checkAxPermission() -> String? {
    if !AXIsProcessTrusted() {
        return """
        Accessibility permission not granted.
        Open System Settings → Privacy & Security → Accessibility and enable the parent process \
        (Terminal/Ghostty/Claude Code/Cursor — whichever launches ocu).
        """
    }
    return nil
}

// ====================== CGEvent helpers ======================

let evtSrc = CGEventSource(stateID: .hidSystemState)

func sendClick(_ pt: CGPoint) {
    CGEvent(mouseEventSource: evtSrc, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: evtSrc, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: evtSrc, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func sendRightClick(_ pt: CGPoint) {
    CGEvent(mouseEventSource: evtSrc, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .right)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: evtSrc, mouseType: .rightMouseDown, mouseCursorPosition: pt, mouseButton: .right)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: evtSrc, mouseType: .rightMouseUp, mouseCursorPosition: pt, mouseButton: .right)?.post(tap: .cghidEventTap)
}

func sendScroll(dx: Int32, dy: Int32, at: CGPoint? = nil) {
    if let pt = at {
        CGEvent(mouseEventSource: evtSrc, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    if let evt = CGEvent(scrollWheelEvent2Source: evtSrc, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
        evt.post(tap: .cghidEventTap)
    }
}

func sendType(_ text: String) {
    for ch in text.unicodeScalars {
        var u = UniChar(ch.value)
        let d = CGEvent(keyboardEventSource: evtSrc, virtualKey: 0, keyDown: true)
        d?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        d?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: evtSrc, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &u)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
    }
}

let keyMap: [String: CGKeyCode] = [
    "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
    "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
    "k": 40, "n": 45, "m": 46
]

func sendKey(_ name: String, flags: CGEventFlags) -> Bool {
    guard let code = keyMap[name.lowercased()] else { return false }
    let d = CGEvent(keyboardEventSource: evtSrc, virtualKey: code, keyDown: true); d?.flags = flags; d?.post(tap: .cghidEventTap)
    let u = CGEvent(keyboardEventSource: evtSrc, virtualKey: code, keyDown: false); u?.flags = flags; u?.post(tap: .cghidEventTap)
    return true
}

func parseFlags(_ mods: [String]) -> CGEventFlags {
    var f: CGEventFlags = []
    for m in mods {
        switch m.lowercased() {
        case "cmd", "command": f.insert(.maskCommand)
        case "shift": f.insert(.maskShift)
        case "alt", "option": f.insert(.maskAlternate)
        case "ctrl", "control": f.insert(.maskControl)
        default: break
        }
    }
    return f
}

// ====================== Tool implementations ======================

enum ToolError: Error { case bad(String) }

func toolResult(_ text: String) -> [String: Any] {
    return ["content": [["type": "text", "text": text]]]
}

func toolError(_ msg: String) -> [String: Any] {
    return ["content": [["type": "text", "text": msg]], "isError": true]
}

func t_listApps() -> [String: Any] {
    let apps = NSWorkspace.shared.runningApplications.compactMap { app -> String? in
        guard app.activationPolicy == .regular, let bid = app.bundleIdentifier else { return nil }
        return "\(app.localizedName ?? "?")\t\(bid)\tPID=\(app.processIdentifier)"
    }
    return toolResult(apps.joined(separator: "\n"))
}

func t_axTree(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String else { return toolError("bundle_id required") }
    if let e = checkAxPermission() { return toolError(e) }
    let maxDepth = (args["max_depth"] as? Int) ?? 12
    let scope = (args["scope"] as? String) ?? "window"
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    Thread.sleep(forTimeInterval: 0.2)
    let target = scope == "app" ? axApp : focusedWindow(of: axApp)
    refMap.removeAll()
    var counter = 0
    var out = ""
    walkText(target, maxDepth: maxDepth, counter: &counter, out: &out)
    return toolResult(out)
}

func t_clickRef(_ args: [String: Any]) -> [String: Any] {
    guard let ref = args["ref"] as? Int else { return toolError("ref (int) required") }
    guard let e = refMap[ref] else { return toolError("ref @e\(ref) not in map. call get_ax_tree first") }
    var actions: CFArray?
    AXUIElementCopyActionNames(e, &actions)
    if let arr = actions as? [String], arr.contains(kAXPressAction as String) {
        let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
        return toolResult(err == .success ? "AXPress @e\(ref) ok" : "AXPress @e\(ref) failed: \(err.rawValue)")
    }
    guard let pt = elementCenter(e) else { return toolError("@e\(ref): no action and no geometry") }
    sendClick(pt)
    return toolResult("clicked @e\(ref) at (\(pt.x),\(pt.y))")
}

func t_screenshot(_ args: [String: Any]) -> [String: Any] {
    let dir = NSTemporaryDirectory()
    let path = "\(dir)ocu-\(Int(Date().timeIntervalSince1970)).png"
    var procArgs = ["-x"]
    if let bid = args["bundle_id"] as? String, let app = findApp(bid) {
        procArgs.append(contentsOf: ["-l", "\(windowIdFor(pid: app.processIdentifier) ?? 0)"])
    }
    procArgs.append(path)
    let p = Process()
    p.launchPath = "/usr/sbin/screencapture"
    p.arguments = procArgs
    do { try p.run(); p.waitUntilExit() } catch { return toolError("screencapture failed: \(error)") }
    guard p.terminationStatus == 0, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        return toolError("screencapture exit=\(p.terminationStatus) path=\(path)")
    }
    if (args["return"] as? String) == "base64" {
        return ["content": [["type": "image", "data": data.base64EncodedString(), "mimeType": "image/png"]]]
    }
    return toolResult(path)
}

func windowIdFor(pid: pid_t) -> CGWindowID? {
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for w in info {
        if let p = w[kCGWindowOwnerPID as String] as? pid_t, p == pid,
           let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
           let id = w[kCGWindowNumber as String] as? CGWindowID {
            return id
        }
    }
    return nil
}

func t_findElement(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String, let q = args["query"] as? String else {
        return toolError("bundle_id and query required")
    }
    if let e = checkAxPermission() { return toolError(e) }
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    Thread.sleep(forTimeInterval: 0.2)
    guard let hit = find(axApp, q) else { return toolError("not found: \(q)") }
    var info = "role=\((axAttr(hit, kAXRoleAttribute as String) as? String) ?? "?")"
    if let d = axString(hit, kAXDescriptionAttribute as String) { info += " desc=\(d)" }
    if let t = axString(hit, kAXTitleAttribute as String) { info += " title=\(t)" }
    if let c = elementCenter(hit) { info += " center=(\(c.x),\(c.y))" }
    var actions: CFArray?
    AXUIElementCopyActionNames(hit, &actions)
    if let arr = actions as? [String] { info += " actions=\(arr)" }
    return toolResult(info)
}

func t_clickElement(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String, let q = args["query"] as? String else {
        return toolError("bundle_id and query required")
    }
    if let e = checkAxPermission() { return toolError(e) }
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    Thread.sleep(forTimeInterval: 0.2)
    guard let hit = find(axApp, q) else { return toolError("not found: \(q)") }
    var actions: CFArray?
    AXUIElementCopyActionNames(hit, &actions)
    if let arr = actions as? [String], arr.contains(kAXPressAction as String) {
        let err = AXUIElementPerformAction(hit, kAXPressAction as CFString)
        return toolResult(err == .success ? "AXPress ok" : "AXPress failed: \(err.rawValue)")
    }
    guard let pt = elementCenter(hit) else { return toolError("no action, no geometry") }
    sendClick(pt)
    return toolResult("clicked at (\(pt.x),\(pt.y))")
}

func t_typeText(_ args: [String: Any]) -> [String: Any] {
    guard let text = args["text"] as? String else { return toolError("text required") }
    sendType(text)
    return toolResult("typed \(text.count) chars")
}

func t_keyPress(_ args: [String: Any]) -> [String: Any] {
    guard let key = args["key"] as? String else { return toolError("key required") }
    let mods = (args["modifiers"] as? [String]) ?? []
    let ok = sendKey(key, flags: parseFlags(mods))
    return ok ? toolResult("key \(key) sent") : toolError("unknown key: \(key)")
}

func t_activate(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String else { return toolError("bundle_id required") }
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let ok = app.activate(options: [.activateIgnoringOtherApps])
    Thread.sleep(forTimeInterval: 0.3)
    return ok ? toolResult("activated \(bid)") : toolError("failed to activate \(bid)")
}

func t_wait(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String, let q = args["query"] as? String else {
        return toolError("bundle_id and query required")
    }
    if let e = checkAxPermission() { return toolError(e) }
    let timeout = (args["timeout"] as? Double) ?? 10.0
    let interval = 0.3
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if find(axApp, q) != nil {
            let elapsed = Date().timeIntervalSince(start)
            return toolResult(String(format: "found after %.2fs", elapsed))
        }
        Thread.sleep(forTimeInterval: interval)
    }
    return toolError("timeout after \(timeout)s waiting for: \(q)")
}

func t_scroll(_ args: [String: Any]) -> [String: Any] {
    let dx = Int32((args["dx"] as? Int) ?? 0)
    let dy = Int32((args["dy"] as? Int) ?? 0)
    if dx == 0 && dy == 0 { return toolError("dx and/or dy required (non-zero)") }
    if let bid = args["bundle_id"] as? String, let q = args["query"] as? String {
        if let e = checkAxPermission() { return toolError(e) }
        guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        enableEnhanced(axApp)
        guard let hit = find(axApp, q), let pt = elementCenter(hit) else {
            return toolError("not found: \(q)")
        }
        sendScroll(dx: dx, dy: dy, at: pt)
        return toolResult("scrolled dx=\(dx) dy=\(dy) over (\(pt.x),\(pt.y))")
    }
    sendScroll(dx: dx, dy: dy)
    return toolResult("scrolled dx=\(dx) dy=\(dy) at cursor")
}

func t_rightClick(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String, let q = args["query"] as? String else {
        return toolError("bundle_id and query required")
    }
    if let e = checkAxPermission() { return toolError(e) }
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    guard let hit = find(axApp, q), let pt = elementCenter(hit) else {
        return toolError("not found: \(q)")
    }
    sendRightClick(pt)
    return toolResult("right-clicked at (\(pt.x),\(pt.y))")
}

func t_clipGet(_ args: [String: Any]) -> [String: Any] {
    let pb = NSPasteboard.general
    if let s = pb.string(forType: .string) { return toolResult(s) }
    return toolError("clipboard empty or not text")
}

func t_clipSet(_ args: [String: Any]) -> [String: Any] {
    guard let text = args["text"] as? String else { return toolError("text required") }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    return toolResult("set clipboard: \(text.count) chars")
}

func t_menu(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String, let path = args["path"] as? String else {
        return toolError("bundle_id and path required (e.g. 'File/Open')")
    }
    if let e = checkAxPermission() { return toolError(e) }
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    guard let menuBarRef = axAttr(axApp, kAXMenuBarAttribute as String) else {
        return toolError("no menu bar for \(bid)")
    }
    let parts = path.split(separator: "/").map { String($0) }
    if parts.isEmpty { return toolError("empty path") }
    var current = menuBarRef as! AXUIElement
    for (i, part) in parts.enumerated() {
        guard let children = axAttr(current, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return toolError("no children at depth \(i): \(part)")
        }
        guard let next = children.first(where: { (axString($0, kAXTitleAttribute as String) ?? "") == part }) else {
            let titles = children.compactMap { axString($0, kAXTitleAttribute as String) }
            return toolError("menu item not found: '\(part)' (available: \(titles.joined(separator: ", ")))")
        }
        if i == parts.count - 1 {
            let err = AXUIElementPerformAction(next, kAXPressAction as CFString)
            return err == .success ? toolResult("pressed menu: \(path)") : toolError("AXPress failed: \(err.rawValue)")
        }
        if let submenu = (axAttr(next, kAXChildrenAttribute as String) as? [AXUIElement])?.first {
            current = submenu
        } else {
            return toolError("no submenu under: \(part)")
        }
    }
    return toolError("unreachable")
}

// JSON 出力用に AX tree を構造化 dict として作る
func walkJson(_ e: AXUIElement, maxDepth: Int, depth: Int = 0, counter: inout Int) -> [String: Any] {
    counter += 1
    let myRef = counter
    refMap[myRef] = e
    var node: [String: Any] = [
        "ref": myRef,
        "role": axRole(e)
    ]
    if let s = axString(e, kAXTitleAttribute as String) { node["title"] = s }
    if let s = axString(e, kAXDescriptionAttribute as String) { node["description"] = s }
    if let v = axAttr(e, kAXValueAttribute as String) {
        if let s = v as? String { node["value"] = s }
        else if let n = v as? NSNumber { node["value"] = n.stringValue }
    }
    if let s = axString(e, kAXHelpAttribute as String) { node["help"] = s }
    if depth < maxDepth, let cs = axAttr(e, kAXChildrenAttribute as String) as? [AXUIElement] {
        var arr: [[String: Any]] = []
        for c in cs {
            arr.append(walkJson(c, maxDepth: maxDepth, depth: depth + 1, counter: &counter))
        }
        if !arr.isEmpty { node["children"] = arr }
    }
    return node
}

func t_axTreeJson(_ args: [String: Any]) -> [String: Any] {
    guard let bid = args["bundle_id"] as? String else { return toolError("bundle_id required") }
    if let e = checkAxPermission() { return toolError(e) }
    let maxDepth = (args["max_depth"] as? Int) ?? 12
    let scope = (args["scope"] as? String) ?? "window"
    guard let app = findApp(bid) else { return toolError("not running: \(bid)") }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    enableEnhanced(axApp)
    Thread.sleep(forTimeInterval: 0.2)
    let target = scope == "app" ? axApp : focusedWindow(of: axApp)
    refMap.removeAll()
    var counter = 0
    let root = walkJson(target, maxDepth: maxDepth, counter: &counter)
    if let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]),
       let s = String(data: data, encoding: .utf8) {
        return toolResult(s)
    }
    return toolError("JSON serialization failed")
}

// ====================== Tool registry ======================

let toolsList: [[String: Any]] = [
    [
        "name": "list_apps",
        "description": "List running macOS GUI applications with bundle IDs and PIDs",
        "inputSchema": ["type": "object", "properties": [:]]
    ],
    [
        "name": "get_ax_tree",
        "description": "Get the accessibility tree of a running app's focused window (or whole app). Returns numbered text tree. Use this to understand what UI is visible before clicking anything.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string", "description": "e.g. com.google.Chrome"],
                "max_depth": ["type": "integer", "default": 12],
                "scope": ["type": "string", "enum": ["window", "app"], "default": "window"]
            ],
            "required": ["bundle_id"]
        ]
    ],
    [
        "name": "find_element",
        "description": "Find first AX element in app matching query (substring in description/title/value/help). Returns role, geometry, available actions.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "query": ["type": "string"]
            ],
            "required": ["bundle_id", "query"]
        ]
    ],
    [
        "name": "click_element",
        "description": "Find element by query and click it (AXPress if available, else CGEvent click at center)",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "query": ["type": "string"]
            ],
            "required": ["bundle_id", "query"]
        ]
    ],
    [
        "name": "type_text",
        "description": "Type Unicode text into the currently focused field (uses CGEvent)",
        "inputSchema": [
            "type": "object",
            "properties": ["text": ["type": "string"]],
            "required": ["text"]
        ]
    ],
    [
        "name": "key_press",
        "description": "Send a single key, optionally with modifiers. Example: key=t modifiers=[cmd] for Cmd+T",
        "inputSchema": [
            "type": "object",
            "properties": [
                "key": ["type": "string", "description": "return/tab/space/escape/letter/digit/arrow"],
                "modifiers": ["type": "array", "items": ["type": "string"]]
            ],
            "required": ["key"]
        ]
    ],
    [
        "name": "click_ref",
        "description": "Click an element by its @e ref number from the last get_ax_tree call. Refs are invalidated when get_ax_tree is called again.",
        "inputSchema": [
            "type": "object",
            "properties": ["ref": ["type": "integer", "description": "the N in @eN"]],
            "required": ["ref"]
        ]
    ],
    [
        "name": "screenshot",
        "description": "Capture a screenshot. If bundle_id is given, captures that app's main window; otherwise full screen. Returns file path by default, or base64 image when return=base64.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "return": ["type": "string", "enum": ["path", "base64"], "default": "path"]
            ]
        ]
    ],
    [
        "name": "activate",
        "description": "Bring an app to foreground. Crucial before sending keystrokes — call this first to avoid leaking input into other apps.",
        "inputSchema": [
            "type": "object",
            "properties": ["bundle_id": ["type": "string"]],
            "required": ["bundle_id"]
        ]
    ],
    [
        "name": "wait_for",
        "description": "Poll for an AX element matching query until it appears or timeout (default 10s). Use to bridge async loads.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "query": ["type": "string"],
                "timeout": ["type": "number", "default": 10]
            ],
            "required": ["bundle_id", "query"]
        ]
    ],
    [
        "name": "scroll",
        "description": "Send scroll wheel event. With bundle_id+query, scrolls over that element; otherwise at current cursor position.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "query": ["type": "string"],
                "dx": ["type": "integer", "default": 0],
                "dy": ["type": "integer", "default": 0, "description": "Negative = scroll down in content"]
            ]
        ]
    ],
    [
        "name": "right_click",
        "description": "Right-click an element matching query (opens context menu)",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "query": ["type": "string"]
            ],
            "required": ["bundle_id", "query"]
        ]
    ],
    [
        "name": "clip_get",
        "description": "Read clipboard text",
        "inputSchema": ["type": "object", "properties": [:]]
    ],
    [
        "name": "clip_set",
        "description": "Write clipboard text (replaces current content)",
        "inputSchema": [
            "type": "object",
            "properties": ["text": ["type": "string"]],
            "required": ["text"]
        ]
    ],
    [
        "name": "menu",
        "description": "Press a menubar item by path (e.g. 'File/Open Recent/Project.txt')",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "path": ["type": "string", "description": "Slash-separated menu path"]
            ],
            "required": ["bundle_id", "path"]
        ]
    ],
    [
        "name": "ax_tree_json",
        "description": "Like get_ax_tree but returns JSON tree (ref/role/title/description/value/help/children)",
        "inputSchema": [
            "type": "object",
            "properties": [
                "bundle_id": ["type": "string"],
                "max_depth": ["type": "integer", "default": 12],
                "scope": ["type": "string", "enum": ["window", "app"], "default": "window"]
            ],
            "required": ["bundle_id"]
        ]
    ]
]

func handleTool(_ name: String, _ args: [String: Any]) -> [String: Any] {
    switch name {
    case "list_apps":     return t_listApps()
    case "get_ax_tree":   return t_axTree(args)
    case "find_element":  return t_findElement(args)
    case "click_element": return t_clickElement(args)
    case "type_text":     return t_typeText(args)
    case "key_press":     return t_keyPress(args)
    case "click_ref":     return t_clickRef(args)
    case "screenshot":    return t_screenshot(args)
    case "activate":      return t_activate(args)
    case "wait_for":      return t_wait(args)
    case "scroll":        return t_scroll(args)
    case "right_click":   return t_rightClick(args)
    case "clip_get":      return t_clipGet(args)
    case "clip_set":      return t_clipSet(args)
    case "menu":          return t_menu(args)
    case "ax_tree_json":  return t_axTreeJson(args)
    default:              return toolError("unknown tool: \(name)")
    }
}

// ====================== CLI mode ======================

func cliExtractText(_ result: [String: Any]) -> String {
    if let content = result["content"] as? [[String: Any]] {
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
    return ""
}

func cliIsError(_ result: [String: Any]) -> Bool {
    return (result["isError"] as? Bool) ?? false
}

// CLI argument parsing lives in OCUCore so it can be unit tested without
// touching ApplicationServices / AppKit. See Sources/OCUCore/CLIArgs.swift.
func cliParseArgs(_ args: [String]) -> (positional: [String], opts: [String: String], flags: Set<String>) {
    let parsed = parseCLIArgs(args)
    return (parsed.positional, parsed.opts, parsed.flags)
}

func cliPrintHelp() {
    let help = """
    OpenComputerUse (ocu) v\(OpenComputerUse.version) — macOS computer use
    via Accessibility + CGEvent. https://github.com/nogu66/OpenComputerUse

    USAGE:
      ocu <subcommand> [options]
      ocu serve                              # MCP stdio server mode
      ocu --version                          # Print version

    SUBCOMMANDS:
      apps                                   List running GUI apps (name, bundle_id, pid)
      activate --bundle-id <id>              Bring app to foreground (call this first!)
      tree   --bundle-id <id> [--depth N] [--scope window|app]
                                             Dump numbered AX tree (text or --json)
      find   --bundle-id <id> --query <q>    Locate first AX element matching query
      wait   --bundle-id <id> --query <q> [--timeout SEC]
                                             Poll until element appears (default 10s)
      click  --bundle-id <id> --query <q>    Left-click first element matching query
      rclick --bundle-id <id> --query <q>    Right-click first element matching query
      type   --text <s>                      Type text into focused field
      key    --key <name> [--mods cmd,shift,alt,ctrl]
                                             Send a single key (optionally with modifiers)
      scroll [--bundle-id <id> --query <q>] [--dx N] [--dy N]
                                             Send scroll wheel (over element or cursor)
      menu   --bundle-id <id> --path <p>     Press menubar item by path (e.g. 'File/Open')
      shot   [--bundle-id <id>] [--out <path>]
                                             Capture screenshot (default: /tmp/...png)
      clip get                               Read clipboard text
      clip set --text <s>                    Write clipboard text

    GLOBAL FLAGS:
      --json                                 Emit JSON output instead of plain text
      --help, -h                             Show this help

    EXAMPLES:
      ocu activate --bundle-id com.google.Chrome
      ocu key --key l --mods cmd                                 # Cmd+L → focus URL bar
      ocu type --text "https://example.com"
      ocu key --key return
      ocu wait --bundle-id com.google.Chrome --query "Example Domain" --timeout 5
      ocu tree --bundle-id com.google.Chrome --depth 8 --json | jq .
      ocu scroll --dy -300
      ocu menu --bundle-id com.google.Chrome --path "ファイル/新規タブ"
      ocu clip set --text "hello"
      ocu clip get
    """
    print(help)
}

/// 結果を CLI に出力。--json なら JSON、それ以外なら text。エラーなら exit(1)。
func cliEmit(_ result: [String: Any], json: Bool) -> Never {
    let isError = cliIsError(result)
    if json {
        var out: [String: Any] = ["ok": !isError]
        out["text"] = cliExtractText(result)
        if isError { out["error"] = cliExtractText(result) }
        if let data = try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    } else {
        let text = cliExtractText(result)
        if isError {
            FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
        } else {
            print(text)
        }
    }
    exit(isError ? 1 : 0)
}

func cliMain(_ argv: [String]) -> Never {
    guard let sub = argv.first else { cliPrintHelp(); exit(0) }
    if sub == "--help" || sub == "-h" || sub == "help" { cliPrintHelp(); exit(0) }
    if sub == "--version" || sub == "-v" || sub == "version" {
        print("ocu \(OpenComputerUse.version)")
        exit(0)
    }

    let (positional, opts, flags) = cliParseArgs(Array(argv.dropFirst()))
    let json = flags.contains("json")

    var toolArgs: [String: Any] = [:]
    if let v = opts["bundle-id"] { toolArgs["bundle_id"] = v }
    if let v = opts["query"]     { toolArgs["query"] = v }
    if let v = opts["text"]      { toolArgs["text"] = v }
    if let v = opts["key"]       { toolArgs["key"] = v }
    if let v = opts["scope"]     { toolArgs["scope"] = v }
    if let v = opts["path"]      { toolArgs["path"] = v }
    if let v = opts["depth"], let n = Int(v) { toolArgs["max_depth"] = n }
    if let v = opts["ref"], let n = Int(v) { toolArgs["ref"] = n }
    if let v = opts["dx"], let n = Int(v) { toolArgs["dx"] = n }
    if let v = opts["dy"], let n = Int(v) { toolArgs["dy"] = n }
    if let v = opts["timeout"], let d = Double(v) { toolArgs["timeout"] = d }
    if let v = opts["mods"] {
        toolArgs["modifiers"] = v.split(separator: ",").map { String($0) }
    }

    switch sub {
    case "apps":
        cliEmit(t_listApps(), json: json)
    case "activate":
        cliEmit(t_activate(toolArgs), json: json)
    case "tree":
        if json {
            cliEmit(t_axTreeJson(toolArgs), json: false) // already JSON in body
        } else {
            cliEmit(t_axTree(toolArgs), json: false)
        }
    case "find":
        cliEmit(t_findElement(toolArgs), json: json)
    case "wait":
        cliEmit(t_wait(toolArgs), json: json)
    case "click":
        cliEmit(t_clickElement(toolArgs), json: json)
    case "rclick":
        cliEmit(t_rightClick(toolArgs), json: json)
    case "type":
        cliEmit(t_typeText(toolArgs), json: json)
    case "key":
        cliEmit(t_keyPress(toolArgs), json: json)
    case "scroll":
        cliEmit(t_scroll(toolArgs), json: json)
    case "menu":
        cliEmit(t_menu(toolArgs), json: json)
    case "clip":
        let action = positional.first ?? ""
        switch action {
        case "get": cliEmit(t_clipGet([:]), json: json)
        case "set": cliEmit(t_clipSet(toolArgs), json: json)
        default:
            FileHandle.standardError.write("clip needs 'get' or 'set'\n".data(using: .utf8)!)
            exit(2)
        }
    case "shot":
        if let outPath = opts["out"] {
            // --out が指定された場合は screencapture を直接呼ぶ
            var procArgs = ["-x"]
            if let bid = opts["bundle-id"], let app = findApp(bid),
               let wid = windowIdFor(pid: app.processIdentifier) {
                procArgs.append(contentsOf: ["-l", "\(wid)"])
            }
            procArgs.append(outPath)
            let p = Process()
            p.launchPath = "/usr/sbin/screencapture"
            p.arguments = procArgs
            do { try p.run(); p.waitUntilExit() } catch {
                cliEmit(toolError("screencapture failed: \(error)"), json: json)
            }
            if p.terminationStatus == 0 {
                cliEmit(toolResult(outPath), json: json)
            } else {
                cliEmit(toolError("screencapture exit=\(p.terminationStatus)"), json: json)
            }
        } else {
            cliEmit(t_screenshot(toolArgs), json: json)
        }
    default:
        FileHandle.standardError.write("unknown subcommand: \(sub)\n".data(using: .utf8)!)
        cliPrintHelp()
        exit(2)
    }
}

// ====================== JSON-RPC loop ======================

func respond(_ id: Any?, result: Any? = nil, error: [String: Any]? = nil) {
    var obj: [String: Any] = ["jsonrpc": "2.0"]
    if let id = id { obj["id"] = id }
    if let r = result { obj["result"] = r }
    if let e = error { obj["error"] = e }
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

// エントリポイント分岐: 引数があれば CLI モード、無いか `serve` なら MCP モード
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let first = cliArgs.first, first != "serve" {
    cliMain(cliArgs)
}

let promptOpts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
if !AXIsProcessTrustedWithOptions(promptOpts) {
    log("Accessibility 権限が必要")
}

log("OpenComputerUse MCP server started (stdio) v\(OpenComputerUse.version)")

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        continue
    }
    let method = msg["method"] as? String ?? ""
    let id = msg["id"]
    let params = msg["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        respond(id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": OpenComputerUse.serverName,
                "version": OpenComputerUse.version
            ]
        ])
    case "notifications/initialized":
        continue
    case "tools/list":
        respond(id, result: ["tools": toolsList])
    case "tools/call":
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        respond(id, result: handleTool(name, args))
    case "ping":
        respond(id, result: [String: Any]())
    default:
        if id != nil {
            respond(id, error: ["code": -32601, "message": "method not found: \(method)"])
        }
    }
}
