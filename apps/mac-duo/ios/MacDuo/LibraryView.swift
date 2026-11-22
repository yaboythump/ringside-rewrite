import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Set-up screen: the ROM, the disks, and the button that turns the Mac on.
struct LibraryView: View {
    @EnvironmentObject private var library: MacLibrary
    @ObservedObject private var session = MacSession.shared
    @State private var importing = false
    @State private var showsMac = false
    @State private var showsAbout = false
    @State private var newDiskSize: Int?
    @State private var newDiskName = "Untitled"

    var body: some View {
        NavigationStack {
            List {
                startSection
                romSection
                diskSection
                helpSection
            }
            .navigationTitle("Mac Duo")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { importing = true } label: { Label("Add ROM or Disks…", systemImage: "doc.badge.plus") }
                        Menu {
                            Button("800K floppy") { newDiskSize = 819_200 }
                            Button("1.4 MB floppy") { newDiskSize = 1_474_560 }
                            Button("20 MB hard disk") { newDiskSize = 20 * 1_048_576 }
                            Button("100 MB hard disk") { newDiskSize = 100 * 1_048_576 }
                            Button("500 MB hard disk") { newDiskSize = 500 * 1_048_576 }
                        } label: {
                            Label("New Blank Disk", systemImage: "externaldrive.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .refreshable { library.refresh() }
            .fullScreenCover(isPresented: $showsMac) { MacView().environmentObject(library) }
            .sheet(isPresented: $showsAbout) { AboutView() }
            .alert("New disk", isPresented: Binding(get: { newDiskSize != nil }, set: { if !$0 { newDiskSize = nil } })) {
                TextField("Name", text: $newDiskName)
                Button("Create") {
                    if let size = newDiskSize { library.createBlankDisk(named: newDiskName, bytes: size) }
                    newDiskSize = nil
                }
                Button("Cancel", role: .cancel) { newDiskSize = nil }
            } message: {
                Text("Insert it in the Mac and it will offer to initialize it.")
            }
            .alert(library.lastError ?? "", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .alert(session.message ?? "", isPresented: Binding(get: { session.message != nil && !showsMac }, set: { if !$0 { session.message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
        .onAppear { library.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            library.refresh()
        }
        .task {
            if DebugLaunch.autoStart, let rom = library.rom {
                if session.start(rom: rom.url, disks: library.startupDisks) { showsMac = true }
            }
        }
    }

    // MARK: - Sections

    private var startSection: some View {
        Section {
            Button {
                guard let rom = library.rom else { return }
                if session.start(rom: rom.url, disks: library.startupDisks) { showsMac = true }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: session.isStarted ? "play.display" : "power")
                        .font(.system(size: 26, weight: .semibold))
                        .frame(width: 52, height: 52)
                        .background(Color.accentColor.opacity(library.rom?.isUsable == true ? 1 : 0.3),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.isStarted ? "Return to the Mac" : "Turn On the Mac")
                            .font(.headline)
                        Text(startSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(library.rom?.isUsable != true)
        }
    }

    private var startSubtitle: String {
        guard let rom = library.rom, rom.isUsable else { return "Add a Macintosh II ROM first" }
        if session.isStarted { return "Running · \(session.insertedDisks.count) disk(s) in" }
        if let boot = library.startupDisks.first {
            return "\(rom.modelName) · starts from \(boot.deletingPathExtension().lastPathComponent)"
        }
        return "\(rom.modelName) · no disk: you'll see the flashing disk icon"
    }

    private var romSection: some View {
        Section {
            if let rom = library.rom {
                VStack(alignment: .leading, spacing: 4) {
                    Label(rom.modelName, systemImage: rom.isUsable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(rom.isUsable ? Color.primary : Color.orange)
                    Text(rom.url.lastPathComponent + String(format: " · checksum %08X", rom.checksum))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if let problem = rom.problem {
                        Text(problem).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { library.deleteROM() }
                        .disabled(session.isStarted)
                }
            } else {
                Button {
                    importing = true
                } label: {
                    Label("Add a ROM…", systemImage: "memorychip")
                }
            }
        } header: {
            Text("ROM")
        } footer: {
            Text("Mac Duo emulates a Macintosh II and needs a 256 KB ROM from a Mac II, IIx, IIcx or SE/30 that you own. ROMs aren't included.")
        }
    }

    private var diskSection: some View {
        Section {
            if library.disks.isEmpty {
                Button {
                    importing = true
                } label: {
                    Label("Add a disk image…", systemImage: "internaldrive")
                }
            }
            ForEach(library.disks) { disk in
                let order = library.startupDisks.firstIndex(of: disk.url)
                Button {
                    library.toggleStartup(disk)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: disk.isFloppy ? "opticaldiscdrive" : "internaldrive")
                            .font(.title3)
                            .frame(width: 30)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(disk.name).foregroundStyle(Color.primary)
                            Text(order == 0 ? "\(disk.sizeText) · starts the Mac" : disk.sizeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if session.isInserted(disk.url) {
                            Text("In use").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: order != nil ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(order != nil ? Color.accentColor : Color.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { library.delete(disk) }
                        .disabled(session.isInserted(disk.url))
                    if order != 0 {
                        Button("Start From") { library.makeBootDisk(disk) }.tint(.blue)
                    }
                }
            }
        } header: {
            Text("Disks")
        } footer: {
            Text("Ticked disks go in when the Mac turns on; the first one starts it. Swipe a disk to start from it or delete it. You can also drop files into Files › On My iPhone › Mac Duo.")
        }
    }

    private var helpSection: some View {
        Section("Getting started") {
            Label("System 6.0.8 to System 7.5.5 run on the Mac II. A ready-made hard disk image with System 7 is the easiest way to begin.", systemImage: "1.circle")
            Label("Slide on the trackpad to move the pointer. Tap to click, tap then slide to drag, or hold the bar under the pad.", systemImage: "2.circle")
            Label("Fold iPhone Duo halfway: the Mac's screen goes on top and the trackpad and keys below.", systemImage: "3.circle")
        }
        .font(.footnote)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mac Duo").font(.title.bold())
                        Text("A classic Macintosh II (68020, color, 8 MB) for iPhone, built for iPhone Duo.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Emulation") {
                    Text("Powered by Mini vMac by Paul C. Pratt and contributors, used under the GNU General Public License version 2. Mac Duo is free software under the same license; its source is in the ringside-rewrite repository under apps/mac-duo.")
                        .font(.footnote)
                    Text("Mac Duo includes no Apple software. You need a ROM and system software you're entitled to use.")
                        .font(.footnote)
                    Text("Macintosh is a trademark of Apple Inc. Mac Duo is not made or endorsed by Apple.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Controls") {
                    Label("Trackpad: slide, tap to click, double-tap to open", systemImage: "hand.point.up.left")
                    Label("Screen: touch to click, or switch it to trackpad mode in ⚙︎", systemImage: "display")
                    Label("⌘ ⌥ ⌃ ⇧: tap for the next key, double-tap to lock", systemImage: "command")
                    Label("Hardware keyboards work too", systemImage: "keyboard")
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
