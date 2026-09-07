import Foundation
import CoreFoundation
import BudgetCore

/// Errors intentionally carry no filesystem paths or upstream record contents.
public enum UsageImportError: Error, Sendable, LocalizedError {
    case unavailable, unsupported, database

    public var errorDescription: String? {
        switch self {
        case .unavailable: "The usage source is missing, inaccessible, or not a regular file or directory."
        case .unsupported: "The usage source schema is unsupported."
        case .database: "The usage database could not be read safely."
        }
    }
}

enum ScanLimit {
    static let lineBytes = 1_048_576
    static let fileBytes = 268_435_456
    static let totalBytes = 1_073_741_824
    static let entries = 10_000
    static let records = 1_000_000
    static let events = 100_000
    static let sqliteRows = 250_000
}

// Foundation may invoke its enumeration error handler through a Sendable closure.
final class EnumerationErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false

    func record() { lock.lock(); defer { lock.unlock() }; failed = true }
    var encountered: Bool { lock.lock(); defer { lock.unlock() }; return failed }
}

enum Notice: String {
    case coverage = "Local usage records do not prove complete billing coverage."
    case attribution = "Codex model attribution uses recorded turn configuration; actual backend reroutes may not be recorded."
    case symlink = "Symbolic links were skipped."
    case unavailable = "Some usage sources were missing or inaccessible."
    case empty = "No supported usage records were found."
    case limit = "A scan safety limit was reached; results are incomplete."
    case malformed = "Malformed or invalid usage records were skipped."
    case version = "Records from an unverified source version were skipped."
    case metadata = "Usage without verified provider or model metadata was skipped."
    case baseline = "An ambiguous cumulative snapshot was retained only as a baseline; usage was omitted."
    case reset = "Cumulative usage reset or diverged; ambiguous usage was omitted."
    case fork = "Forked, inherited, or rolled-back history was skipped to avoid duplicate usage."
    case oversized = "An oversized record was skipped; usage coverage may be incomplete."
    case partial = "An unterminated final record was deferred until a later scan."
    case cacheWrite = "Nonzero Codex cache-write usage is not supported by this adapter."
    case reroute = "A model reroute was detected; usage was skipped until new turn metadata."
    case steps = "Only canonical OpenCode step-finish usage is imported; message and session totals are not added."
}

extension ImportReport {
    mutating func warn(_ notice: Notice) {
        if !warnings.contains(notice.rawValue) { warnings.append(notice.rawValue) }
    }
}

func object(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

func identifier(_ value: Any?) -> String? {
    guard let value = value as? String, !value.isEmpty, value.utf8.count <= 256,
          !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
    return value
}

func integer(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          let result = Int64(number.stringValue), result >= 0 else { return nil }
    return result
}

func json(_ data: Data) -> [String: Any]? {
    guard let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return object(value)
}

// Check ancestors too: a regular-looking leaf can live inside a linked directory.
func fileType(_ url: URL) throws -> FileAttributeType {
    var current = url.standardizedFileURL
    while true {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: current.path) }
        catch { throw UsageImportError.unavailable }
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink { return .typeSymbolicLink }
        let parent = current.deletingLastPathComponent()
        if parent.path == current.path { break }
        current = parent
    }
    do {
        return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType ?? .typeUnknown
    } catch { throw UsageImportError.unavailable }
}

/// Streams complete lines only. Oversized lines are discarded without growing the buffer.
/// A nil line invalidates the caller's cumulative/model baseline.
func streamLines(_ url: URL, byteBudget: inout Int,
                 consume: (Data?, Int) -> Bool) throws -> (limited: Bool, partial: Bool) {
    guard try fileType(url) == .typeRegular else { throw UsageImportError.unavailable }
    let handle: FileHandle
    do { handle = try FileHandle(forReadingFrom: url) }
    catch { throw UsageImportError.unavailable }
    defer { try? handle.close() }
    var line = Data()
    var oversized = false
    var offset = 0
    var lineOffset = 0
    do {
        // Freeze the read extent: concurrent appends are reconciled by the next scan.
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let extent = Int(min(size, UInt64(min(ScanLimit.fileBytes, byteBudget))))
        while offset < extent {
            let chunk = try handle.read(upToCount: min(65_536, extent - offset)) ?? Data()
            if chunk.isEmpty { return (false, !line.isEmpty || oversized) }
            byteBudget -= chunk.count
            for byte in chunk {
                offset += 1
                if byte == 10 {
                    if !consume(oversized ? nil : line, lineOffset) { return (false, false) }
                    line.removeAll(keepingCapacity: true)
                    oversized = false
                    lineOffset = offset
                } else if !oversized {
                    if line.count == ScanLimit.lineBytes {
                        oversized = true
                        line.removeAll(keepingCapacity: true)
                    } else { line.append(byte) }
                }
            }
        }
        return (UInt64(extent) < size, !line.isEmpty || oversized)
    } catch { throw UsageImportError.unavailable }
}
