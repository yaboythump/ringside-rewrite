import XCTest

final class OfflineCareerTests: XCTestCase {
    @MainActor
    func testNativeRingBellStartsPlayback() {
        let app = XCUIApplication()
        app.launch()
        let game = app.webViews.firstMatch
        let settings = game.buttons["Settings & credits"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()
        let bell = game.buttons["Test ring bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        XCTAssertTrue(game.staticTexts["Ring bell playback started."].waitForExistence(timeout: 10))
    }

    @MainActor
    func testDamageAndEndTurnStayVisibleAfterPlayingCard() {
        let app = XCUIApplication()
        let game = app.webViews.firstMatch
        func button(_ text: String) -> XCUIElement {
            game.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        }

        app.launch()
        let exhibition = button("Exhibition")
        guard exhibition.waitForExistence(timeout: 20) else {
            return XCTFail("The bundled game did not load.")
        }
        exhibition.tap()
        button("Brick Malone").tap()
        button("To the ring").tap()
        let entrance = button("Ring the bell")
        if entrance.waitForExistence(timeout: 2), entrance.isHittable { entrance.tap() }

        let endTurn = button("End turn")
        XCTAssertTrue(endTurn.waitForExistence(timeout: 10))
        let attack = game.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ AND enabled == true", "DMG")
        ).firstMatch
        // The hand is shuffled. A defensive opening can be played through without scrolling.
        for _ in 0..<3 where !attack.waitForExistence(timeout: 2) {
            XCTAssertTrue(game.frame.contains(endTurn.frame))
            endTurn.tap()
        }
        guard attack.waitForExistence(timeout: 4) else {
            return XCTFail("No attack card was dealt.")
        }
        XCTAssertTrue(game.frame.contains(attack.frame))
        attack.tap()

        let damage = game.staticTexts.matching(
            NSPredicate(format: "label MATCHES[c] %@", ".* for [0-9]+.*!.*")
        ).firstMatch
        XCTAssertTrue(damage.waitForExistence(timeout: 5))
        XCTAssertTrue(game.frame.contains(damage.frame))
        XCTAssertTrue(game.frame.contains(endTurn.frame))
    }

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
