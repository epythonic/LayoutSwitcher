import Foundation

/// Stores whether the first-run onboarding flow has been completed.
@MainActor
struct OnboardingCompletionStore {
    private static let completedKey = "onboarding.completed"

    private let readCompleted: @MainActor () -> Bool
    private let writeCompleted: @MainActor (Bool) -> Void

    /// Creates a store backed by the provided defaults suite.
    init(defaults: UserDefaults) {
        self.init(
            readCompleted: { defaults.bool(forKey: Self.completedKey) },
            writeCompleted: { value in defaults.set(value, forKey: Self.completedKey) }
        )
    }

    /// Creates a store with injectable persistence closures for deterministic tests.
    init(
        readCompleted: @escaping @MainActor () -> Bool,
        writeCompleted: @escaping @MainActor (Bool) -> Void
    ) {
        self.readCompleted = readCompleted
        self.writeCompleted = writeCompleted
    }

    /// Returns `true` after the user has completed onboarding at least once.
    var isCompleted: Bool {
        readCompleted()
    }

    /// Persists successful onboarding completion.
    func markCompleted() {
        guard !isCompleted else {
            return
        }

        writeCompleted(true)
    }
}
