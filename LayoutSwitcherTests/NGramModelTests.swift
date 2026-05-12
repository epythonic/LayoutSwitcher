import Testing
@testable import LayoutSwitcher

@MainActor
struct NGramModelTests {
    let en = NGramModels.english()
    let ru = NGramModels.russian()
    let uk = NGramModels.ukrainian()

    @Test func englishWordScoresHigherInEnglishModel() {
        #expect(en.score("hello") > ru.score("hello"))
        #expect(en.score("world") > ru.score("world"))
        #expect(en.score("the") > ru.score("the"))
    }

    @Test func russianWordScoresHigherInRussianModel() {
        #expect(ru.score("привет") > en.score("привет"))
        #expect(ru.score("слово") > en.score("слово"))
    }

    @Test func ukrainianWordScoresHigherInUkrainianModel() {
        #expect(uk.score("привіт") > en.score("привіт"))
        #expect(uk.score("слово") > en.score("слово"))
    }

    @Test func wrongLayoutTextScoresLowInItsLayout() {
        // ghbdtn typed on EN layout should look improbable in EN.
        let ghbdtn = en.score("ghbdtn")
        let realEnglish = en.score("hello")
        #expect(realEnglish > ghbdtn)
    }

    @Test func wrongLayoutTextScoresLowInRussian() {
        // руддщ typed on RU layout should look improbable in RU.
        let ruddh = ru.score("руддщ")
        let realRussian = ru.score("привет")
        #expect(realRussian > ruddh)
    }

    @Test func emptyWordReturnsNegativeInfinity() {
        #expect(en.score("") == -Double.infinity)
    }
}
