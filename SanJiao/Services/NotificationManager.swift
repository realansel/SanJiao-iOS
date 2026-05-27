import UserNotifications

enum NotificationManager {

    static let dailyReminderID = "com.sanjiao.daily-reminder"

    // MARK: - Permission

    /// Request authorization and, if granted, schedule (or cancel) based on current setting.
    static func requestAuthorizationIfNeeded(enabled: Bool, hour: Int = 21, minute: Int = 0) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if granted && enabled {
                    scheduleDailyReminder(hour: hour, minute: minute)
                } else {
                    cancelDailyReminder()
                }
            }
        }
    }

    /// Restore or cancel reminders on launch without triggering a system permission prompt.
    static func restoreReminderIfAuthorized(enabled: Bool, hour: Int = 21, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard enabled else {
                    cancelDailyReminder()
                    return
                }

                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    scheduleDailyReminder(hour: hour, minute: minute)
                default:
                    cancelDailyReminder()
                }
            }
        }
    }

    // MARK: - Schedule / Cancel

    /// Schedule a repeating daily notification at the given hour and minute.
    static func scheduleDailyReminder(hour: Int = 21, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()

        // Avoid duplicates — remove existing first
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderID])

        let content = UNMutableNotificationContent()
        content.title = "记一笔 📒"
        content.body = "今天的支出还没记录，花 3 秒记下来吧。"
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: dailyReminderID,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// Cancel the daily reminder.
    static func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyReminderID])
    }
}
