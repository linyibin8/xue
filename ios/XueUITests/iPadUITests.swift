import XCTest

final class iPadUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testIPadTour() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 12), "登录邮箱框未出现")
        email.tap()
        email.typeText("ipadqa@evowit.com")
        let pw = app.secureTextFields.firstMatch
        pw.tap()
        pw.typeText("ipadqa2026")
        app.buttons["登录"].firstMatch.tap()

        // 等待认证后的 iPad 外壳：侧栏导航标题 "知进伴学" 或 Learn composer
        let shell = app.staticTexts["知进伴学"].firstMatch
        let send = app.buttons["ipad-composer-send"].firstMatch
        let ok = shell.waitForExistence(timeout: 25) || send.waitForExistence(timeout: 5)
        sleep(2)
        snap(app, "01-postlogin")
        XCTAssertTrue(ok, "登录后未进入 iPad 主界面")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        snap(app, "02-learn-landscape")

        for (key, name) in [("history","03-history"),("mistakes","04-mistakes"),("memory","05-memory"),("settings","06-settings")] {
            let item = app.descendants(matching: .any)["ipad-section-\(key)"].firstMatch
            if item.waitForExistence(timeout: 6) {
                item.tap(); sleep(3); snap(app, name)
            } else {
                snap(app, "\(name)-NOTFOUND")
            }
        }
    }
}
