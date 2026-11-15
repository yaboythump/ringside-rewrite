import XCTest

final class OfflineCareerTests: XCTestCase {
    @MainActor
    func testNewCareerSurvivesRelaunch() {
        let app = XCUIApplication()
        func button(_ text: String) -> XCUIElement {
            app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        }

        app.launch()
        let career = button("Career")
        guard career.waitForExistence(timeout: 20) else {
            return XCTFail("The bundled game did not load.")
        }
        career.tap()
        let brick = button("Brick Malone")
        XCTAssertTrue(brick.waitForExistence(timeout: 10))
        brick.tap()
        XCTAssertTrue(button("Fight Camp").waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        let continued = button("Continue career")
        XCTAssertTrue(continued.waitForExistence(timeout: 15))
        continued.tap()
        XCTAssertTrue(button("Fight Camp").waitForExistence(timeout: 10))
    }
}
