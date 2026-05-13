import Foundation

/// Stores whether the first-run onboarding flow has been completed.
@MainActor
struct OnboardingCompletionStore {
    private static let completedKey = "onboarding.completed"

    private let readCompleted: @MainActor () -> Bool
    private let writeCompleted: @MainActor (Bool) -> Void

    init(
        readCompleted: @escaping @MainActor () -> Bool = {
            UserDefaults.standard.bool(forKey: Self.completedKey)
        },
        writeCompleted: @escaping @MainActor (Bool) -> Void = { value in
            UserDefaults.standard.set(value, forKey: Self.completedKey)
        }
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
        writeCompleted(true)
    }
}
