import AppKit
import BudgetCore
import Foundation
import Observation
import UsageAdapters

struct SourceStatus: Codable, Sendable {
    var sourcePath: String?
    var lastScan: Date?
    var lastSuccess: Date?
    var warnings: [String] = []
}

private struct ScanResult: Sendable {
    var events: [UsageEvent]
    var statuses: [UsageSource: SourceStatus]
    var warnings: [String]
}

@MainActor @Observable
final class AppStore {
    private(set) var settings = AppSettings()
    private(set) var events: [UsageEvent] = []
    private(set) var statuses: [UsageSource: SourceStatus] = [:]
    private(set) var summary: BudgetSummary?
    private(set) var isScanning = false
    private(set) var hasLoadedLedger = false
    private(set) var error: String?
    private var scanWarnings: [String] = []
    private var ledger: Ledger?
    private var settingsURL: URL?
    private var statusURL: URL?
    private var scanTask: Task<ScanResult, Error>?
    private var refreshTimer: Task<Void, Never>?
    private var refreshQueued = false

    init() {
        do {
            let manager = FileManager.default
            let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("TokenBudget", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let configurationURL = directory.appendingPathComponent("settings.json")
            if manager.fileExists(atPath: configurationURL.path) {
                settings = try SettingsStore.load(from: configurationURL)
            }
            let scanURL = directory.appendingPathComponent("scan-status.json")
            if manager.fileExists(atPath: scanURL.path) {
                do {
                    statuses = try JSONDecoder().decode([UsageSource: SourceStatus].self,
                                                        from: Data(contentsOf: scanURL))
                    for source in UsageSource.allCases {
                        let path = source == .opencode ? settings.openCodePath : settings.codexPath
                        if statuses[source]?.sourcePath != path { statuses[source] = SourceStatus() }
                    }
                } catch {
                    scanWarnings = ["Previous scan timestamps could not be read."]
                }
            }
            ledger = try Ledger(url: directory.appendingPathComponent("usage.sqlite"))
            settingsURL = configurationURL
            statusURL = scanURL
        } catch {
            self.error = "Private storage or saved settings could not be opened. Check access to Application Support/TokenBudget, then restart. Existing files have not been replaced."
        }
    }

    var discoveredSelections: [UsageSelection] {
        let imported = events.map { UsageSelection(source: $0.source, provider: $0.provider, model: $0.model) }
        return Set(imported + settings.selections).sorted {
            ($0.source.rawValue, $0.provider, $0.model) < ($1.source.rawValue, $1.provider, $1.model)
        }
    }

    var needsSetup: Bool {
        settings.enabledSources.isEmpty || !settings.selections.contains { settings.enabledSources.contains($0.source) }
    }

    var canShowEstimate: Bool {
        !needsSetup && hasLoadedLedger && (settings.enabledSources.contains { source in
            settings.selections.contains(where: { $0.source == source }) && statuses[source]?.lastSuccess != nil
        } || events.contains { event in
            settings.enabledSources.contains(event.source) && settings.selections.contains { $0.matches(event) }
        })
    }

    var warnings: [String] {
        var messages = scanWarnings
        for source in settings.enabledSources {
            messages += statuses[source]?.warnings ?? []
            if statuses[source]?.lastSuccess == nil {
                messages.append("\(source.label) has not completed a successful scan. Its coverage is unknown.")
            }
        }
        messages += summary?.warnings ?? []
        if let summary, summary.unpricedCount > 0 {
            messages.append("\(summary.unpricedCount) usage records have no applicable price. The estimate is incomplete.")
        }
        return Array(Set(messages)).sorted()
    }

    func lastUse(for source: UsageSource) -> Date? {
        events.lazy.filter { $0.source == source }.map(\.timestamp).max()
    }

    func start() {
        guard refreshTimer == nil else { return }
        refreshTimer = Task { [weak self] in
            self?.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                guard let self else { return }
                self.refresh()
            }
        }
    }

