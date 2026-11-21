import XCTest

final class ControlsTests: XCTestCase {
    func testNativeControlsAudioAndLayouts() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemo", "-RetroDuoUITests"]
        app.launch()
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        let audio = NSPredicate(format: "label CONTAINS %@", "audio:true")
        expectation(for: audio, evaluatedWith: diagnostics)
        waitForExpectations(timeout: 15)
        sleep(3) // Allow the original test cartridge to finish booting.
        let before = diagnostics.label
        app.buttons["A button"].tap()
        // Parse counters rather than assuming that a rendered press changed the console.
        XCTAssertTrue(waitForCounter("actions", above: counter("actions", before), in: diagnostics))
        let pad = app.buttons["Direction pad"]
        let right = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.5))
        let directions = counter("directions", diagnostics.label)
        right.press(forDuration: 0.25)
        XCTAssertTrue(waitForCounter("directions", above: directions, in: diagnostics))
        let actions = counter("actions", diagnostics.label)
        app.buttons["START"].tap()
        XCTAssertTrue(waitForCounter("actions", above: actions, in: diagnostics))
        app.buttons["Mute sound"].tap()
        XCTAssertTrue(app.buttons["Turn sound on"].exists)
        app.buttons["Turn sound on"].tap()
        XCTAssertTrue(app.buttons["Mute sound"].exists)
        attach(app, "portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["A button"].waitForExistence(timeout: 5))
        let landscapeActions = counter("actions", diagnostics.label)
        app.buttons["B button"].tap()
        XCTAssertTrue(waitForCounter("actions", above: landscapeActions, in: diagnostics))
        attach(app, "landscape")
        app.terminate()
    }
    private func counter(_ key: String, _ text: String) -> Int {
        text.split(separator: " ").first(where: { $0.hasPrefix(key + ":") })
            .flatMap { Int($0.split(separator: ":").last ?? "0") } ?? 0
    }
    private func waitForCounter(_ key: String, above value: Int, in element: XCUIElement) -> Bool {
        let predicate = NSPredicate { _, _ in self.counter(key, element.label) > value }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5) == .completed
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
