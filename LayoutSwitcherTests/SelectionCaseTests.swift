import Testing
@testable import LayoutSwitcher

@MainActor
struct SelectionCaseTests {
    @Test func cyclesLowerUpperTitleForLatin() {
        #expect(SelectionCase.cycled("hello world") == "HELLO WORLD")
        #expect(SelectionCase.cycled("HELLO WORLD") == "Hello World")
        #expect(SelectionCase.cycled("Hello World") == "hello world")
    }

    @Test func cyclesLowerUpperTitleForCyrillic() {
        #expect(SelectionCase.cycled("привет") == "ПРИВЕТ")
        #expect(SelectionCase.cycled("ПРИВЕТ") == "Привет")
        #expect(SelectionCase.cycled("Привет") == "привет")
    }

    @Test func returnsNilWhenNothingToChange() {
        #expect(SelectionCase.cycled("12345") == nil) // no cased letters
        #expect(SelectionCase.cycled("") == nil)
    }
}
