import SwiftUI

/// Settings › RetroAchievements: sign in or out.
struct AchievementsAccountSection: View {
    @ObservedObject private var achievements = RetroAchievements.shared
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        Section {
            if let player = achievements.player {
                LabeledContent("Signed in as", value: player)
                LabeledContent("Points", value: achievements.score.formatted())
                Button("Sign out", role: .destructive) { achievements.signOut() }
                    .accessibilityIdentifier("avydrix-ra-sign-out")
            } else {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("avydrix-ra-username")
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("avydrix-ra-password")
                HStack {
                    Button("Sign in") {
                        achievements.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
                        password = ""
                    }
                    .disabled(username.isEmpty || password.isEmpty || achievements.signingIn || !achievements.available)
                    if achievements.signingIn {
                        Spacer()
                        ProgressView()
                    }
                }
                if let error = achievements.signInError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Link("Make a free account", destination: URL(string: "https://retroachievements.org/createaccount.php")!)
                    .font(.caption)
            }
        } header: {
            Text("RetroAchievements")
        } footer: {
            Text("Earn achievements in games RetroAchievements.org knows. Unlocks pop up while you play and count toward your profile. Casual mode, so rewind, cheats and save states still work. Your password is only used to sign in; the app keeps a sign-in token in the Keychain.")
        }
    }
}

/// The open game's achievements (command center › ACHIEVEMENTS).
struct AchievementsSheet: View {
    @ObservedObject private var achievements = RetroAchievements.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let progress = achievements.progress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(progress.title)
                                .font(.headline)
                            ProgressView(value: Double(progress.earned), total: Double(max(progress.total, 1)))
                            Text("\(progress.earned) of \(progress.total) earned · \(progress.points) of \(progress.totalPoints) points")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        ForEach(achievements.achievements) { achievement in
                            AchievementRow(achievement: achievement)
                        }
                    }
                } else {
                    Section {
                        Text(achievements.gameStatus
                             ?? (achievements.player == nil
                                 ? "Sign in to RetroAchievements in Settings to earn achievements."
                                 : "This game has no RetroAchievements."))
                            .foregroundStyle(.secondary)
                    }
                    if achievements.player == nil {
                        AchievementsAccountSection()
                    }
                }
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { achievements.refreshList() }
        }
    }
}

private struct AchievementRow: View {
    let achievement: RetroAchievements.Achievement

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: achievement.badge) { image in
                image.resizable().interpolation(.none)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.25))
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .saturation(achievement.unlocked ? 1 : 0)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(achievement.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(achievement.points)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Text(achievement.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !achievement.unlocked && !achievement.progress.isEmpty {
                    Text(achievement.progress)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(achievement.unlocked ? 1 : 0.75)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(achievement.title), \(achievement.unlocked ? "earned" : "locked"), \(achievement.points) points")
    }
}
