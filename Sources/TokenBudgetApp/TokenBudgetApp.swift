import AppKit
import BudgetCore
import SwiftUI

@main
struct TokenBudgetApp: App {
    @State private var store: AppStore

    init() {
        let store = AppStore()
        _store = State(initialValue: store)
        store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            BudgetMenu(store: store)
        } label: {
            if store.canShowEstimate, let summary = store.summary {
                Text("\(store.warnings.isEmpty ? "" : "! ")~\(money(summary.spent, currency: store.settings.budget.currency)) / \(money(store.settings.budget.amount, currency: store.settings.budget.currency))")
                    .monospacedDigit()
                    .accessibilityLabel("Token Budget, estimated spend out of budget. \(store.warnings.isEmpty ? "" : "Incomplete coverage.")")
            } else {
                Label("Budget: --", systemImage: "chart.bar.doc.horizontal")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Token Budget Settings", id: "settings") {
            BudgetSettings(store: store)
        }
        .defaultSize(width: 720, height: 720)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands { BudgetCommands() }
    }
}

struct BudgetCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")
        }
    }
}

struct BudgetMenu: View {
    let store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Token Budget").font(.headline)
                Spacer()
                if store.isScanning { ProgressView().controlSize(.small) }
            }
            if store.needsSetup {
                Text("Set up your estimate").font(.title2.bold())
                Text("Enable a local source, refresh, then select the provider/models to include and add your prices.")
                    .foregroundStyle(.secondary)
            } else if store.canShowEstimate, let summary = store.summary {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.warnings.isEmpty ? "Estimated recorded spend" : "Partial estimate - check warnings")
                        .foregroundStyle(.secondary)
                    Text(money(summary.spent, currency: store.settings.budget.currency))
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                    Text("\(money(summary.remaining, currency: store.settings.budget.currency)) estimated remaining of \(money(store.settings.budget.amount, currency: store.settings.budget.currency))")
                        .font(.callout)
                    ProgressView(value: min(1, max(0, NSDecimalNumber(decimal: summary.spent / store.settings.budget.amount).doubleValue)))
                        .accessibilityLabel("Budget used")
                }
                Text("\(store.settings.budget.period.rawValue.capitalized) budget / \(store.settings.budget.timeZoneID)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Period starts \(date(summary.window.start)); resets \(date(summary.window.end))")
                    .font(.caption)
                ForEach(store.settings.enabledSources, id: \.self) { source in
                    HStack {
                        Text(source.label)
                        Spacer()
                        if store.statuses[source]?.lastSuccess != nil || store.lastUse(for: source) != nil {
                            Text(money(summary.bySource[source] ?? 0, currency: store.settings.budget.currency))
                                .monospacedDigit()
                        } else {
                            Text("Unknown").foregroundStyle(.secondary)
                        }
                    }
                }
                if store.settings.coverageStart != nil, summary.unpricedCount == 0, let forecast = summary.forecast {
                    Text("Projected total (user-confirmed history): \(money(forecast, currency: store.settings.budget.currency))")
                        .font(.callout)
                }
                Text("Local records and your rates, not a provider bill. Missing records or prices can understate spend.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Estimate unavailable").font(.title2.bold())
                Text("Waiting for a readable source and imported usage. An unavailable source is not a zero balance.")
                    .foregroundStyle(.secondary)
            }
            if let error = store.error { warning(error) }
            if !store.warnings.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(store.warnings, id: \.self) { warning($0) }
                    }
                }.frame(maxHeight: 140)
            }
            Divider()
            if let lastScan = store.settings.enabledSources.compactMap({ store.statuses[$0]?.lastSuccess }).min() {
                Text("Oldest source scan: \(date(lastScan))").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh") { store.refresh() }.disabled(store.isScanning)
                Button("Settings...") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 390)
        .onAppear { store.recompute() }
    }

    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: store.settings.budget.timeZoneID)
        return formatter.string(from: value)
    }
}
