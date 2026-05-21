//
//  VersionTests.swift
//  OpenComputerUse / OCUCoreTests
//

import XCTest
@testable import OCUCore

final class VersionTests: XCTestCase {

    func testVersionLooksSemver() {
        let v = OpenComputerUse.version
        let parts = v.split(separator: ".")
        XCTAssertEqual(parts.count, 3, "version '\(v)' must be MAJOR.MINOR.PATCH")
        for p in parts {
            XCTAssertNotNil(Int(p), "version part '\(p)' must be an integer")
        }
    }

    func testServerNameNotEmpty() {
        XCTAssertFalse(OpenComputerUse.serverName.isEmpty)
    }
}
