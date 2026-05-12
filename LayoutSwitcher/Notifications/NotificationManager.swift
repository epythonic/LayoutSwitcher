import Foundation
import UserNotifications
import os

/// Posts local notifications when an automatic layout switch occurs,
/// offering an inline "Undo" action that reverts the correction.
@MainActor
final class NotificationManager: NSObject {
    static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "Notifications")

    /// Identifier for the auto-switch notification category.
    static let autoSwitchCategory = "autoSwitch"
    /// Identifier for the inline undo action.
    static let undoActionIdentifier = "undoAction"

    /// Closure invoked when the user taps the Undo action on a notification.
    var onUndoRequested: (() -> Void)?

    private var pendingNotificationID: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Requests authorization if not already granted.
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.logger.error("Notification authorization error: \(error.localizedDescription, privacy: .public)")
            } else {
                Self.logger.info("Notification authorization: \(granted, privacy: .public)")
            }
        }
    }

    /// Registers the notification category with an Undo action.
    func registerCategories() {
        let undoAction = UNNotificationAction(
            identifier: Self.undoActionIdentifier,
            title: String(localized: "notification.action.undo"),
            options: .foreground
        )
        let category = UNNotificationCategory(
            identifier: Self.autoSwitchCategory,
            actions: [undoAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// Posts a notification for a successful auto-switch, embedding the record ID for undo.
    func postAutoSwitchNotification(original: String, corrected: String) {
        let id = UUID().uuidString
        pendingNotificationID = id

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.title.layout-switched")
        let bodyFormat = String(localized: "notification.body.auto-switched")
        content.body = String(format: bodyFormat, original, corrected)
        content.sound = .default
        content.categoryIdentifier = Self.autoSwitchCategory
        content.userInfo = ["original": original, "corrected": corrected]

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes any pending auto-switch notification (e.g. after manual undo via hotkey).
    func clearPendingNotification() {
        if let id = pendingNotificationID {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
            pendingNotificationID = nil
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification responses while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle the user tapping the Undo action on a delivered notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.undoActionIdentifier {
            Self.logger.info("Undo action triggered from notification")
            onUndoRequested?()
        }
        completionHandler()
    }
}
