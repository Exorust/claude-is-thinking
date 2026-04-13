import Foundation
import UserNotifications

final class GrassNotifier {
    private let dataStore: DataStore
    private var lastNotificationDate: Date?
    private var snoozedUntil: Date?

    private let messages = [
        "You've waited %@ for Claude Code today. Go touch grass for %@ to compensate.",
        "Claude has been thinking for %@ today. Your houseplants miss you.",
        "Time spent waiting for AI today: %@. Time spent outside: probably less.",
        "You've given Claude %@ of your day. Maybe take %@ back for yourself.",
        "%@ waiting for Claude Code today. That's enough time to bake bread.",
    ]

    private let sessionEndMessages = [
        "Claude just thought for %@. That's longer than most microwave meals.",
        "That response took %@. Perfect nap length, honestly.",
        "%@ of thinking. Claude was really chewing on that one.",
        "You just waited %@ for a response. The internet owes you.",
        "Claude took %@ to respond. Your patience is legendary.",
        "%@ for one response. At this rate, you could learn to knit.",
        "That was %@ of pure suspense. Hitchcock would be proud.",
    ]

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func requestPermission() {
        // UNUserNotificationCenter requires a valid bundle identifier.
        // When running as a bare SPM executable (no .app bundle), skip notifications.
        guard Bundle.main.bundleIdentifier != nil else {
            print("[TimeSpend] No bundle ID, notifications disabled. Build as .app for notifications.")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("[TimeSpend] Notification permission error: \(error)")
            }
        }

        // Register actions
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Remind in 30 min", options: [])
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "I'm good today", options: [])
        let category = UNNotificationCategory(identifier: "TOUCH_GRASS", actions: [snooze, dismiss], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func checkThreshold() {
        let thresholdStr = dataStore.getSetting(.grassThreshold) ?? "180"
        let threshold = Int(thresholdStr) ?? 180

        // 0 means disabled
        guard threshold > 0 else { return }

        // Check snooze
        if let snoozed = snoozedUntil, Date() < snoozed { return }

        // Only notify once per threshold crossing per day
        if let lastDate = lastNotificationDate,
           Calendar.current.isDateInToday(lastDate) { return }

        let todayTotal = dataStore.getTodayTotalSeconds()
        guard todayTotal >= threshold else { return }

        sendNotification(totalSeconds: todayTotal)
        lastNotificationDate = Date()
    }

    func snooze(minutes: Int = 30) {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    func dismissForToday() {
        lastNotificationDate = Date()
    }

    func notifySessionEnd(durationSeconds: Int) {
        guard durationSeconds >= 60 else { return }
        guard Bundle.main.bundleIdentifier != nil else { return }

        let durationStr = DataStore.formatDuration(durationSeconds)
        let template = sessionEndMessages.randomElement()!
        let body = template.replacingOccurrences(of: "%@", with: durationStr)

        let content = UNMutableNotificationContent()
        content.title = "Claude is done!"
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "session-end-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[TimeSpend] Session end notification failed: \(error)")
            }
        }
    }

    private func sendNotification(totalSeconds: Int) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let totalStr = DataStore.formatDuration(totalSeconds)
        let compensateMinutes = max(totalSeconds / 60 / 3, 5)
        let compensateStr = "\(compensateMinutes) minutes"

        let template = messages.randomElement()!
        let body: String
        if template.contains("%@") {
            // Replace first %@ with total, second %@ with compensate time
            let parts = template.components(separatedBy: "%@")
            if parts.count >= 3 {
                body = parts[0] + totalStr + parts[1] + compensateStr + parts[2]
            } else if parts.count >= 2 {
                body = parts[0] + totalStr + parts[1]
            } else {
                body = template
            }
        } else {
            body = template
        }

        let content = UNMutableNotificationContent()
        content.title = "Time to touch grass"
        content.body = body
        content.categoryIdentifier = "TOUCH_GRASS"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "grass-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[TimeSpend] Notification failed: \(error)")
            }
        }
    }
}
