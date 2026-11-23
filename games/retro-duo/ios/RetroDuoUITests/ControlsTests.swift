import XCTest
import UIKit

final class ControlsTests: XCTestCase {
    func testAppStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoUITests", "-AvydrixStoreScreenshots", "-avydrix.ambientMotionEnabled", "NO"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["AVYDRIX settings"].waitForExistence(timeout: 15))
        attach(app, "store-01-your-console")
        let shelf = app.descendants(matching: .any)
            .matching(identifier: "avydrix-3d-console-shelf").firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 10))
        app.swipeUp()
        attach(app, "store-02-explore-library")
        app.swipeDown()
        app.buttons["AVYDRIX settings"].tap()
        XCTAssertTrue(app.buttons["avydrix-skin-ultraviolet"].waitForExistence(timeout: 8))
        app.buttons["avydrix-skin-ultraviolet"].tap()
        attach(app, "store-05-make-it-yours")
        app.buttons["Done"].tap()
        // Only the original bundled game is used in promotional captures.
        let game = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Play featured game")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 8))
        game.tap()
        XCTAssertTrue(app.buttons["Game menu"].waitForExistence(timeout: 15))
        attach(app, "store-03-dual-screen-gaming")
        app.buttons["Game menu"].tap()
        XCTAssertTrue(app.staticTexts["COMMAND CENTER"].waitForExistence(timeout: 8))
        attach(app, "store-04-control-everything")
        app.buttons.containing(.staticText, identifier: "QUICK SAVE").firstMatch.tap()
        app.buttons.containing(.staticText, identifier: "SAVE VAULT").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Visual Save Manager"].waitForExistence(timeout: 8))
        attach(app, "store-06-never-lose-your-place")
    }

    func testPlay2ConsoleShelfAndSkins() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoUITests"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        let shelf = app.descendants(matching: .any)
            .matching(identifier: "avydrix-3d-console-shelf").firstMatch
        XCTAssertTrue(shelf.waitForExistence(timeout: 15),
                      "Interactive console shelf should appear in the existing library")
        XCTAssertTrue(app.buttons["avydrix-add-games-compact"].exists)
        app.buttons["AVYDRIX settings"].tap()
        let violet = app.buttons["avydrix-skin-ultraviolet"]
        XCTAssertTrue(violet.waitForExistence(timeout: 8),
                      "Console skins must be available in Settings")
        violet.tap()
        XCTAssertTrue(violet.isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(shelf.exists, "Changing skins must not remove the library")
    }

    func testCommandCenterRetainsResumeAndSaveActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemoGBA", "-RetroDuoUITests"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let menu = app.buttons["Game menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        let center = app.descendants(matching: .any)
            .matching(identifier: "avydrix-command-center").firstMatch
        XCTAssertTrue(center.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["QUICK SAVE"].exists)
        XCTAssertTrue(app.staticTexts["SAVE VAULT"].exists)
        XCTAssertTrue(app.staticTexts["CONTROLS"].exists)
        app.buttons["avydrix-resume-game"].tap()
        XCTAssertTrue(app.buttons["Game menu"].isHittable)
    }

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

    func testSystemToolsAreHiddenFromHomeButAccessibleThroughSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoUITests"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        // Diagnostic carts should not clutter the public storefront.
        XCTAssertFalse(app.staticTexts["SYSTEM TOOLS"].exists)
        XCTAssertTrue(app.staticTexts["GAME LIBRARY"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["avydrix-diagnostic-builtin.testcart"].exists)

        let settings = app.buttons["AVYDRIX settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let tools = app.buttons["avydrix-system-tools-link"]
        // Form rows are created lazily; reach Advanced before querying its link.
        for _ in 0..<6 {
            if tools.exists && tools.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(tools.waitForExistence(timeout: 8),
                      "Advanced System Tools must stay available inside Settings")
        tools.tap()
        XCTAssertTrue(app.staticTexts["Diagnostic cartridges"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["avydrix-diagnostic-builtin.testcart"].exists,
                      "Original built-in test cartridge must still be launchable")
        attach(app, "system-tools-inside-settings")
    }

    func testGBALandscapeRetainsTouchControlsAndGameMenu() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-RetroDuoDemoGBA", "-RetroDuoUITests",
            "-avydrix.duo.mode", "auto",
            "-avydrix.gba.landscapeControls", "YES"
        ]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
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
        XCTAssertTrue(app.buttons["L button"].isHittable)
        XCTAssertTrue(app.buttons["R button"].isHittable)
        XCTAssertTrue(app.buttons["START"].exists)
        XCTAssertTrue(app.buttons["SELECT"].exists)

        // These controls must be in the console shell, NOT on top of gameplay.
        let screen = app.descendants(matching: .any)
            .matching(identifier: "gbaLandscapeGameScreen").firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        for name in ["Direction pad", "A button", "B button", "L button", "R button", "Game menu"] {
            let control = app.buttons[name]
            XCTAssertFalse(control.frame.intersects(screen.frame),
                           "\(name) must not obscure the game screen")
        }
        attach(app, "gba-separate-console-shell")
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

    /// The Genesis picture is wide (320x224); in landscape it must shrink to fit between the
    /// control columns instead of pushing them off the screen.
    func testGenesisLandscapeKeepsControlsOnScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemoGenesis", "-RetroDuoUITests",
                               "-avydrix.duo.mode", "auto"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            // Measure only after the rotation has finished, or buttons already laid out for
            // landscape are compared against the old portrait window and look off-screen.
            XCTAssertTrue(waitForWindow(of: app, landscape: orientation.isLandscape), "rotation did not finish")
            sleep(1)
            let window = app.windows.firstMatch.frame
            let screen = app.descendants(matching: .any)["Game screen"].firstMatch
            for name in ["A button", "B button", "C button", "Direction pad", "START", "MODE"] {
                let button = app.buttons[name]
                XCTAssertTrue(button.waitForExistence(timeout: 10), "\(name) disappeared")
                XCTAssertTrue(window.contains(button.frame), "\(name) is off the screen")
                XCTAssertTrue(button.isHittable, "\(name) must be tappable")
                if orientation != .portrait, screen.exists {
                    XCTAssertFalse(screen.frame.insetBy(dx: 8, dy: 8).intersects(button.frame),
                                   "\(name) must not cover the game")
                }
            }
            attach(app, "genesis-controls-\(orientation.rawValue)")
        }
    }

    /// Move & resize controls: drag the D-pad somewhere new, check it still steers there,
    /// make it bigger, then Reset puts it back.
    func testControlsCanBeMovedResizedAndReset() {
        let app = XCUIApplication()
        // Start from default controls: other tests (store screenshots) resize them, and the
        // argument domain overrides what they saved.
        app.launchArguments = ["-RetroDuoDemo", "-RetroDuoUITests",
                               "-avydrix.controls.gameBoyColor.size", "default",
                               "-avydrix.controls.gameBoyColor.directionOffset", "default",
                               "-avydrix.controls.gameBoyColor.actionOffset", "default",
                               "-avydrix.controls.gameBoyColor.mirrored", "NO",
                               "-avydrix.layout.gameBoyColor", "none"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForCounter("frames", above: 120, in: diagnostics, timeout: 30))
        let pad = app.buttons["Direction pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        let original = pad.frame

        func openEditor() {
            app.buttons["Game menu"].tap()
            // The menu's container identifier covers its tiles, so find the tile by its text.
            let move = app.staticTexts["MOVE CONTROLS"]
            if !move.waitForExistence(timeout: 8) {
                // Show CI what the menu holds instead.
                for line in app.debugDescription.split(separator: "\n") { print("RDDUMP \(line)") }
            }
            XCTAssertTrue(move.exists, "Move controls is in the menu")
            if !move.isHittable { app.swipeUp() }
            move.tap()
            XCTAssertTrue(app.buttons["layout-done"].waitForExistence(timeout: 5), "Edit mode opens")
        }

        openEditor()
        let handle = app.descendants(matching: .any)["layout-dpad"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 70, dy: -90)))
        attach(app, "layout-editing")
        app.buttons["layout-done"].tap()

        let moved = pad.frame
        XCTAssertEqual(moved.midX - original.midX, 70, accuracy: 20, "D-pad moved right")
        XCTAssertEqual(moved.midY - original.midY, -90, accuracy: 20, "D-pad moved up")
        let directions = counter("directions", diagnostics.label)
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.5)).press(forDuration: 0.25)
        XCTAssertTrue(waitForCounter("directions", above: directions, in: diagnostics),
                      "The moved D-pad still steers where it is drawn")

        openEditor()
        app.descendants(matching: .any)["layout-dpad"].firstMatch.tap()
        let slider = app.sliders["layout-size"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "Selecting a control shows its size slider")
        slider.adjust(toNormalizedSliderPosition: 0.9)
        app.buttons["layout-done"].tap()
        XCTAssertGreaterThan(pad.frame.width, original.width * 1.25, "D-pad got bigger")
        attach(app, "layout-moved-and-bigger")

        openEditor()
        app.buttons["layout-reset"].tap()
        app.buttons["layout-done"].tap()
        XCTAssertEqual(pad.frame.midX, original.midX, accuracy: 3, "Reset puts the D-pad back")
        XCTAssertEqual(pad.frame.width, original.width, accuracy: 3, "Reset restores its size")
    }

    func testTrackerReadsTheGameOnTheLowerScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemo", "-RetroDuoUITests",
                               "-avydrix.controls.gameBoyColor.size", "default",
                               "-avydrix.controls.gameBoyColor.directionOffset", "default",
                               "-avydrix.controls.gameBoyColor.mirrored", "NO",
                               "-avydrix.layout.gameBoyColor", "none"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForCounter("frames", above: 120, in: diagnostics, timeout: 30))
        let pad = app.buttons["Direction pad"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        let toggle = app.buttons["avydrix-tracker-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The tracker button is in the top bar")

        // The built-in test cart has a definition: the star's position comes from its RAM.
        let starX = app.descendants(matching: .any)["tracker-stat-Star X"].firstMatch
        func readStarX() -> Int? {
            toggle.tap()
            guard starX.waitForExistence(timeout: 5) else {
                for line in app.debugDescription.split(separator: "\n") { print("RDDUMP \(line)") }
                return nil
            }
            Thread.sleep(forTimeInterval: 0.6) // let the panel refresh
            return (starX.value as? String).flatMap { Int($0) }
        }
        let before = readStarX()
        XCTAssertNotNil(before, "The tracker shows the star's X position")
        XCTAssertFalse(pad.exists, "The tracker takes the controls' place")
        attach(app, "tracker-open")

        toggle.tap()
        XCTAssertTrue(pad.waitForExistence(timeout: 5), "The controls come back")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.84, dy: 0.5)).press(forDuration: 0.8)
        let after = readStarX()
        XCTAssertNotNil(after)
        if let before, let after {
            XCTAssertGreaterThan(after, before, "Moving the star right raises the tracked X position")
        }
        toggle.tap()
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
    }

    func testGoLiveExplainsAConnectionProblem() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemo", "-RetroDuoUITests", "-avydrix.live.service", "custom",
                               "-avydrix.live.server.custom", ""]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        app.buttons["Game menu"].tap()
        let goLive = app.staticTexts["GO LIVE"]
        if !goLive.waitForExistence(timeout: 8) {
            for line in app.debugDescription.split(separator: "\n") { print("RDDUMP \(line)") }
        }
        XCTAssertTrue(goLive.exists, "Go live is in the game menu")
        if !goLive.isHittable { app.swipeUp() }
        goLive.tap()

        let server = app.textFields["live-server"]
        XCTAssertTrue(server.waitForExistence(timeout: 8), "The live stream setup opens")
        server.tap()
        server.typeText("rtmp://127.0.0.1:9/app")
        let key = app.secureTextFields["live-key"]
        XCTAssertTrue(key.exists)
        key.tap()
        key.typeText("ui-test-key")
        attach(app, "live-setup")
        app.buttons["live-go"].tap()
        // Nothing listens on port 9: the sheet must say so instead of hanging.
        let error = app.descendants(matching: .any)["live-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 25), "A failed connection is explained")
        XCTAssertTrue(error.label.contains("127.0.0.1"), "The message names the server: \(error.label)")
        attach(app, "live-error")
    }

    func testWidgetLinkOpensTheGame() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoUITests"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        defer { app.terminate() }
        // What the home screen widget does when tapped: open avydrix://play?id=<game>.
        app.open(URL(string: "avydrix://play?id=builtin.nestestcart")!)
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 20), "The widget's link opens the game")
        XCTAssertTrue(waitForCounter("frames", above: 60, in: diagnostics, timeout: 30), "and it runs")
        attach(app, "widget-link")
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
    func testFloatingThumbstickMovesWhereverTheThumbLands() {
        let app = XCUIApplication()
        app.launchArguments = ["-RetroDuoDemo", "-RetroDuoUITests", "-avydrix.thumbstick", "YES"]
        app.launch()
        defer { app.terminate() }
        let diagnostics = app.staticTexts["rd-diagnostics"]
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 15))
        sleep(3)
        let stick = app.buttons["Thumbstick"]
        XCTAssertTrue(stick.waitForExistence(timeout: 5), "Thumbstick replaces the D-pad when turned on")
        XCTAssertFalse(app.buttons["Direction pad"].exists)
        // Start off-centre (the stick appears under the thumb) and slide right, then left.
        for (start, end) in [(CGVector(dx: 0.3, dy: 0.6), CGVector(dx: 0.75, dy: 0.6)),
                             (CGVector(dx: 0.7, dy: 0.3), CGVector(dx: 0.2, dy: 0.35))] {
            let before = counter("directions", diagnostics.label)
            stick.coordinate(withNormalizedOffset: start)
                .press(forDuration: 0.1, thenDragTo: stick.coordinate(withNormalizedOffset: end),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertTrue(waitForCounter("directions", above: before, in: diagnostics))
        }
        attach(app, "thumbstick")
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
        XCTAssertTrue(waitForCounter("frames", above: 180, in: diagnostics, timeout: 30))
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

    private func waitForWindow(of app: XCUIApplication, landscape: Bool, timeout: TimeInterval = 10) -> Bool {
        let window = app.windows.firstMatch
        let predicate = NSPredicate { _, _ in
            let frame = window.frame
            return frame.width > 0 && (frame.width > frame.height) == landscape
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: window)], timeout: timeout) == .completed
    }
    private func counter(_ key: String, _ text: String) -> Int {
        text.split(separator: " ").first(where: { $0.hasPrefix(key + ":") })
            .flatMap { Int($0.split(separator: ":").last ?? "0") } ?? 0
    }
    private func waitForCounter(_ key: String, above value: Int, in element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { _, _ in self.counter(key, element.label) > value }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
