import AppKit
import BudgetCore
import SwiftUI

struct BudgetSettings: View {
    let store: AppStore
    @State private var draft: AppSettings
    @State private var amount: String
    @State private var message: String?
    @State private var priceSelection: UsageSelection?
    @State private var effectiveFrom = Date()
    @State private var priceCurrency: String
    @State private var inputRate = ""
    @State private var readRate = ""
    @State private var writeRate = ""
    @State private var outputRate = ""
    @State private var provenance = ""
    @State private var confirmedCoverage = false
    @State private var coverageStart = Date()

    init(store: AppStore) {
        self.store = store
        _draft = State(initialValue: store.settings)
        _amount = State(initialValue: NSDecimalNumber(decimal: store.settings.budget.amount).stringValue)
        _priceCurrency = State(initialValue: store.settings.budget.currency)
        _confirmedCoverage = State(initialValue: store.settings.coverageStart != nil)
        _coverageStart = State(initialValue: store.settings.coverageStart ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Local Sources") {
                    Text("Nothing is imported or included until you opt in. Apply sources first, then select discovered models below. Changes take effect with Apply Settings.")
                        .foregroundStyle(.secondary)
                    ForEach(UsageSource.allCases, id: \.self) { source in
                        sourceControls(source)
                    }
                    HStack {
                        Button("Refresh Saved Sources") { store.refresh() }.disabled(store.isScanning)
                        if store.isScanning { ProgressView().controlSize(.small) }
                    }
                    Text("Import reads local usage metadata only. No credentials, network requests, telemetry, or record export. Disabling a source excludes it from estimates but retains its ledger history.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Budget & Reset") {
                    TextField("Budget amount", text: $amount)
                    TextField("ISO currency (for example USD)", text: $draft.budget.currency)
                    Picker("Period", selection: $draft.budget.period) {
                        ForEach(BudgetPeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("Timezone identifier", text: $draft.budget.timeZoneID)
                    Text("Use an IANA timezone such as America/New_York, Europe/London, or UTC.")
                        .font(.caption).foregroundStyle(.secondary)
                    if draft.budget.period == .weekly {
                        Picker("Reset weekday", selection: $draft.budget.weekday) {
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(3)
                            Text("Wednesday").tag(4)
                            Text("Thursday").tag(5)
                            Text("Friday").tag(6)
                            Text("Saturday").tag(7)
                        }
                    } else {
                        Text("Monthly resets occur on the first day of the month.").font(.caption)
                    }
                    HStack {
                        Picker("Hour (24h)", selection: $draft.budget.hour) {
                            ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                        Picker("Minute", selection: $draft.budget.minute) {
                            ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                        }
                    }
                    Text("Amounts and rates use a decimal point. Prices must match the budget currency; no currency conversion is performed.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Included Provider / Models") {
                    if store.discoveredSelections.isEmpty {
                        Text("No models discovered yet. Enable a source, set its path, then apply and refresh. No models are selected automatically.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.discoveredSelections, id: \.self) { selection in
                        Toggle(selectionLabel(selection), isOn: Binding(
                            get: { draft.selections.contains(selection) },
                            set: { included in
                                draft.selections.removeAll { $0 == selection }
                                if included { draft.selections.append(selection) }
                            }
                        ))
                    }
                }

                Section("Append Dated Price Profile") {
                    Text("No rates are supplied. Enter all four rates per million tokens, including explicit 0 for free categories. Blank means missing, never zero. A profile applies from its effective date until the next profile for that model and currency.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Provider / model", selection: $priceSelection) {
                        Text("Choose a discovered model").tag(Optional<UsageSelection>.none)
                        ForEach(store.discoveredSelections, id: \.self) {
                            Text(selectionLabel($0)).tag(Optional($0))
                        }
                    }
                    DatePicker("Effective from (local timezone)", selection: $effectiveFrom)
                    TextField("Rate currency", text: $priceCurrency)
                    TextField("Input / million", text: $inputRate)
                    TextField("Cache read / million", text: $readRate)
                    TextField("Cache write / million", text: $writeRate)
                    TextField("Output / million", text: $outputRate)
                    TextField("Provenance (rate card URL or your agreement reference)", text: $provenance)
                    Button("Add Profile to Draft") { appendPrice() }
                    Text("Adding does not replace an existing profile. Apply Settings to persist the draft. Backdating a new profile intentionally recalculates affected estimates.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if !draft.prices.isEmpty {
                    Section("Price History") {
                        ForEach(draft.prices.sorted { $0.effectiveFrom > $1.effectiveFrom }) { price in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(price.source.label) / \(price.provider) / \(price.model)").font(.headline)
                                Text("From \(price.effectiveFrom.formatted(date: .abbreviated, time: .standard)) / \(price.currency) / million")
                                Text("Input \(price.inputPerMillion.description) | Read \(price.cacheReadPerMillion.description) | Write \(price.cacheWritePerMillion.description) | Output \(price.outputPerMillion.description)")
                                Text(price.provenance).foregroundStyle(.secondary).textSelection(.enabled)
                            }.font(.caption)
                        }
                    }
                }

                Section("History & Notifications") {
                    Toggle("I confirm complete history for the enabled sources and included models", isOn: $confirmedCoverage)
                    if confirmedCoverage {
                        DatePicker("Complete history begins (local timezone)", selection: $coverageStart, in: ...Date())
                    }
                    Text("Forecast is hidden unless you confirm coverage. Local logs alone cannot establish complete history. Recheck this confirmation after changing paths or included models.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("80% and 100% notifications are not implemented in this version. No notification permissions are requested and no historical alerts are sent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let message { Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
                if let error = store.error { Text(error).font(.callout).foregroundStyle(.red) }
                HStack {
                    Text("Stored privately in Application Support/TokenBudget.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply Settings") { apply() }.keyboardShortcut("s", modifiers: .command)
                }
            }.padding()
        }
        .frame(minWidth: 650, minHeight: 560)
        .task { store.refresh() }
        .onChange(of: draft.enabledSources) { confirmedCoverage = false }
        .onChange(of: draft.openCodePath) { confirmedCoverage = false }
        .onChange(of: draft.codexPath) { confirmedCoverage = false }
        .onChange(of: draft.selections) { confirmedCoverage = false }
    }

    private func sourceControls(_ source: UsageSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(source.label, isOn: Binding(
                get: { draft.enabledSources.contains(source) },
                set: { enabled in
                    draft.enabledSources.removeAll { $0 == source }
                    if enabled { draft.enabledSources.append(source) }
                }
            ))
            HStack {
                TextField("Local source path", text: pathBinding(source))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(source.label) local path")
                Button("Choose...") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = true
                    panel.allowsMultipleSelection = false
                    panel.showsHiddenFiles = true
                    panel.prompt = "Use Local Source"
                    if panel.runModal() == .OK, let url = panel.url {
                        pathBinding(source).wrappedValue = url.path
                    }
                }
            }
            Text(source == .opencode
                 ? "Choose opencode.db or its data directory."
                 : "Choose a rollout JSONL file or a sessions/archive directory.")
                .foregroundStyle(.secondary)
            Text("Last scan attempt: \(timestamp(store.statuses[source]?.lastScan))")
            Text("Last successful scan: \(timestamp(store.statuses[source]?.lastSuccess))")
            Text("Last recorded use: \(timestamp(store.lastUse(for: source)))")
            ForEach(store.statuses[source]?.warnings ?? [], id: \.self) {
                Text($0).foregroundStyle(.orange)
            }
        }.font(.caption)
    }

    private func pathBinding(_ source: UsageSource) -> Binding<String> {
        source == .opencode ? $draft.openCodePath : $draft.codexPath
    }

    private func timestamp(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Not known"
    }

    private func selectionLabel(_ selection: UsageSelection) -> String {
        "\(selection.source.label) / \(selection.provider) / \(selection.model)"
    }

    private func appendPrice() {
        let currency = priceCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let reference = provenance.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveDate = Date(timeIntervalSince1970: floor(effectiveFrom.timeIntervalSince1970 / 60) * 60)
        guard let selection = priceSelection, validCurrency(currency), !reference.isEmpty,
              let input = decimalInput(inputRate), let read = decimalInput(readRate),
              let write = decimalInput(writeRate), let output = decimalInput(outputRate),
              [input, read, write, output].allSatisfy({ $0 <= Decimal(1_000_000_000) }) else {
            message = "Choose a model, ISO currency, provenance, and four decimal rates between 0 and 1,000,000,000 per million tokens. Enter 0 explicitly where applicable."
            return
        }
        guard !draft.prices.contains(where: {
            $0.source == selection.source && $0.provider == selection.provider && $0.model == selection.model
                && $0.currency == currency && $0.effectiveFrom == effectiveDate
        }) else {
            message = "A profile already exists for this model, currency, and effective time. Choose a distinct effective time; existing profiles are never overwritten."
            return
        }
        draft.prices.append(PriceProfile(source: selection.source, provider: selection.provider,
                                         model: selection.model, currency: currency, effectiveFrom: effectiveDate,
                                         inputPerMillion: input, cacheReadPerMillion: read,
                                         cacheWritePerMillion: write, outputPerMillion: output,
                                         provenance: reference))
        message = "Dated profile added to draft. Apply Settings to save it."
    }

    private func apply() {
        let currency = draft.budget.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let value = decimalInput(amount), value > 0, validCurrency(currency) else {
            message = "Enter a positive budget amount and a valid three-letter ISO currency."
            return
        }
        draft.budget.timeZoneID = draft.budget.timeZoneID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TimeZone(identifier: draft.budget.timeZoneID) != nil else {
            message = "Enter a valid timezone identifier."
            return
        }
        draft.openCodePath = draft.openCodePath.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.codexPath = draft.codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.enabledSources.contains(where: {
            ($0 == .opencode ? draft.openCodePath : draft.codexPath).isEmpty
        }) else {
            message = "Choose or enter a local path for each enabled source."
            return
        }
        draft.budget.amount = value
        draft.budget.currency = currency
        draft.notificationsEnabled = false
        draft.coverageStart = confirmedCoverage ? coverageStart : nil
        if store.save(draft) { message = "Settings saved. Enabled sources are being refreshed." }
    }
}
