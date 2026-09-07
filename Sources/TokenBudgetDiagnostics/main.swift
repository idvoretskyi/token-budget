import Foundation
import UsageAdapters
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let arguments = CommandLine.arguments
guard arguments.count == 3, ["opencode", "codex"].contains(arguments[1]) else {
    print("Usage: token-budget-diagnostics opencode|codex PATH")
    exit(2)
}

do {
    let report = try arguments[1] == "opencode"
        ? OpenCodeImporter.scan(path: arguments[2])
        : CodexImporter.scan(path: arguments[2])
    print("Scanned records: \(report.scannedRecords)")
    print("Usage events: \(report.events.count)")
    print("Warnings: \(report.warnings.count)")
    for warning in report.warnings { print(warning) }
} catch {
    // Never interpolate an error, argument, event, provider, model, or source record.
    print("The usage source could not be scanned safely. Check source availability and compatibility.")
    exit(1)
}
