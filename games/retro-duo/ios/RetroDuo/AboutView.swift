import SwiftUI

/// Public-facing product information. Keep personal developer account names out of
/// the UI while retaining the notices and source access required by the emulator licenses.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let sourceURL = URL(
        string: "https://github.com/yaboythump/ringside-rewrite/archive/refs/heads/main.zip"
    )

    private func licenseText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "The license file is unavailable in this build."
        }
        return contents
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 14) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 65, height: 65)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.08, green: 0.61, blue: 1.0),
                                        Color(red: 0.45, green: 0.24, blue: 0.94)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: RoundedRectangle(cornerRadius: 17)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AVYDRIX PLAY")
                                .font(.system(size: 21, weight: .black, design: .rounded))
                                .tracking(1)
                            Text("A CTInteractive gaming experience")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Play Without Limits.")
                        .font(.system(size: 23, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Rediscover NES, Game Boy, Game Boy Color, and Nintendo DS games with flexible controls, game covers, and an iPhone Duo-ready layout.")
                        .foregroundStyle(.white.opacity(0.84))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Bring your own games", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("AVYDRIX Play does not sell or distribute commercial games. Import only games you have permission to use. Original bundled games and diagnostics are included separately.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider().overlay(.white.opacity(0.1))

                    Text("OPEN-SOURCE ACKNOWLEDGMENTS")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 0.52, green: 0.84, blue: 1))

                    Text("AVYDRIX Play uses independent open-source emulator projects. Their creators, licenses, and access to corresponding source code remain available below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    licenseSection(
                        "SameBoy • Game Boy and Game Boy Color",
                        credit: "SameBoy and its Game Boy Color start-up program were developed by Lior Halphon and contributors.",
                        file: "SameBoy-LICENSE"
                    )
                    licenseSection(
                        "Nestopia UE • NES",
                        credit: "Nestopia UE was developed by Martin Freij, R. Belmont, R. Danbrook, and contributors. It is free software under GNU GPL version 2 or later.",
                        file: "Nestopia-LICENSE"
                    )
                    licenseSection(
                        "bsnes • Super Nintendo",
                        credit: "bsnes was developed by byuu (Near) and contributors, with its libretro port by the libretro team. It is free software under GNU GPL version 3; its source is at github.com/libretro/bsnes-libretro.",
                        file: "bsnes-LICENSE"
                    )
                    licenseSection(
                        "BlastEm • Genesis, Master System, Game Gear",
                        credit: "BlastEm was developed by Michael Pavone and contributors, with its libretro port by the libretro team. It is free software under GNU GPL version 3 or later; its source is at github.com/libretro/blastem.",
                        file: "BlastEm-LICENSE"
                    )
                    licenseSection(
                        "mGBA • Game Boy Advance",
                        credit: "mGBA was developed by Vicki Pfau and contributors. It is free software under the Mozilla Public License 2.0; its source is at github.com/mgba-emu/mgba.",
                        file: "mGBA-LICENSE"
                    )
                    licenseSection(
                        "melonDS • Nintendo DS",
                        credit: "melonDS was developed by the melonDS team. Its emulator and this distribution include software covered by GNU GPL version 3 or later.",
                        file: "melonDS-LICENSE"
                    )

                    if let sourceURL {
                        Link(destination: sourceURL) {
                            HStack {
                                Label("Download corresponding source code", systemImage: "arrow.down.doc")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundStyle(Color(red: 0.51, green: 0.83, blue: 1))
                            .padding(15)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                        }
                        .accessibilityIdentifier("avydrix-source-download")
                    }

                    Text("Source code is supplied for license compliance. No gaming account or personal developer profile is needed to play.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: 850, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Color(red: 0.018, green: 0.027, blue: 0.065).ignoresSafeArea())
            .navigationTitle("About AVYDRIX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.48, green: 0.82, blue: 1))
    }

    private func licenseSection(_ title: String, credit: String, file: String) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(credit)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text(licenseText(file))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 12)
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(16)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }
}
