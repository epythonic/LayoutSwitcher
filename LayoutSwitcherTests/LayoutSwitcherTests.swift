//
//  LayoutSwitcherTests.swift
//  LayoutSwitcherTests
//
//  Created by Ghenadie Melniciuc on 03.05.2026.
//

import Testing
@testable import LayoutSwitcher

@MainActor
struct LayoutSwitcherTests {

    @Test func supportedLanguagesAreStable() {
        #expect(Set(LanguageID.allCases) == [.en, .ru, .ro, .uk])
    }

}
