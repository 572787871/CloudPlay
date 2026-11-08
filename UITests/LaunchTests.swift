import XCTest

final class LaunchTests: XCTestCase {
    func testFirstLaunchAndFourChineseTabs() {
        let app=XCUIApplication()
        app.launchArguments += ["-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["添加服务器"].exists)
        for title in ["云盘","下载","播放","设置"] {
            let tab=app.tabBars.buttons[title]
            XCTAssertTrue(tab.exists)
            tab.tap()
            let screenshot=XCTAttachment(screenshot:app.screenshot())
            screenshot.name="CloudPlay-\(title)";screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
    func testConfigurationFormHasIndependentConnectionTests() {
        let app=XCUIApplication();app.launch()
        app.tabBars.buttons["设置"].tap()
        app.buttons["添加服务器"].tap()
        XCTAssertTrue(app.textFields["HTTPS 服务器地址"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["独立测试云盘连接"].exists)
        app.swipeUp()
        XCTAssertTrue(app.buttons["独立测试下载器连接"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["添加服务器"].exists)
    }
}
