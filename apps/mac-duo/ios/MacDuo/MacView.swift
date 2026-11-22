import SwiftUI

/// The running Mac. Half-folded on iPhone Duo, the Mac's screen sits above the
/// fold and the trackpad and keys below it, like a PowerBook. Held flat in
/// portrait you get the same stack; in landscape the screen fills the display.
struct MacView: View {
    @EnvironmentObject private var library: MacLibrary
    @ObservedObject private var session = MacSession.shared
    @StateObject private var modifiers = ModifierState()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var hinge = HingeState()
    @State private var showsKeyboard = false
    @State private var confirmRestart = false
    @AppStorage("touchMode") private var touchModeRaw = ScreenTouchMode.direct.rawValue
    @AppStorage("smoothScreen") private var smooth = true
    @AppStorage("trackpadSpeed") private var trackpadSpeed = 1.0

    private var touchMode: ScreenTouchMode { ScreenTouchMode(rawValue: touchModeRaw) ?? .direct }
    private var fakeFold: Bool { ProcessInfo.processInfo.arguments.contains("-MacDuoFakeFold") }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            Group {
                if hinge.isHalfOpen || fakeFold {
                    folded(geo.size)
                } else if landscape && !showsKeyboard {
                    wide
                } else {
                    tall
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.ignoresSafeArea())
        .background(KeyCapture(showsKeyboard: $showsKeyboard, isActive: scenePhase == .active, modifiers: modifiers).frame(width: 1, height: 1))
        .modifier(HingeReader(state: $hinge))
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { session.resume() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.resume() } else { session.pause() }
        }
        .alert("Restart the Mac?", isPresented: $confirmRestart) {
            Button("Restart", role: .destructive) { session.restart() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Like pressing the reset switch: anything not saved on the Mac is lost.")
        }
        .alert(session.message ?? "", isPresented: Binding(get: { session.message != nil }, set: { if !$0 { session.message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Layouts

    /// iPhone Duo half-open: screen above the fold, controls below.
    private func folded(_ size: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                screen
                if session.state == MVStatePoweredOff { poweredOff.frame(maxWidth: .infinity, maxHeight: .infinity) }
                toolbar.padding(8)
            }
            .frame(height: size.height / 2)
            controls
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .frame(height: size.height / 2)
                .background(Color(.systemGroupedBackground))
        }
        .ignoresSafeArea()
    }

    /// Landscape: the screen as big as it gets, with the toolbar floating.
    private var wide: some View {
        ZStack(alignment: .topLeading) {
            screen.ignoresSafeArea()
            toolbar.padding(10)
            if session.state == MVStatePoweredOff { poweredOff }
        }
    }

    /// Portrait: toolbar, screen, then trackpad and keys.
    private var tall: some View {
        VStack(spacing: 10) {
            toolbar.padding(.horizontal, 12)
            ZStack {
                screen
                if session.state == MVStatePoweredOff { poweredOff }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            controls.padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var screen: some View {
        MacScreen(touchMode: touchMode, smooth: smooth)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if !showsKeyboard {
                Trackpad(sensitivity: trackpadSpeed)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer(minLength: 0)
            }
            KeyBar(modifiers: modifiers, showsKeyboard: $showsKeyboard)
        }
    }

    private var poweredOff: some View {
        VStack(spacing: 12) {
            Text("The Mac is shut down").font(.headline).foregroundStyle(.white)
            Button("Turn On") { session.restart() }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                session.pause()
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Library")

            Menu {
                Section("Insert a disk") {
                    let available = library.disks.filter { !session.isInserted($0.url) }
                    if available.isEmpty {
                        Text("All your disks are in")
                    }
                    ForEach(available) { disk in
                        Button {
                            session.insert(disk.url)
                        } label: {
                            Label("\(disk.name) (\(disk.sizeText))", systemImage: disk.isFloppy ? "opticaldiscdrive" : "internaldrive")
                        }
                    }
                }
                Text("To eject, drag a disk to the Trash on the Mac, or choose Eject from its Special menu.")
            } label: {
                Image(systemName: "opticaldiscdrive")
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Disks")

            Menu {
                Picker("Speed", selection: $session.speed) {
                    ForEach(MacSession.Speed.allCases) { Text($0.label).tag($0) }
                }
                Picker("Touching the screen", selection: $touchModeRaw) {
                    ForEach(ScreenTouchMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Trackpad speed", selection: $trackpadSpeed) {
                    Text("Slow").tag(0.6)
                    Text("Normal").tag(1.0)
                    Text("Fast").tag(1.6)
                }
                Toggle("Smooth screen", isOn: $smooth)
                Toggle("Mute", isOn: $session.muted)
                Divider()
                Button("Interrupt (debugger switch)") { session.interrupt() }
                Button("Restart…", role: .destructive) { confirmRestart = true }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Settings")
            Spacer()
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }
}
