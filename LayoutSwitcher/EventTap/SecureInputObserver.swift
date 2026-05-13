import Carbon.HIToolbox
import Foundation
import os

@MainActor
protocol SecureInputPolling: AnyObject {
    func invalidate()
}

extension Timer: SecureInputPolling {}

/// Periodically polls `IsSecureEventInputEnabled()` so the UI can reflect when
/// any process (Loginwindow, Terminal `sudo`, password fields) has hijacked the
/// global event stream — in that mode CGEventTap stops receiving keystrokes.
@MainActor
final class SecureInputObserver {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "SecureInput")

    typealias SecureInputStatusProvider = @MainActor () -> Bool
    typealias PollingTimerFactory = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> any SecureInputPolling

    private let interval: TimeInterval
    private let secureInputStatusProvider: SecureInputStatusProvider
    private let pollingTimerFactory: PollingTimerFactory
    private var timer: (any SecureInputPolling)?

    private(set) var isSecureInputEnabled: Bool = false
    var onChange: ((Bool) -> Void)?

    init(
        interval: TimeInterval = 1.5,
        secureInputStatusProvider: @escaping SecureInputStatusProvider = {
            IsSecureEventInputEnabled()
        },
        pollingTimerFactory: @escaping PollingTimerFactory = { interval, tick in
            let timer = Timer(timeInterval: interval, repeats: true) { _ in
                Task { @MainActor in
                    tick()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            return timer
        }
    ) {
        self.interval = interval
        self.secureInputStatusProvider = secureInputStatusProvider
        self.pollingTimerFactory = pollingTimerFactory
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
