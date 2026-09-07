import Foundation
import BudgetCore

public enum CodexImporter {
    /// Reads one rollout JSONL file, or recursively scans a sessions/archive directory.
    public static func scan(path: String) throws -> ImportReport {
        guard !path.isEmpty else { throw UsageImportError.unavailable }
        var report = ImportReport()
        report.warn(.coverage)
        report.warn(.attribution)
        let root = URL(fileURLWithPath: path)
        let type = try fileType(root)
        if type == .typeSymbolicLink { report.warn(.symlink); return report }
        var files: [URL] = []
        if type == .typeRegular {
            guard root.pathExtension == "jsonl" else { throw UsageImportError.unsupported }
            files = [root]
        } else if type == .typeDirectory {
            let errors = EnumerationErrors()
            guard let enumerator = FileManager.default.enumerator(at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey],
                options: [], errorHandler: { _, _ in errors.record(); return true }) else {
                throw UsageImportError.unavailable
            }
            var entries = 0
            while let url = enumerator.nextObject() as? URL {
                entries += 1
                if entries > ScanLimit.entries { report.warn(.limit); break }
                do {
                    let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
                    if values.isSymbolicLink == true {
                        enumerator.skipDescendants(); report.warn(.symlink)
                    } else if values.isRegularFile == true && url.pathExtension == "jsonl" { files.append(url) }
                    else if url.pathExtension == "zst" || url.pathExtension == "gz" { report.warn(.version) }
                } catch { report.warn(.unavailable) }
            }
            if errors.encountered { report.warn(.unavailable) }
        } else { throw UsageImportError.unavailable }

        var byteBudget = ScanLimit.totalBytes
        for file in files.sorted(by: { $0.path < $1.path }) {
            if byteBudget == 0 || report.scannedRecords == ScanLimit.records || report.events.count == ScanLimit.events {
                report.warn(.limit); break
            }
            var session: String?
            var provider: String?
            var model: String?
            var previous: [Int64]?
            var pristine = true
            var sawMeta = false
            let start = report.events.count
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let seconds = ISO8601DateFormatter()
            do {
                let result = try streamLines(file, byteBudget: &byteBudget) { data, offset in
                    if report.scannedRecords == ScanLimit.records || report.events.count == ScanLimit.events {
                        report.warn(.limit); return false
                    }
                    report.scannedRecords += 1
                    guard let data else {
                        report.warn(.oversized); previous = nil; model = nil; pristine = false; return sawMeta
                    }
                    if data.allSatisfy({ $0 == 13 || $0 == 32 || $0 == 9 }) { return true }
                    guard let row = json(data), let type = row["type"] as? String,
                          let payload = object(row["payload"]) else {
                        report.warn(.malformed); previous = nil; model = nil; pristine = false; return sawMeta
                    }
                    if type == "session_meta" {
                        // A second metadata record can be a copied fork prefix, not a new session.
                        if sawMeta {
                            report.events.removeSubrange(start...); report.warn(.fork); return false
                        }
                        sawMeta = true
                        guard payload["cli_version"] as? String == "0.153.4" else { report.warn(.version); return false }
                        let inherited = ["forked_from_id", "forked_from_ordinal_exclusive", "history_base",
                                         "parent_thread_id", "subagent_history_start_ordinal"]
                        if inherited.contains(where: { payload[$0] != nil && !(payload[$0] is NSNull) })
                            || (payload["history_mode"] != nil && payload["history_mode"] as? String != "legacy") {
                            report.warn(.fork); return false
                        }
                        session = identifier(payload["id"])
                        provider = identifier(payload["model_provider"])
                        guard session != nil, provider != nil else { report.warn(.metadata); return false }
                        return true
                    }
                    // Never adopt a later copied parent's metadata after an absent header.
                    guard sawMeta else { report.warn(.metadata); return false }
                    if type == "turn_context" {
                        model = identifier(payload["model"])
                        if model == nil { report.warn(.metadata) }
                        return true
                    }
                    if type == "compacted" {
                        previous = nil; pristine = false; report.warn(.reset); return true
                    }
                    guard type == "event_msg" else { return true }
                    if payload["type"] as? String == "thread_rolled_back" { report.warn(.fork); return false }
                    if payload["type"] as? String == "model_reroute" {
                        model = nil; report.warn(.reroute); return true
                    }
                    guard payload["type"] as? String == "token_count" else { return true }
                    if payload["info"] is NSNull { return true } // rate-limit-only notification
                    guard let info = object(payload["info"]), let total = snapshot(info["total_token_usage"]),
                          let last = snapshot(info["last_token_usage"]) else {
                        report.warn(.malformed); previous = nil; pristine = false; return true
                    }
                    if total[5] != 0 || last[5] != 0 {
                        report.warn(.cacheWrite); previous = nil; pristine = false; return true
                    }
                    let baseline = previous
                    previous = total
                    defer { pristine = false }
                    if baseline == total { return true }
                    let delta: [Int64]
                    if let baseline {
                        guard zip(total, baseline).allSatisfy({ $0 >= $1 }) else { report.warn(.reset); return true }
                        delta = zip(total, baseline).map { $0 - $1 }
                        guard delta == last else { report.warn(.reset); return true }
                    } else {
                        guard pristine && total == last else { report.warn(.baseline); return true }
                        delta = total
                    }
                    guard delta[1] <= delta[0], delta[3] <= delta[2] else { report.warn(.malformed); return true }
                    let counts = TokenCounts(input: delta[0] - delta[1], cacheRead: delta[1], output: delta[2])
                    if counts.isEmpty { return true }
                    guard let session, let provider, let model else { report.warn(.metadata); return true }
                    guard let stamp = row["timestamp"] as? String, stamp.utf8.count <= 64,
                          let date = fractional.date(from: stamp) ?? seconds.date(from: stamp) else {
                        report.warn(.malformed); return true
                    }
                    report.events.append(UsageEvent(id: "codex:snapshot:\(session.utf8.count):\(session):\(offset)",
                        source: .codex, timestamp: date, provider: provider, model: model, tokens: counts))
                    return true
                }
                if result.limited { report.warn(.limit) }
                if result.partial { report.warn(.partial) }
                if !sawMeta { report.warn(.metadata) }
            } catch {
                // A failed file must not leave partially imported history behind.
                report.events.removeSubrange(start...)
                if type == .typeRegular { throw UsageImportError.unavailable }
                report.warn(.unavailable)
            }
        }
        if report.events.isEmpty { report.warn(.empty) }
        return report
    }

    private static func snapshot(_ value: Any?) -> [Int64]? {
        guard let value = object(value) else { return nil }
        let keys = ["input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens", "total_tokens"]
        let counts = keys.compactMap { integer(value[$0]) }
        guard counts.count == keys.count, counts[1] <= counts[0], counts[3] <= counts[2] else { return nil }
        let sum = counts[0].addingReportingOverflow(counts[2])
        guard !sum.overflow, sum.partialValue == counts[4] else { return nil }
        let write: Int64
        if let raw = value["cache_write_input_tokens"] {
            guard let parsed = integer(raw) else { return nil }
            write = parsed
        } else { write = 0 }
        return counts + [write]
    }
}
