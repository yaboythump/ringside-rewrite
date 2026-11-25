import SwiftUI

/// What the cheats screen edits (both game sessions).
@MainActor
protocol CheatHost: ObservableObject {
    var game: Game { get }
    var cheats: [Cheat] { get }
    var rejectedCheats: Set<UUID> { get }
    func updateCheats(_ new: [Cheat])
}

extension EmulatorSession: CheatHost {}
extension DSSession: CheatHost {}

/// Game menu › Cheats: the game's codes with on/off switches, and a form to add one.
struct CheatsSheet<Host: CheatHost>: View {
    @ObservedObject var host: Host
    @Environment(\.dismiss) private var dismiss
    @State private var adding = false
    @State private var name = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                if host.cheats.isEmpty && !adding {
                    Section {
                        Text("No cheats yet for \(host.game.name).")
                            .foregroundStyle(.secondary)
                    }
                }
                if !host.cheats.isEmpty {
                    Section {
                        ForEach(host.cheats) { cheat in
                            row(cheat)
                        }
                        .onDelete { offsets in
                            var cheats = host.cheats
                            cheats.remove(atOffsets: offsets)
                            host.updateCheats(cheats)
                        }
                    } footer: {
                        Text("Swipe left to delete. Cheats can change your save: make a save state first if you're unsure.")
                    }
                }
                if adding {
                    Section {
                        TextField("Name (e.g. Infinite lives)", text: $name)
                            .accessibilityIdentifier("cheat-name")
                        TextField("Code", text: $code, axis: .vertical)
                            .lineLimit(1...8)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("cheat-code")
                        Button("Add cheat") {
                            let cheat = Cheat(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Cheat" : name,
                                              code: code)
                            host.updateCheats(host.cheats + [cheat])
                            name = ""
                            code = ""
                            adding = false
                        }
                        .disabled(CheatCodes.lines(code).isEmpty)
                        .accessibilityIdentifier("cheat-add")
                    } header: {
                        Text("New cheat")
                    } footer: {
                        Text(CheatCodes.help(system: host.game.system.rawValue))
                    }
                } else {
                    Section {
                        Button {
                            adding = true
                        } label: {
                            Label("Add a cheat code", systemImage: "plus.circle.fill")
                        }
                        .accessibilityIdentifier("cheat-new")
                    } footer: {
                        Text(CheatCodes.help(system: host.game.system.rawValue))
                    }
                }
            }
            .navigationTitle("Cheats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ cheat: Cheat) -> some View {
        let rejected = cheat.enabled && host.rejectedCheats.contains(cheat.id)
        return Toggle(isOn: Binding(
            get: { cheat.enabled },
            set: { on in
                var cheats = host.cheats
                if let index = cheats.firstIndex(where: { $0.id == cheat.id }) { cheats[index].enabled = on }
                host.updateCheats(cheats)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cheat.name)
                Text(CheatCodes.lines(cheat.code).joined(separator: "  "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if rejected {
                    Label("This console didn't understand this code", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("cheat-rejected")
                }
            }
        }
        .accessibilityIdentifier("cheat-\(cheat.name)")
    }
}
