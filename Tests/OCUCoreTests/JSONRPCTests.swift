//
//  JSONRPCTests.swift
//  OpenComputerUse / OCUCoreTests
//

import XCTest
@testable import OCUCore

final class JSONRPCTests: XCTestCase {

    func testResponseWithResult() throws {
        let obj = JSONRPC.response(id: 7, result: ["ok": true])
        XCTAssertEqual(obj["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(obj["id"] as? Int, 7)
        let result = obj["result"] as? [String: Any]
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertNil(obj["error"])
    }

    func testResponseWithError() {
        let obj = JSONRPC.response(
            id: 3,
            error: ["code": JSONRPC.ErrorCode.methodNotFound, "message": "x"]
        )
        XCTAssertEqual(obj["id"] as? Int, 3)
        XCTAssertNil(obj["result"])
        XCTAssertNotNil(obj["error"])
    }

    func testResponseWithoutId() {
        let obj = JSONRPC.response(id: nil, result: [:])
        XCTAssertNil(obj["id"])
    }

    func testEncodeAppendsNewline() throws {
        let data = try JSONRPC.encode(["jsonrpc": "2.0", "id": 1])
        XCTAssertEqual(data.last, 0x0A)
        let body = String(data: data.dropLast(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("\"jsonrpc\""))
    }

    func testMCPTextContent() {
        let obj = MCPContent.text("hello")
        let content = obj["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertEqual(content?.first?["text"] as? String, "hello")
        XCTAssertNil(obj["isError"])
    }

    func testMCPTextErrorContent() {
        let obj = MCPContent.text("nope", isError: true)
        XCTAssertEqual(obj["isError"] as? Bool, true)
    }
}
