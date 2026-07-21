//
//  OpenCodeClientUITestsLaunchTests.swift
//  OpenCodeClientUITests
//
//  Created by Mauricio Istúriz on 7/19/26.
//

import XCTest

final class OpenCodeClientUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_EMPTY"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding-add-server"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
