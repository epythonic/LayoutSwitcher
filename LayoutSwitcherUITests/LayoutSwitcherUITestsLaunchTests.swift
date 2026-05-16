//
//  LayoutSwitcherUITestsLaunchTests.swift
//  LayoutSwitcherUITests
//
//  Created by Ghenadie Melniciuc on 03.05.2026.
//

import XCTest

final class LayoutSwitcherUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["LAYOUTSWITCHER_UI_TESTING"] = "1"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
