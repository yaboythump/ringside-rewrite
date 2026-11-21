import XCTest
import UIKit

final class ControlsTests: XCTestCase {
    func testFoldedLibraryHasPersistentAddGamesButton() {
        let app = XCUIApplication()
        // The library launch flag skips the boot screen without auto-opening a ROM.
        app.launchArguments = ["-RetroDuoUITests"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        let addButton = app.buttons["avydrix-add-games-compact"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15),
                      "Add Games must be available without unfolding or scrolling")
        XCTAssertTrue(addButton.isHittable)
    }

    func testGBALandscapeRetainsTouchControlsAndGameMenu() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-RetroDuoDemoGBA", "-RetroDuoUITests",
            "-avydrix.duo.mode", "auto",
            "-avydrix.gba.landscapeControls", "YES"
        ]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }

        let landscape = app.descendants(matching: .any)
            .matching(identifier: "gba-landscape-with-controls").firstMatch
        XCTAssertTrue(landscape.waitForExistence(timeout: 15),
                      "GBA landscape must show its touch controls alongside the picture")
        XCTAssertTrue(app.buttons["Game menu"].isHittable,
                      "Game menu must remain reachable in landscape")
        XCTAssertTrue(app.buttons["Direction pad"].isHittable)
        XCTAssertTrue(app.buttons["A button"].isHittable)
        XCTAssertTrue(app.buttons["B button"].isHittable)
        XCTAssertTrue(app.buttons["START"].exists)
        XCTAssertTrue(app.buttons["SELECT"].exists)
    }

    func testSNESFaceButtonsStayLargeInPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemoSNES", "-RetroDuoUITests",
                               "-avydrix.duo.mode", "auto"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        let buttons = ["A button", "B button", "X button", "Y button"]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for name in buttons {
                let button = app.buttons[name]
                XCTAssertTrue(button.waitForExistence(timeout: 10), "\(name) disappeared")
                XCTAssertTrue(button.isHittable, "\(name) must be tappable")
                XCTAssertGreaterThanOrEqual(button.frame.width, 43,
                    "\(name) is too small for comfortable tapping")
                XCTAssertGreaterThanOrEqual(button.frame.height, 43,
                    "\(name) is too small for comfortable tapping")
            }
            XCTAssertTrue(app.buttons["L button"].exists)
            XCTAssertTrue(app.buttons["R button"].exists)
            XCTAssertTrue(app.buttons["Game menu"].exists)
            attach(app, "snes-buttons-\(orientation.rawValue)")
        }
    }

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
    func testGameBoyPictureSurvivesRepeatedRotation() {
        checkRotations(demo: "-RetroDuoDemo")
    }

    func testDSPictureSurvivesRepeatedRotation() {
        checkRotations(demo: "-RetroDuoDemoDS")
    }

    private func checkRotations(demo: String) {
        let app = XCUIApplication()
        app.launchArguments = [demo, "-RetroDuoUITests", "-retroDuoTwoPanels", "YES",
                               "-retroDuoOriginalProportions", "NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForCounter("frames", above: 180, in: diagnostics))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait, .landscapeRight, .portrait] {
            let before = counter("frames", diagnostics.label)
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(waitForCounter("frames", above: before + 30, in: diagnostics))
            let panel = app.descendants(matching: .any).matching(identifier: "upperGamePanel").firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(panel.frame.width, app.frame.width * 0.95)
            XCTAssertEqual(panel.frame.height, app.frame.height / 2, accuracy: 4)
            XCTAssertTrue(hasGamePicture(app, frame: panel.frame), "Game picture became black after rotation")
            attach(app, "\(demo)-\(orientation.rawValue)")
        }
    }

    /// Inspect only the game area, so visible controls cannot hide a black renderer.
    private func hasGamePicture(_ app: XCUIApplication, frame: CGRect) -> Bool {
        guard let image = app.screenshot().image.cgImage, app.frame.width > 0 else { return false }
        let sx = CGFloat(image.width) / app.frame.width
        let sy = CGFloat(image.height) / app.frame.height
        let area = frame.insetBy(dx: 12, dy: 12)
        let rect = CGRect(x: (area.minX - app.frame.minX) * sx,
                          y: (area.minY - app.frame.minY) * sy,
                          width: area.width * sx, height: area.height * sy)
        guard let picture = image.cropping(to: rect) else { return false }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32,
                                          bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            let values = bytes.bindMemory(to: UInt8.self)
            return stride(from: 0, to: values.count, by: 4).filter {
                max(values[$0], values[$0 + 1], values[$0 + 2]) > 30
            }.count > 10
        }
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
