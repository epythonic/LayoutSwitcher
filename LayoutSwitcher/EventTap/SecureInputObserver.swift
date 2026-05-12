import Carbon.HIToolbox
import Foundation
import os

/// Periodically polls `IsSecureEventInputEnabled()` so the UI can reflect when
/// any process (Loginwindow, Terminal `sudo`, password fields) has hijacked the
/// global event stream — in that mode CGEventTap stops receiving keystrokes.
@MainActor
final class SecureInputObserver {
    private static let logger = Logger(subsystem: "GIH.LayoutSwitcher", category: "SecureInput")

    private let interval: TimeInterval
    private var timer: Timer?

    private(set) var isSecureInputEnabled: Bool = false
    var onChange: ((Bool) -> Void)?

    init(interval: TimeInterval = 1.5) {
        self.interval = interval
    }

    /// Begin periodic polling. Idempotent.
    func start() {
        guard timer == nil else { return }
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Cancel polling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let current = IsSecureEventInputEnabled()
        guard current != isSecureInputEnabled else { return }
        isSecureInputEnabled = current
        Self.logger.info("Secure event input \(current ? "ENABLED" : "disabled", privacy: .public)")
        onChange?(current)
    }
}
