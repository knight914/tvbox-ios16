import XCTest
final class PlaybackLayoutTests: XCTestCase {
    func testReferenceControlsLockAndAutoHide() {
        let app = XCUIApplication()
        app.launchArguments = ["--playback-layout-test"]
        app.launch()
        XCTAssertTrue(app.buttons["enterPlayback"].waitForExistence(timeout: 15))
        app.buttons["enterPlayback"].tap()
        expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let lock = app.buttons["锁定"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(lock.frame.width, 44)
        XCTAssertGreaterThanOrEqual(lock.frame.height, 44)
        lock.tap()
        XCTAssertTrue(app.buttons["解锁"].exists)
        XCTAssertFalse(app.buttons["播放速度"].exists)
        app.buttons["解锁"].tap()
        XCTAssertTrue(app.buttons["播放速度"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Reference controls landscape"; capture.lifetime = .keepAlways; add(capture)
        expectation(for: NSPredicate { _, _ in !app.buttons["锁定"].exists }, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        app.otherElements["player.controlSurface"].tap()
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        app.buttons["退出全屏"].tap()
        XCTAssertTrue(app.buttons["enterPlayback"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
    }
    func testNativeLandscapeSheetAndPortraitRestoration() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--playback-layout-test"]
        app.launch()
        let enter = app.buttons["enterPlayback"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        enter.tap()
        let sheet = app.buttons["openSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(sheet.isHittable); sheet.tap()
        XCTAssertTrue(app.staticTexts["sheetContent"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        XCTAssertTrue(app.buttons["closeSheet"].isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Native landscape sheet"; image.lifetime = .keepAlways; add(image)
        app.buttons["closeSheet"].tap(); app.buttons["exitPlayback"].tap()
        XCTAssertTrue(enter.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }
}
