import XCTest
final class PlaybackLayoutTests: XCTestCase {
    func testNativeLandscapeSheetAndPortraitRestoration() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--playback-layout-test"]
        app.launch()
        let enter = app.buttons["enterPlayback"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15)); enter.tap()
        let sheet = app.buttons["openSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(sheet.isHittable); sheet.tap()
        XCTAssertTrue(app.staticTexts["sheetContent"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        XCTAssertTrue(app.buttons["closeSheet"].isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Native landscape sheet"; image.lifetime = .keepAlways; add(image)
        app.buttons["closeSheet"].tap(); app.buttons["exitPlayback"].tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 10))
        expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }
}
