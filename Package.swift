// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "BudgetCore", targets: ["BudgetCore"]),
    .library(name: "UsageAdapters", targets: ["UsageAdapters"]),
    .executable(name: "token-budget-diagnostics", targets: ["TokenBudgetDiagnostics"]),
]
var targets: [Target] = [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
    .target(name: "BudgetCore", dependencies: ["CSQLite"]),
    .target(name: "UsageAdapters", dependencies: ["BudgetCore", "CSQLite"]),
    .executableTarget(name: "TokenBudgetDiagnostics", dependencies: ["UsageAdapters"]),
    .testTarget(name: "BudgetCoreTests", dependencies: ["BudgetCore"]),
    .testTarget(name: "UsageAdaptersTests", dependencies: ["UsageAdapters", "CSQLite"]),
]
#if os(macOS)
products.append(.executable(name: "TokenBudget", targets: ["TokenBudgetApp"]))
targets.append(.executableTarget(name: "TokenBudgetApp", dependencies: ["BudgetCore", "UsageAdapters"]))
#endif

let package = Package(
    name: "TokenBudget", platforms: [.macOS("26.0")],
    products: products, targets: targets
)
