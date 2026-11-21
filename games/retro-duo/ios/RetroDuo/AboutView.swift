import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var license: String {
        guard let url = Bundle.main.url(forResource: "SameBoy-LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Retro Duo plays Game Boy and Game Boy Color games on iPhone, with a layout made for iPhone Duo: fold it halfway and the game sits on the top half with the controls below.")
                    Text("Retro Duo doesn't include or sell any commercial games. Add only games you own or that their creators share freely.")
                    Text("Game controllers work too. The right face button is A, the bottom one is B, Menu is START and Options is SELECT.")
                    Divider()
                    Text("Emulation by SameBoy")
                        .font(.headline)
                    Text("Retro Duo uses the SameBoy emulator core and its Game Boy Color start-up program, by Lior Halphon and contributors.")
                    Text(license)
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
