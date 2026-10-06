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
        XCTAssertFalse(app.buttons["session-fixture-child-session"].exists)
        session.tap()

        let composer = app.descendants(matching: .any)["chat-composer"]
        let assistantMessage = app.descendants(matching: .any)[
            "assistant-message-fixture-assistant-message"
        ]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(assistantMessage.waitForExistence(timeout: 5))
        let finalHeading = app.staticTexts["Foundation complete"]
        XCTAssertTrue(finalHeading.waitForExistence(timeout: 5))
        XCTAssertTrue(finalHeading.isHittable)
        XCTAssertTrue(app.staticTexts["Studio Mac"].exists)
        XCTAssertTrue(app.buttons["chat-new-chat"].exists)
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
        let project = app.buttons["OpenCodeClient"]
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
    func testProjectDisclosureCollapsesAndRestoresSessions() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WORKSPACE"]
        app.launch()

        let disclosure = app.buttons["project-disclosure-fixture-project"]
        let session = app.buttons["session-fixture-session"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertTrue(session.exists)
        disclosure.tap()
        XCTAssertFalse(session.exists)
        disclosure.tap()
        XCTAssertTrue(session.waitForExistence(timeout: 2))
    }

    @MainActor
    func testChatCanJumpToLatestAndOpenReviewScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WORKSPACE"]
        app.launch()
        app.buttons["session-fixture-session"].tap()

        let transcript = app.scrollViews["chat-transcript"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.swipeDown()
        let jump = app.buttons["jump-to-latest"]
        XCTAssertTrue(jump.waitForExistence(timeout: 3))
        jump.tap()
        XCTAssertTrue(app.staticTexts["Foundation complete"].isHittable)

        let menu = app.buttons["Conversation Options"]
        menu.tap()
        XCTAssertTrue(app.buttons["Pin"].exists)
        XCTAssertTrue(app.buttons["Rename"].exists)
        XCTAssertTrue(app.buttons["Changes"].exists)
        XCTAssertTrue(app.buttons["Files"].exists)
        app.buttons["Changes"].tap()
        XCTAssertTrue(app.staticTexts["OpenCodeClient/App/AppShellView.swift"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        menu.tap()
        app.buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["README.md"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["OpenCodeClient"].exists)
    }

    @MainActor
    func testChatNewButtonPreservesServerAndProject() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_WORKSPACE"]
        app.launch()
        app.buttons["session-fixture-session"].tap()
        XCTAssertTrue(app.buttons["chat-new-chat"].waitForExistence(timeout: 5))
        app.buttons["chat-new-chat"].tap()

        XCTAssertEqual(app.buttons["new-chat-server"].value as? String, "Studio Mac")
        XCTAssertEqual(app.buttons["new-chat-project"].value as? String, "OpenCodeClient")
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
