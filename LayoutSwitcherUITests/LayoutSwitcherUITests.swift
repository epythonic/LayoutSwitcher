//
//  LayoutSwitcherUITests.swift
//  LayoutSwitcherUITests
//
//  Created by Ghenadie Melniciuc on 03.05.2026.
//

import XCTest

final class LayoutSwitcherUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testDetectionCorrectionTogglesAreVisibleInSettings() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LAYOUTSWITCHER_UI_TESTING"] = "1"
        app.launchEnvironment["LAYOUTSWITCHER_UI_TESTING_OPEN_SETTINGS"] = "1"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["settings.toggle.correct-duplicate-letters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings.toggle.correct-double-capitals"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.descendants(matching: .any)["settings.toggle.correct-common-typos"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.descendants(matching: .any)["settings.toggle.auto-russian-yo"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.descendants(matching: .any)["settings.toggle.sound-feedback"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.descendants(matching: .any)["settings.toggle.visual-feedback"].waitForExistence(timeout: 1))
    }
}
