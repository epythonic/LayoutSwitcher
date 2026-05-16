import ServiceManagement
import Testing
@testable import LayoutSwitcher

@MainActor
struct LaunchAtLoginManagerTests {
    private enum TestError: Error {
        case failed
    }

    @Test func isEnabledReflectsEnabledServiceStatus() {
        let manager = LaunchAtLoginManager(
            statusProvider: { .enabled },
            registerService: {},
            unregisterService: {}
        )

        #expect(manager.isEnabled)
    }

    @Test func isEnabledIsFalseForNotRegisteredServiceStatus() {
        let manager = LaunchAtLoginManager(
            statusProvider: { .notRegistered },
            registerService: {},
            unregisterService: {}
        )

        #expect(!manager.isEnabled)
    }

    @Test func setEnabledRegistersService() {
        var registerCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { .notRegistered },
            registerService: { registerCount += 1 },
            unregisterService: {}
        )

        #expect(manager.setEnabled(true))
        #expect(registerCount == 1)
    }

    @Test func setEnabledIsNoOpWhenAlreadyEnabled() {
        var registerCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { .enabled },
            registerService: { registerCount += 1 },
            unregisterService: {}
        )

        #expect(manager.setEnabled(true))
        #expect(registerCount == 0)
    }

    @Test func setEnabledReturnsFalseWhenServiceIsNotFound() {
        var registerCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { .notFound },
            registerService: { registerCount += 1 },
            unregisterService: {}
        )

        #expect(!manager.setEnabled(true))
        #expect(registerCount == 0)
    }

    @Test func setEnabledReturnsFalseWhenRegisterThrows() {
        let manager = LaunchAtLoginManager(
            statusProvider: { .notRegistered },
            registerService: { throw TestError.failed },
            unregisterService: {}
        )

        #expect(!manager.setEnabled(true))
    }

    @Test func setDisabledUnregistersService() {
        var unregisterCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { .enabled },
            registerService: {},
            unregisterService: { unregisterCount += 1 }
        )

        #expect(manager.setEnabled(false))
        #expect(unregisterCount == 1)
    }

    @Test func setDisabledIsNoOpWhenAlreadyNotRegistered() {
        var unregisterCount = 0
        let manager = LaunchAtLoginManager(
            statusProvider: { .notRegistered },
            registerService: {},
            unregisterService: { unregisterCount += 1 }
        )

        #expect(manager.setEnabled(false))
        #expect(unregisterCount == 0)
    }

    @Test func setDisabledReturnsFalseWhenUnregisterThrows() {
        let manager = LaunchAtLoginManager(
            statusProvider: { .enabled },
            registerService: {},
            unregisterService: { throw TestError.failed }
        )

        #expect(!manager.setEnabled(false))
    }
}
