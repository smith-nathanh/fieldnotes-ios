//
//  FieldnotesUITests.swift
//  FieldnotesUITests
//
//  Created by Nathan Smith on 6/28/26.
//

import XCTest

final class FieldnotesUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testPrimaryCaptureScreens() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Start Listening"].waitForExistence(timeout: 5))
        attachScreenshot(named: "Listen Idle")

        let photoTab = app.buttons["PHOTO"]
        XCTAssertTrue(photoTab.exists)
        photoTab.tap()
        XCTAssertTrue(app.staticTexts["Search Area"].waitForExistence(timeout: 5))

        let locationAlert = app.alerts.firstMatch
        if locationAlert.waitForExistence(timeout: 2) {
            locationAlert.buttons["Don’t Allow"].tap()
        }

        XCTAssertFalse(app.staticTexts["Choose a photo"].exists)
        attachScreenshot(named: "Photo Idle")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
