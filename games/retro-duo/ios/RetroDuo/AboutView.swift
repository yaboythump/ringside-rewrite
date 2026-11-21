import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var license: String { text("SameBoy-LICENSE") }

    private func text(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Retro Duo plays NES, Game Boy, Game Boy Color and Nintendo DS games on iPhone, with layouts made for iPhone Duo: fold it halfway and the game sits on the top half with the controls below. DS games put the top screen above the fold and the touch screen below it.")
                    Text("Retro Duo doesn't include or sell any commercial games. Add only games you own or that their creators share freely.")
                    Text("Game controllers work too. The right face button is A, the bottom one is B, Menu is START and Options is SELECT.")
                    Divider()
                    Text("Emulation by SameBoy")
                        .font(.headline)
                    Text("Retro Duo uses the SameBoy emulator core and its Game Boy Color start-up program, by Lior Halphon and contributors.")
                    Text(license)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("NES emulation by Nestopia")
                        .font(.headline)
                    Text("Retro Duo uses the Nestopia UE emulator core by Martin Freij, R. Belmont, R. Danbrook and contributors, free software under the GNU General Public License, version 2 or later.")
                    Text(text("Nestopia-LICENSE"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Divider()
                    Text("Nintendo DS emulation by melonDS")
                        .font(.headline)
                    Text("Retro Duo uses the melonDS emulator core by the melonDS team, with its free replacement BIOS, so no Nintendo system files are needed. melonDS is free software under the GNU General Public License, version 3 or later, and so is Retro Duo. The full source code, including any changes, is at github.com/yaboythump/ringside-rewrite.")
                    Text(text("melonDS-LICENSE"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
