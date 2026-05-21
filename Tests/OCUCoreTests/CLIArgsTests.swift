//
//  CLIArgsTests.swift
//  OpenComputerUse / OCUCoreTests
//

import XCTest
@testable import OCUCore

final class CLIArgsTests: XCTestCase {

    func testEmpty() {
        let p = parseCLIArgs([])
        XCTAssertEqual(p, ParsedArgs())
    }

    func testPositionalOnly() {
        let p = parseCLIArgs(["apps"])
        XCTAssertEqual(p.positional, ["apps"])
        XCTAssertTrue(p.opts.isEmpty)
        XCTAssertTrue(p.flags.isEmpty)
    }

    func testKeyValuePair() {
        let p = parseCLIArgs(["--bundle-id", "com.google.Chrome"])
        XCTAssertEqual(p.opts["bundle-id"], "com.google.Chrome")
        XCTAssertTrue(p.flags.isEmpty)
    }

    func testFlagFollowedByFlag() {
        // `--json` followed by another --opt should remain a flag.
        let p = parseCLIArgs(["--json", "--query", "Search"])
        XCTAssertTrue(p.flags.contains("json"))
        XCTAssertEqual(p.opts["query"], "Search")
    }

    func testTrailingFlag() {
        // `--json` at end is a flag.
        let p = parseCLIArgs(["--json"])
        XCTAssertEqual(p.flags, ["json"])
    }

    func testMixed() {
        let p = parseCLIArgs([
            "tree",
            "--bundle-id", "com.apple.Safari",
            "--depth", "8",
            "--json"
        ])
        XCTAssertEqual(p.positional, ["tree"])
        XCTAssertEqual(p.opts["bundle-id"], "com.apple.Safari")
        XCTAssertEqual(p.opts["depth"], "8")
        XCTAssertTrue(p.flags.contains("json"))
    }

    func testMultiplePositionals() {
        let p = parseCLIArgs(["clip", "set", "--text", "hello"])
        XCTAssertEqual(p.positional, ["clip", "set"])
        XCTAssertEqual(p.opts["text"], "hello")
    }

    func testModifierAliases() {
        XCTAssertEqual(ModifierKey(alias: "cmd"),     .command)
        XCTAssertEqual(ModifierKey(alias: "command"), .command)
        XCTAssertEqual(ModifierKey(alias: "shift"),   .shift)
        XCTAssertEqual(ModifierKey(alias: "alt"),     .option)
        XCTAssertEqual(ModifierKey(alias: "option"),  .option)
        XCTAssertEqual(ModifierKey(alias: "CTRL"),    .control)
        XCTAssertNil(ModifierKey(alias: "hyper"))
    }

    func testParseModifiers() {
        XCTAssertEqual(parseModifiers("cmd,shift"), [.command, .shift])
        XCTAssertEqual(parseModifiers("alt"),       [.option])
        XCTAssertEqual(parseModifiers(""),          [])
        XCTAssertEqual(parseModifiers("cmd,bogus"), [.command])
    }
}
