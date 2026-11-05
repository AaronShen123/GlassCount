import XCTest

/// Drives the real app. Each test launches with an isolated data dir, so user data is never touched.
final class GlassCountUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        let dir = NSTemporaryDirectory() + "GlassCountUITest-\(UUID().uuidString)"
        app.launchArguments = ["--data-dir", dir, "--no-system-notifications"]
        app.launch()
    }

    private var addButton: XCUIElement { app.buttons["addCountdown"].firstMatch }

    private func addCountdown(named name: String) {
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.click()
        let field = app.textFields["eventTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); field.typeText(name)
        app.buttons["saveEvent"].click()
    }

    func testEmptyStateThenCreateCountdown() {
        XCTAssertTrue(app.descendants(matching: .any)["emptyState"].waitForExistence(timeout: 10))
        addCountdown(named: "Launch Day")
        XCTAssertTrue(app.staticTexts["Launch Day"].waitForExistence(timeout: 5), "new event appears as the featured card")
        XCTAssertFalse(app.descendants(matching: .any)["emptyState"].exists)
    }

    func testEditCountdown() {
        addCountdown(named: "Old Name")
        XCTAssertTrue(app.staticTexts["Old Name"].waitForExistence(timeout: 5))
        app.menuButtons["More actions"].firstMatch.click()
        app.menuItems["Edit…"].click()
        let field = app.textFields["eventTitleField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click(); field.typeKey("a", modifierFlags: .command); field.typeText("New Name")
        app.buttons["saveEvent"].click()
        XCTAssertTrue(app.staticTexts["New Name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Old Name"].exists)
    }

    func testDeleteCountdown() {
        addCountdown(named: "To Delete")
        XCTAssertTrue(app.staticTexts["To Delete"].waitForExistence(timeout: 5))
        app.menuButtons["More actions"].firstMatch.click()
        app.menuItems["Delete…"].click()
        app.sheets.buttons["Delete"].firstMatch.click()
        XCTAssertTrue(app.descendants(matching: .any)["emptyState"].waitForExistence(timeout: 5))
    }

    func testBackgroundSheetOpens() {
        XCTAssertTrue(app.buttons["customizeBackground"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["customizeBackground"].firstMatch.click()
        XCTAssertTrue(app.buttons["chooseBackground"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Restore Default"].exists)
    }

    func testSettingsWindowOpens() {
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.toolbars.buttons["Notifications"].waitForExistence(timeout: 5)
                      || app.radioButtons["Notifications"].waitForExistence(timeout: 5)
                      || app.tabs["Notifications"].waitForExistence(timeout: 5))
    }
}