    func save(_ proposed: AppSettings) -> Bool {
        guard let settingsURL else { return false }
        do {
            // Check calendar/timezone configuration before changing persisted settings.
            _ = try BudgetEngine.window(for: proposed.budget, at: Date())
            try SettingsStore.save(proposed, to: settingsURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
            for source in UsageSource.allCases {
                let oldPath = source == .opencode ? settings.openCodePath : settings.codexPath
                let newPath = source == .opencode ? proposed.openCodePath : proposed.codexPath
                if oldPath != newPath { statuses[source] = SourceStatus() }
            }
            settings = proposed
            error = nil
            recompute()
            refresh()
            return true
        } catch {
            self.error = "Settings could not be saved. Check the budget configuration and private storage permissions."
            return false
        }
    }

    func refresh() {
        guard let ledger, let statusURL else { return }
        guard scanTask == nil else {
            refreshQueued = true
            return
        }
        isScanning = true
        let configuration = settings
        let oldStatuses = statuses
        // Only this detached task imports. Requests during a scan coalesce into one follow-up.
        let task = Task.detached(priority: .utility) { () throws -> ScanResult in
            var statuses = oldStatuses
            var warnings: [String] = []
            for source in configuration.enabledSources {
                var status = statuses[source] ?? SourceStatus()
                status.lastScan = Date()
                do {
                    let path = source == .opencode ? configuration.openCodePath : configuration.codexPath
                    if status.sourcePath != path { status = SourceStatus(lastScan: Date()) }
                    status.sourcePath = path
                    let expanded = NSString(string: path).expandingTildeInPath
                    guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          FileManager.default.isReadableFile(atPath: expanded) else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    let report: ImportReport
                    switch source {
                    case .opencode: report = try OpenCodeImporter.scan(path: expanded)
                    case .codex: report = try CodexImporter.scan(path: expanded)
                    }
                    try await ledger.merge(report.events)
                    status.lastSuccess = Date()
                    status.warnings = report.warnings.map { "\(source.label): \($0)" }
                } catch {
                    status.warnings = ["\(source.label) could not be imported. Previously recorded usage is retained; new usage may be missing."]
                }
                statuses[source] = status
            }
            let events = try await ledger.events()
            do {
                try JSONEncoder().encode(statuses).write(to: statusURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusURL.path)
            } catch {
                warnings.append("Scan timestamps could not be saved. Recorded usage is retained.")
            }
            return ScanResult(events: events, statuses: statuses, warnings: warnings)
        }
        scanTask = task
        Task { [weak self] in
            let result = await task.result
            guard let self else { return }
            self.scanTask = nil
            self.isScanning = false
            switch result {
            case .success(let scan):
                self.events = scan.events
                for source in UsageSource.allCases {
                    let scannedPath = source == .opencode ? configuration.openCodePath : configuration.codexPath
                    let currentPath = source == .opencode ? self.settings.openCodePath : self.settings.codexPath
                    if scannedPath == currentPath { self.statuses[source] = scan.statuses[source] }
                }
                self.scanWarnings = scan.warnings
                self.hasLoadedLedger = true
            case .failure:
                self.scanWarnings = ["The usage ledger could not be read. The previous estimate is retained and may be stale."]
            }
            self.recompute()
            if self.refreshQueued {
                self.refreshQueued = false
                self.refresh()
            }
        }
    }

    func recompute() {
        guard hasLoadedLedger else { return }
        do {
            var importWarnings = scanWarnings
            for source in settings.enabledSources {
                importWarnings += statuses[source]?.warnings ?? []
                if statuses[source]?.lastSuccess == nil {
                    importWarnings.append("An enabled source has not completed a successful scan.")
                }
            }
            summary = try BudgetEngine.summarize(events: events, settings: settings, at: Date(), warnings: importWarnings)
        } catch {
            summary = nil
            self.error = "The budget could not be calculated. Check the reset schedule, currency, and price profiles."
        }
    }
}

func money(_ amount: Decimal, currency: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount) \(currency)"
}

func decimalInput(_ text: String) -> Decimal? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.range(of: #"^[0-9]{1,18}(\.[0-9]{1,12})?$"#, options: .regularExpression) != nil,
          let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
          !number.isNaN else { return nil }
    return number
}

func validCurrency(_ text: String) -> Bool {
    Locale.commonISOCurrencyCodes.contains(text)
}
