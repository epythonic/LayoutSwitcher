import Testing
@testable import LayoutSwitcher

@MainActor
struct OnboardingCompletionStoreTests {
    @Test func isCompletedReadsInjectedStorage() {
        var completed = false
        let store = OnboardingCompletionStore(
            readCompleted: { completed },
            writeCompleted: { completed = $0 }
        )

        #expect(!store.isCompleted)

        completed = true

        #expect(store.isCompleted)
    }

    @Test func markCompletedWritesTrue() {
        var writes: [Bool] = []
        let store = OnboardingCompletionStore(
            readCompleted: { false },
            writeCompleted: { writes.append($0) }
        )

        store.markCompleted()

        #expect(writes == [true])
    }
}
