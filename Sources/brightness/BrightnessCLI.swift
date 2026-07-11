//  BrightnessCLI.swift
//  brightness
//
//  Entry point and argument parsing. The grammar is small enough that a
//  hand-rolled parser keeps the package dependency-free (builds offline,
//  no swift-argument-parser fetch).

import DDCKit
import Foundation

@main
struct BrightnessCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            try await run(arguments: arguments)
        } catch let error as DDCError {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(2)
        } catch let error as UsageError {
            FileHandle.standardError.write(Data("error: \(error.message)\n\n".utf8))
            print(Self.usage)
            exit(64)  // EX_USAGE
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run(arguments: [String]) async throws {
        var (positional, displayID) = try parseOptions(arguments)

        guard !positional.isEmpty else {
            print(Self.usage)
            return
        }
        let command = positional.removeFirst()

        switch command {
        case "list":
            try await Commands.list()
        case "get":
            try await Commands.get(displayID: displayID)
        case "set":
            let value = try requiredValue(positional, name: "brightness value")
            try await Commands.set(value, displayID: displayID)
        case "up":
            let step = try optionalValue(positional) ?? 10
            try await Commands.adjust(by: step, displayID: displayID)
        case "down":
            let step = try optionalValue(positional) ?? 10
            try await Commands.adjust(by: -step, displayID: displayID)
        case "max":
            try await Commands.setToLimit(maximum: true, displayID: displayID)
        case "min":
            try await Commands.setToLimit(maximum: false, displayID: displayID)
        case "diagnose":
            try await Commands.diagnose()
        case "help", "--help", "-h":
            print(Self.usage)
        default:
            throw UsageError("unknown command '\(command)'")
        }
    }

    // MARK: - Parsing helpers

    private static func parseOptions(_ arguments: [String]) throws -> (positional: [String], displayID: Int?) {
        var positional: [String] = []
        var displayID: Int? = nil
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--display" || argument == "-d" {
                guard index + 1 < arguments.count, let id = Int(arguments[index + 1]) else {
                    throw UsageError("--display requires a numeric identifier")
                }
                displayID = id
                index += 2
            } else if argument.hasPrefix("--display=") {
                guard let id = Int(argument.dropFirst("--display=".count)) else {
                    throw UsageError("--display requires a numeric identifier")
                }
                displayID = id
                index += 1
            } else {
                positional.append(argument)
                index += 1
            }
        }
        return (positional, displayID)
    }

    private static func requiredValue(_ positional: [String], name: String) throws -> Int {
        guard let raw = positional.first else {
            throw UsageError("missing \(name)")
        }
        guard let value = Int(raw) else {
            throw UsageError("'\(raw)' is not a number")
        }
        return value
    }

    private static func optionalValue(_ positional: [String]) throws -> Int? {
        guard let raw = positional.first else { return nil }
        guard let value = Int(raw) else {
            throw UsageError("'\(raw)' is not a number")
        }
        return value
    }

    static let usage = """
        brightness — hardware backlight control for external displays (DDC/CI)

        USAGE:
          brightness <command> [value] [--display <id>]

        COMMANDS:
          get              Print the current hardware brightness
          set <0-100>      Set brightness to an absolute value
          up [step]        Raise brightness (default step: 10)
          down [step]      Lower brightness (default step: 10)
          max              Set brightness to the monitor's maximum
          min              Set brightness to the monitor's minimum
          list             List displays with identity and DDC status
          diagnose         Full DDC/CI diagnostic report with raw traffic
          help             Show this help

        OPTIONS:
          --display <id>   Target a specific display (see `brightness list`)

        EXAMPLES:
          brightness set 70
          brightness up 5 --display 2
        """
}

/// Thrown for malformed command lines; prints usage and exits EX_USAGE.
struct UsageError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
