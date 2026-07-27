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

        let editServer = app.buttons["Edit Studio Mac"]
        XCTAssertTrue(editServer.waitForExistence(timeout: 5))
        editServer.tap()
        XCTAssertEqual(app.textFields["server-name"].value as? String, "Studio Mac")
        XCTAssertEqual(app.textFields["server-url"].value as? String, "https://fixture.example.com")
        XCTAssertEqual(app.textFields["server-username"].value as? String, "opencode")
        app.buttons["Cancel"].tap()

        let addVoice = app.buttons["Add Voice Server"]
        XCTAssertTrue(addVoice.waitForExistence(timeout: 5))
        addVoice.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["fluidvoice-username"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["fluidvoice-password"].exists)
    }

    @MainActor
    func testNewChatStartsAsDraftWithTargetSelectors() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WORKSPACE"]
        app.launch()

        let newChat = app.buttons["new-chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 5))
        newChat.tap()

        XCTAssertTrue(app.buttons["new-chat-server"].waitForExistence(timeout: 5))
        let projectSelector = app.buttons["new-chat-project"]
        XCTAssertTrue(projectSelector.exists)
        let composer = app.descendants(matching: .any)["chat-composer"]
        XCTAssertTrue(composer.exists)
        XCTAssertFalse(app.buttons["chat-send"].isEnabled)

        projectSelector.tap()
        let project = app.buttons["OpenCodeClient — /Users/demo/Projects/OpenCodeClient"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.tap()

        composer.tap()
        composer.typeText("Draft first prompt")
        let send = app.buttons["chat-send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled)
        send.tap()

        XCTAssertTrue(app.staticTexts["Draft first prompt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["new-chat-project"].exists)
    }

    @MainActor
    func testOrganizeMenuExposesGroupingOptions() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WORKSPACE"]
        app.launch()

        let moreOptions = app.buttons["More Options"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 5))
        moreOptions.tap()

        let organize = app.buttons["Organize"]
        XCTAssertTrue(organize.waitForExistence(timeout: 5))
        organize.tap()

        XCTAssertTrue(app.buttons["Project"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Chronology"].exists)
    }
}
