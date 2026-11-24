import XCTest
final class PlaybackLayoutTests: XCTestCase {
    func testDirectDanmakuToggleWithoutSheetAndPresentationSync() {
        let app = XCUIApplication()
        app.launchArguments = ["--playback-layout-test"]
        app.launch()
        app.buttons["enterPlayback"].tap()
        let toggle = app.buttons["player.danmaku"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let initial = toggle.value as? String
        XCTAssertNotNil(initial, "弹幕开关必须暴露开启/关闭状态")
        toggle.tap()
        // The value is published by the store, so poll instead of reading the same snapshot.
        expectation(for: NSPredicate { _, _ in (toggle.value as? String) != initial }, evaluatedWith: app)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(app.buttons["关闭"].exists)
        XCTAssertTrue(app.buttons["player.settings"].exists)
        let changed = toggle.value as? String
        app.buttons["退出全屏"].tap()
        app.buttons["enterPlayback"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, changed, "重新进入播放页应保留用户选择")
        toggle.tap()
        expectation(for: NSPredicate { _, _ in (toggle.value as? String) == initial }, evaluatedWith: app)
        waitForExpectations(timeout: 8)
    }
    func testLivePlaybackHasNoImportOrEPGOverlay() {
        let app = XCUIApplication()
        app.launchArguments = ["--playback-layout-test", "--live-layout-test"]
        app.launch()
        XCTAssertTrue(app.staticTexts["暂无直播源"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["导入"].isHittable)
        XCTAssertFalse(app.buttons["节目单"].isHittable)
    }
    func testReferenceControlsLockAndAutoHide() {
        let app = XCUIApplication()
        app.launchArguments = ["--playback-layout-test"]
        app.launch()
        XCTAssertTrue(app.buttons["enterPlayback"].waitForExistence(timeout: 15))
        app.buttons["enterPlayback"].tap()
        expectation(for: NSPredicate { _, _ in app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let lock = app.buttons["player.lock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(lock.frame.width, 44)
        XCTAssertGreaterThanOrEqual(lock.frame.height, 44)
        lock.tap()
        XCTAssertTrue(app.buttons["player.unlock"].exists)
        XCTAssertFalse(app.buttons["player.settings"].exists)
        app.buttons["player.unlock"].tap()
        let settings = app.buttons["player.settings"]
        XCTAssertTrue(settings.exists)
        settings.tap()
        XCTAssertTrue(app.staticTexts["播放速度"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["填充画面（裁剪边缘）"].exists)
        app.buttons["关闭面板"].tap()
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Reference controls landscape"; capture.lifetime = .keepAlways; add(capture)
        expectation(for: NSPredicate { _, _ in !app.buttons["player.lock"].exists }, evaluatedWith: app)
        waitForExpectations(timeout: 12)
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
