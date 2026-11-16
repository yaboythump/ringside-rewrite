import XCTest

final class OfflineCareerTests: XCTestCase {
    @MainActor
    func testNativeRingBellStartsPlayback() {
        let app = XCUIApplication()
        app.launch()
        let game = app.webViews.firstMatch
        let settings = game.buttons["Settings"]
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
        let brick = button("Brick Malone")
        guard brick.waitForExistence(timeout: 10) else {
            return XCTFail("Wrestler selection did not open after tapping Exhibition.")
        }
        brick.tap()
        let start = button("To the ring")
        guard start.waitForExistence(timeout: 10) else {
            return XCTFail("Exhibition setup did not show the match start button.")
        }
        start.tap()
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
        let game = app.webViews.firstMatch
        func button(_ text: String) -> XCUIElement {
            game.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        }

        app.launch()
        let career = game.buttons["New career"]
        guard career.waitForExistence(timeout: 20) else {
            return XCTFail("The bundled game did not load.")
        }
        career.tap()
        let brick = button("Brick Malone")
        XCTAssertTrue(brick.waitForExistence(timeout: 10))
        brick.tap()
        let replace = game.buttons["Start new career"]
        if replace.waitForExistence(timeout: 2) { replace.tap() }
        XCTAssertTrue(button("Fight Camp").waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        let continued = game.buttons["Continue career"]
        XCTAssertTrue(continued.waitForExistence(timeout: 15))
        continued.tap()
        guard button("Fight Camp").waitForExistence(timeout: 10) else {
            return XCTFail("The saved career did not reopen after tapping Continue career.")
        }

        button("Main menu").tap()
        career.tap()
        brick.tap()
        let keep = game.buttons["Keep my career"]
        XCTAssertTrue(keep.waitForExistence(timeout: 10))
        keep.tap()
        XCTAssertTrue(brick.isHittable)
        brick.tap()
        XCTAssertTrue(replace.waitForExistence(timeout: 10))
        replace.tap()
        let fight = button("To the ring")
        XCTAssertTrue(fight.waitForExistence(timeout: 10))
        XCTAssertTrue(fight.isHittable)
        fight.tap()
        let endTurn = button("End turn")
        XCTAssertTrue(endTurn.waitForExistence(timeout: 10))
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: endTurn)], timeout: 8) == .completed)
    }
}
