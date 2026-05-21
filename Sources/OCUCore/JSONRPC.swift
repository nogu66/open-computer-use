//
//  JSONRPC.swift
//  OpenComputerUse / OCUCore
//
//  Tiny helpers for constructing JSON-RPC 2.0 responses used by the MCP
//  server loop. Kept platform-free so they can be unit tested in CI.
//

import Foundation

public enum JSONRPC {
    /// Build a JSON-RPC 2.0 response object.
    ///
    /// - Parameters:
    ///   - id: Request id. `nil` is allowed for notifications.
    ///   - result: Optional `result` payload.
    ///   - error: Optional `error` payload. Mutually exclusive with `result`.
    public static func response(id: Any?,
                                result: Any? = nil,
                                error: [String: Any]? = nil) -> [String: Any] {
        var obj: [String: Any] = ["jsonrpc": "2.0"]
        if let id = id { obj["id"] = id }
        if let r = result { obj["result"] = r }
        if let e = error { obj["error"] = e }
        return obj
    }

    /// Serialize a response object to a single line of UTF-8 data
    /// (newline appended), suitable for stdio framing.
    public static func encode(_ obj: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: obj, options: [])
        data.append(0x0A) // '\n'
        return data
    }

    /// Standard JSON-RPC 2.0 error codes that the MCP server may emit.
    public enum ErrorCode {
        public static let methodNotFound = -32601
        public static let invalidParams  = -32602
        public static let internalError  = -32603
    }
}

/// MCP `tools/call` content envelope.
public enum MCPContent {
    public static func text(_ s: String, isError: Bool = false) -> [String: Any] {
        var obj: [String: Any] = ["content": [["type": "text", "text": s]]]
        if isError { obj["isError"] = true }
        return obj
    }
}
