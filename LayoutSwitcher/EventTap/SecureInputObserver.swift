import Carbon.HIToolbox
import Foundation
import os

/// Invalidation handle for secure-input polling.
@MainActor
protocol SecureInputPolling: AnyObject {
    /// Stops the active polling resource.
    func invalidate()
}

extension Timer: SecureInputPolling {}

/// Periodically polls `IsSecureEventInputEnabled()` so the UI can reflect when
/// any process (Loginwindow, Terminal `sudo`, password fields) has hijacked the
/// global event stream — in that mode CGEventTap stops receiving keystrokes.
@MainActor
final class SecureInputObserver {
    private static let logger = Logger(subsystem: "GM.LayoutSwitcher", category: "SecureInput")

    typealias SecureInputStatusProvider = @MainActor () -> Bool
    typealias PollingTimerFactory = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> any SecureInputPolling

    private let interval: TimeInterval
    private let secureInputStatusProvider: SecureInputStatusProvider
    private let pollingTimerFactory: PollingTimerFactory
    private var timer: (any SecureInputPolling)?

    private(set) var isSecureInputEnabled: Bool = false
    var onChange: (@MainActor (Bool) -> Void)?

    /// Creates observer backed by Carbon secure-input status and a run-loop timer.
    convenience init(interval: TimeInterval = 1.5) {
        self.init(
            interval: interval,
            secureInputStatusProvider: {
                IsSecureEventInputEnabled()
            },
            pollingTimerFactory: Self.makePollingTimer(interval:tick:)
        )
    }

    /// Creates observer with injectable system-boundary closures for deterministic tests.
    init(
        interval: TimeInterval = 1.5,
        secureInputStatusProvider: @escaping SecureInputStatusProvider,
        pollingTimerFactory: @escaping PollingTimerFactory
    ) {
        self.interval = interval
        self.secureInputStatusProvider = secureInputStatusProvider
        self.pollingTimerFactory = pollingTimerFactory
    }

    private static func makePollingTimer(
        interval: TimeInterval,
        tick: @escaping @MainActor () -> Void
    ) -> any SecureInputPolling {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Begin periodic polling. Idempotent.
    func start() {
        guard timer == nil else { return }
        poll()
        timer = pollingTimerFactory(interval) { [weak self] in
            self?.poll()
        }
    }

    /// Cancel polling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = secureInputStatusProvider()
        guard current != isSecureInputEnabled else { return }
        isSecureInputEnabled = current
        Self.logger.info("Secure event input \(current ? "ENABLED" : "disabled", privacy: .public)")
        onChange?(current)
    }
}
