import XCTest

final class OpenCodeClientUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testEmptyFixtureStartsOnboarding() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_EMPTY"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding-add-server"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testWorkspaceFixtureOpensConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WORKSPACE"]
        app.launch()

        let session = app.buttons["session-fixture-session"]
        XCTAssertTrue(session.waitForExistence(timeout: 5))
        session.tap()

        let composer = app.descendants(matching: .any)["chat-composer"]
        let assistantMessage = app.descendants(matching: .any)[
            "assistant-message-fixture-assistant-message"
        ]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 5))

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["fluidvoice-username"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["fluidvoice-password"].exists)
    }
}
