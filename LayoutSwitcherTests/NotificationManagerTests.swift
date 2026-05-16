import Testing
import UserNotifications
@testable import LayoutSwitcher

@MainActor
struct NotificationManagerTests {
    private enum TestError: Error {
        case failed
    }

    @Test func initAssignsNotificationCenterDelegate() {
        var capturedDelegate: UNUserNotificationCenterDelegate?

        let manager = makeManager(
            setDelegate: { capturedDelegate = $0 }
        )

        #expect((capturedDelegate as AnyObject?) === (manager as AnyObject))
    }

    @Test func requestAuthorizationUsesInjectedRequester() {
        var didRequestAuthorization = false
        let manager = makeManager(
            setDelegate: { _ in },
            requestAuthorization: { completion in
                didRequestAuthorization = true
                completion(true, nil)
            }
        )

        manager.requestAuthorization()

        #expect(didRequestAuthorization)
    }

    @Test func registerCategoriesRegistersAutoSwitchUndoAction() {
        var capturedCategories: Set<UNNotificationCategory> = []
        let manager = makeManager(
            setDelegate: { _ in },
            setNotificationCategories: { capturedCategories = $0 }
        )

        manager.registerCategories()

        let category = capturedCategories.first { $0.identifier == NotificationManager.autoSwitchCategory }
        #expect(category != nil)

        guard let category else {
            return
        }

        #expect(category.actions.map(\.identifier) == [NotificationManager.undoActionIdentifier])
    }

    @Test func postAutoSwitchNotificationSendsDeterministicRequest() {
        var capturedRequest: UNNotificationRequest?
        let manager = makeManager(
            setDelegate: { _ in },
            addNotificationRequest: { request, completion in
                capturedRequest = request
                completion(nil)
            },
            makeNotificationID: { "notification-id" }
        )

        manager.postAutoSwitchNotification(original: "ghbdtn", corrected: "привет")

        #expect(capturedRequest?.identifier == "notification-id")
        #expect(capturedRequest?.content.categoryIdentifier == NotificationManager.autoSwitchCategory)
        #expect(capturedRequest?.content.userInfo["original"] as? String == "ghbdtn")
        #expect(capturedRequest?.content.userInfo["corrected"] as? String == "привет")
    }

    @Test func clearPendingNotificationRemovesOnlyOnce() {
        var removedIdentifiers: [[String]] = []
        let manager = makeManager(
            setDelegate: { _ in },
            addNotificationRequest: { _, completion in completion(nil) },
            removeDeliveredNotifications: { removedIdentifiers.append($0) },
            makeNotificationID: { "notification-id" }
        )

        manager.postAutoSwitchNotification(original: "ghbdtn", corrected: "привет")
        manager.clearPendingNotification()
        manager.clearPendingNotification()

        #expect(removedIdentifiers == [["notification-id"]])
    }

    @Test func postAutoSwitchNotificationLogsInjectedFailureWithoutThrowing() {
        var didCallCompletion = false
        let manager = makeManager(
            setDelegate: { _ in },
            addNotificationRequest: { _, completion in
                didCallCompletion = true
                completion(TestError.failed)
            },
            makeNotificationID: { "notification-id" }
        )

        manager.postAutoSwitchNotification(original: "ghbdtn", corrected: "привет")

        #expect(didCallCompletion)
    }

    private func makeManager(
        setDelegate: @escaping NotificationManager.SetDelegate = { _ in },
        requestAuthorization: @escaping NotificationManager.RequestAuthorization = { completion in completion(true, nil) },
        setNotificationCategories: @escaping NotificationManager.SetNotificationCategories = { _ in },
        addNotificationRequest: @escaping NotificationManager.AddNotificationRequest = { _, completion in completion(nil) },
        removeDeliveredNotifications: @escaping NotificationManager.RemoveDeliveredNotifications = { _ in },
        makeNotificationID: @escaping NotificationManager.MakeNotificationID = { "notification-id" },
        notificationSound: UNNotificationSound? = nil
    ) -> NotificationManager {
        NotificationManager(
            setDelegate: setDelegate,
            requestAuthorization: requestAuthorization,
            setNotificationCategories: setNotificationCategories,
            addNotificationRequest: addNotificationRequest,
            removeDeliveredNotifications: removeDeliveredNotifications,
            makeNotificationID: makeNotificationID,
            notificationSound: notificationSound
        )
    }
}
