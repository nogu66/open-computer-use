//
//  CLIArgs.swift
//  OpenComputerUse / OCUCore
//
//  Pure-Foundation argument parsing for the `ocu` CLI. Kept in a library
//  target so it can be unit tested independently of the executable.
//

import Foundation

public struct ParsedArgs: Equatable {
    public var positional: [String]
    public var opts: [String: String]
    public var flags: Set<String>

    public init(positional: [String] = [],
                opts: [String: String] = [:],
                flags: Set<String> = []) {
        self.positional = positional
        self.opts = opts
        self.flags = flags
    }
}

/// Lightweight `--key value` / `--flag` parser.
///
/// Rules:
/// * `--key value` becomes `opts["key"] = "value"` when the following token
///   does not itself start with `--`.
/// * Otherwise `--key` becomes a flag.
/// * Tokens that do not start with `--` are returned as `positional`.
public func parseCLIArgs(_ args: [String]) -> ParsedArgs {
    var positional: [String] = []
    var opts: [String: String] = [:]
    var flags: Set<String> = []
    var i = 0
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                opts[key] = args[i + 1]
                i += 2
            } else {
                flags.insert(key)
                i += 1
            }
        } else {
            positional.append(a)
            i += 1
        }
    }
    return ParsedArgs(positional: positional, opts: opts, flags: flags)
}

/// Modifier-key string normalization. Accepts common aliases.
public enum ModifierKey: String, CaseIterable, Equatable {
    case command, shift, option, control

    public init?(alias: String) {
        switch alias.lowercased() {
        case "cmd", "command": self = .command
        case "shift":           self = .shift
        case "alt", "option":   self = .option
        case "ctrl", "control": self = .control
        default:                return nil
        }
    }
}

/// Parse a comma-separated modifier list (e.g. "cmd,shift").
public func parseModifiers(_ s: String) -> [ModifierKey] {
    return s.split(separator: ",").compactMap { ModifierKey(alias: String($0)) }
}
