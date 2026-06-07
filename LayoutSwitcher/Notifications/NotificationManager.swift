import Foundation
import UserNotifications
import os

/// Posts local notifications when an automatic layout switch occurs,
/// offering an inline "Undo" action that reverts the correction.
@MainActor
final class NotificationManager: NSObject {
    typealias SetDelegate = @MainActor (UNUserNotificationCenterDelegate?) -> Void
    typealias RequestAuthorization = @MainActor (@escaping @Sendable (Bool, Error?) -> Void) -> Void
    typealias SetNotificationCategories = @MainActor (Set<UNNotificationCategory>) -> Void
    typealias AddNotificationRequest = @MainActor (UNNotificationRequest, @escaping @Sendable (Error?) -> Void) -> Void
    typealias RemoveDeliveredNotifications = @MainActor ([String]) -> Void
    typealias MakeNotificationID = @MainActor () -> String

    nonisolated static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "Notifications")

    /// Identifier for the auto-switch notification category.
    static let autoSwitchCategory = "autoSwitch"
    /// Identifier for the inline undo action.
    static let undoActionIdentifier = "undoAction"

    /// Closure invoked when the user taps the Undo action on a notification.
    var onUndoRequested: (@MainActor () -> Void)?

    /// Last delivered notification ID that can be cleared after an undo.
    private var pendingNotificationID: String?
    /// Injected notification-center delegate setter.
    private let setDelegate: SetDelegate
    /// Injected authorization requester.
    private let requestAuthorizationHandler: RequestAuthorization
    /// Injected category registrar.
    private let setNotificationCategories: SetNotificationCategories
    /// Injected notification request sender.
    private let addNotificationRequest: AddNotificationRequest
    /// Injected delivered-notification remover.
    private let removeDeliveredNotifications: RemoveDeliveredNotifications
    /// Injected notification ID factory for deterministic tests.
    private let makeNotificationID: MakeNotificationID
    /// Explicit sound policy for posted notifications.
    private let notificationSound: UNNotificationSound?

    /// Creates a notification manager backed by the provided notification center.
    convenience init(
        notificationCenter: UNUserNotificationCenter,
        makeNotificationID: @escaping MakeNotificationID,
        notificationSound: UNNotificationSound?
    ) {
        self.init(
            setDelegate: { delegate in
                notificationCenter.delegate = delegate
            },
            requestAuthorization: { completion in
                notificationCenter.requestAuthorization(options: [.alert, .sound], completionHandler: completion)
            },
            setNotificationCategories: { categories in
                notificationCenter.setNotificationCategories(categories)
            },
            addNotificationRequest: { request, completion in
                notificationCenter.add(request, withCompletionHandler: completion)
            },
            removeDeliveredNotifications: { identifiers in
                notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
            },
            makeNotificationID: makeNotificationID,
            notificationSound: notificationSound
        )
    }

    /// Creates a notification manager with injectable side-effect closures.
    ///
    /// Tests inject all closures to avoid touching the real notification center.
    init(
        setDelegate: @escaping SetDelegate,
        requestAuthorization: @escaping RequestAuthorization,
        setNotificationCategories: @escaping SetNotificationCategories,
        addNotificationRequest: @escaping AddNotificationRequest,
        removeDeliveredNotifications: @escaping RemoveDeliveredNotifications,
        makeNotificationID: @escaping MakeNotificationID,
        notificationSound: UNNotificationSound?
    ) {
        self.setDelegate = setDelegate
        self.requestAuthorizationHandler = requestAuthorization
        self.setNotificationCategories = setNotificationCategories
        self.addNotificationRequest = addNotificationRequest
        self.removeDeliveredNotifications = removeDeliveredNotifications
        self.makeNotificationID = makeNotificationID
        self.notificationSound = notificationSound
        super.init()
        self.setDelegate(self)
    }

    /// Requests authorization if not already granted.
    func requestAuthorization() {
        requestAuthorizationHandler { granted, error in
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
        setNotificationCategories([category])
    }

    /// Posts a notification for a successful auto-switch, embedding the record ID for undo.
    func postAutoSwitchNotification(original: String, corrected: String) {
        let id = makeNotificationID()
        pendingNotificationID = id

        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.title.layout-switched")
        let bodyFormat = String(localized: "notification.body.auto-switched")
        content.body = String(format: bodyFormat, original, corrected)
        content.sound = notificationSound
        content.categoryIdentifier = Self.autoSwitchCategory
        content.userInfo = ["original": original, "corrected": corrected]

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        addNotificationRequest(request) { error in
            if let error {
                Self.logger.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes any pending auto-switch notification (e.g. after manual undo via hotkey).
    func clearPendingNotification() {
        if let id = pendingNotificationID {
            removeDeliveredNotifications([id])
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
