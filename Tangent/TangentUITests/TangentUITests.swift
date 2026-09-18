//
//  TangentUITests.swift
//  TangentUITests
//
//  Created by Sierra Bonilla on 18/09/2026.
//

import XCTest

final class TangentUITests: XCTestCase {

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
    func testDiaryNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()
        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 2)
        )

        app.navigationBars["Settings"].buttons.firstMatch.tap()

        let recordTodayButton = app.buttons["Record today’s Tangent"]
        XCTAssertTrue(recordTodayButton.waitForExistence(timeout: 2))
        recordTodayButton.tap()
        XCTAssertTrue(
            app.navigationBars["Record Tangent"].waitForExistence(timeout: 2)
        )

        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(
            app.navigationBars["Insights"].waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
