import BudgetCore
import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class BudgetNotifications {
    private(set) var status = "Notifications are off."
    private(set) var revision = UUID()
    private var configuration: AppSettings?
    private var policy = BudgetAlerts()
    private let center = UNUserNotificationCenter.current()

    func configure(_ settings: AppSettings, requestPermission: Bool = false) {
        let enabling = configuration?.notificationsEnabled != true && settings.notificationsEnabled
        if configuration != settings {
            revision = UUID()
            policy.resetBaseline()
        }
        configuration = settings
        let revision = revision
        guard settings.notificationsEnabled else {
            status = "Notifications are off."
            center.removeAllPendingNotificationRequests()
            return
        }
        Task {
            guard self.revision == revision else { return }
            do {
                if enabling && requestPermission {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                }
                let authorization = await center.notificationSettings().authorizationStatus
                guard self.revision == revision else { return }
                _ = updateStatus(authorization)
            } catch {
                guard self.revision == revision else { return }
                status = "Notification permission could not be checked. Your enabled preference is saved."
            }
        }
    }

    func observe(summary: BudgetSummary?, settings: AppSettings, canShowEstimate: Bool,
                 successfulScan: Bool, revision: UUID, ledger: Ledger) async {
        guard self.revision == revision, configuration == settings else { return }
        let alerts = policy.observe(summary: summary, settings: settings,
                                    canShowEstimate: canShowEstimate, successfulScan: successfulScan)
        guard !alerts.isEmpty else { return }
        let authorization = await center.notificationSettings().authorizationStatus
        guard self.revision == revision else { return }
        let permitted = updateStatus(authorization)
        for alert in alerts {
            do {
                let recorded = try await ledger.notificationRecorded(key: alert.key)
                guard self.revision == revision else { return }
                guard !recorded else { continue }
                // Claim before delivery: a crash or denied permission must not produce a later flood.
                try await ledger.recordNotification(key: alert.key)
                guard self.revision == revision else { return }
                guard alert.shouldNotify, permitted else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Recorded estimate crossed \(alert.threshold)%"
                content.body = "Observed priced spend crossed \(alert.threshold)% of your configured budget. History may be incomplete; this is not a bill or remaining allowance."
                content.sound = .default
                // Keep local configuration keys and all source/provider/model identifiers out of the OS payload.
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                try await center.add(request)
            } catch {
                guard self.revision == revision else { return }
                status = "A budget notification could not be recorded or delivered. Your enabled preference is saved."
                return
            }
        }
    }

    private func updateStatus(_ authorization: UNAuthorizationStatus) -> Bool {
        switch authorization {
        case .authorized, .provisional:
            status = "Notifications enabled for new recorded-estimate crossings after a successful baseline scan."
            return true
        case .denied:
            status = "Notifications are enabled here but denied by macOS. Allow TokenBudget in System Settings > Notifications."
        case .notDetermined:
            status = "Permission has not been granted. Switch notifications off and apply, then on and apply to request permission."
        @unknown default:
            status = "Notification permission is unavailable. Check System Settings > Notifications."
        }
        return false
    }
}
