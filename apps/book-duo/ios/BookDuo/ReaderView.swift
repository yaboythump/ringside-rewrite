import SwiftUI

/// The open book. Unfolded iPhone Duo shows a two-page spread with the fold as the spine.
struct ReaderView: View {
    @StateObject private var model: ReaderModel
    @EnvironmentObject private var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingContents = false
    @State private var showingAppearance = false
    @State private var scrubbing: Double?
    @State private var focusMode = false
    @State private var isOpeningCoverVisible = true

    init(book: Book, library: BookLibrary, startAt chapter: Int? = nil) {
        _model = StateObject(wrappedValue: ReaderModel(book: book, library: library, startAt: chapter))
    }

    private var theme: ReaderTheme { settings.theme }

    var body: some View {
        GeometryReader { proxy in
            let layout = PaneLayout.make(size: proxy.size, fold: Self.debugFold(proxy.size) ?? PaneLayout.fold(in: proxy),
                                         mode: settings.spread)
            ZStack(alignment: .topLeading) {
                if layout.kind == .sideBySide, let fold = layout.fold {
                    SpineShade(theme: theme).frame(width: max(fold.width, 2) + 36, height: proxy.size.height)
                        .offset(x: fold.midX - (max(fold.width, 2) + 36) / 2)
                }
                ForEach(Array(layout.frames.enumerated()), id: \.offset) { index, frame in
                    pane(index, frame: frame, layout: layout)
                }
                if !model.isRevealed {
                    ProgressView()
                        .tint(theme.textColor.opacity(0.5))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .onChange(of: layout, initial: true) { _, newLayout in
                model.setLayout(newLayout, rawFold: PaneLayout.fold(in: proxy))
            }
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .overlay(alignment: .top) { if model.chromeVisible { topBar.transition(.move(edge: .top).combined(with: .opacity)) } }
        .overlay(alignment: .topLeading) {
            if !model.chromeVisible && !focusMode { compactLibraryButton.transition(.opacity) }
        }
        .overlay(alignment: .bottom) {
            if model.chromeVisible { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .overlay { cinematicBookOpening }
        .statusBarHidden(!model.chromeVisible)
        .persistentSystemOverlays(model.chromeVisible ? .automatic : .hidden)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .tint(theme.accentColor)
        .sheet(isPresented: $showingContents) {
            ContentsView(model: model)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingAppearance) {
            AppearanceView()
                .presentationDetents([.height(440), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(440)))
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.save() } }
        .onChange(of: model.isRevealed, initial: true) { _, ready in
            guard ready && isOpeningCoverVisible else { return }
            if reduceMotion {
                isOpeningCoverVisible = false
            } else {
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    withAnimation(.easeInOut(duration: 0.8)) { isOpeningCoverVisible = false }
                }
            }
        }
        .onDisappear { model.save() }
        .task {
            // `-BookDuoTurn` turns one page after opening, for simulator checks.
            guard ProcessInfo.processInfo.arguments.contains("-BookDuoTurn") else { return }
            for _ in 0..<40 where !model.isRevealed { try? await Task.sleep(nanoseconds: 250_000_000) }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            model.next()
        }
        .accessibilityAction(named: "Next page") { model.next() }
        .accessibilityAction(named: "Previous page") { model.previous() }
        .accessibilityAction(named: "Show reading controls") {
            withAnimation(.easeInOut(duration: 0.2)) { model.chromeVisible = true }
        }
    }

    /// `-BookDuoFakeFold` pretends there is a 16-point fold down the middle, for simulator checks.
    private static func debugFold(_ size: CGSize) -> CGRect? {
        guard ProcessInfo.processInfo.arguments.contains("-BookDuoFakeFold"), size.width > size.height else { return nil }
        return CGRect(x: size.width / 2 - 8, y: 0, width: 16, height: size.height)
    }

    // MARK: Pages

    private func pane(_ index: Int, frame: CGRect, layout: PaneLayout) -> some View {
        let footer: CGFloat = focusMode ? 0 : 28
        let pageSize = CGSize(width: frame.width, height: max(100, frame.height - footer))
        let number = model.page + index
        let isVisiblePage = number < model.pageCount && model.isRevealed
        let remaining = max(0, model.pageCount - number - 1)
        return VStack(spacing: 0) {
            PageWebView(request: model.request(for: index, settingsJSON: settings.json(for: pageSize))) { event in
                model.handle(event, pane: index)
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .accessibilityLabel("Book page \(number + 1)")
            if !focusMode {
                HStack(spacing: 5) {
                    if isVisiblePage {
                    Text("PAGE \(number + 1) / \(model.pageCount)")
                    Text("·")
                    Text("\(remaining) LEFT IN CHAPTER")
                    }
                }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .monospacedDigit()
            .foregroundStyle(theme.textColor.opacity(0.48))
            .frame(width: frame.width, height: footer, alignment: .center)
            .allowsHitTesting(false)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }

    // A brief cover-to-page reveal, timed to the EPUB layout becoming ready.
    // Reduced Motion skips the effect. No book content or cover is synthesized.
    private var cinematicBookOpening: some View {
        ZStack {
            RadialGradient(colors: [Color(hex: "#2D244F"), Color(hex: "#080D18")],
                           center: .center, startRadius: 20, endRadius: 550)
                .opacity(isOpeningCoverVisible ? 1 : 0)

            VStack(spacing: 27) {
                CoverView(book: model.book)
                    .frame(width: 185, height: 278)
                    .rotation3DEffect(.degrees(isOpeningCoverVisible ? 0 : -75),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: .leading, perspective: 0.7)
                    .scaleEffect(isOpeningCoverVisible ? 1 : 1.18)
                    .shadow(color: .black.opacity(0.48), radius: 30, x: 8, y: 24)

                VStack(spacing: 8) {
                    Text("QUILUNE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(4)
                        .foregroundStyle(Palette.accent)
                    Text("A new chapter awaits")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                }
            }
            .opacity(isOpeningCoverVisible ? 1 : 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(isOpeningCoverVisible)
        .accessibilityHidden(true)
    }

    // MARK: Reader controls

    private var chromeFill: Color {
        theme.isDark ? Color(hex: "#171D30") : Color(hex: "#FFFCF5")
    }

    private var chromeBorder: Color {
        theme.isDark ? Color.white.opacity(0.13) : Color.black.opacity(0.08)
    }

    private func controlIcon(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .frame(width: 40, height: 40)
                .background(theme.textColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var compactLibraryButton: some View {
        Button {
            model.save()
            dismiss()
        } label: {
            Label("Library", systemImage: "chevron.left")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textColor)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(chromeFill.opacity(0.92), in: Capsule())
                .overlay(Capsule().stroke(chromeBorder))
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .padding(.top, 4)
        .accessibilityLabel("Exit book to library")
    }

    private var topBar: some View {
        HStack(spacing: 9) {
            Button {
                model.save()
                dismiss()
            } label: {
                Label("Library", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textColor)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(theme.textColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Exit book to library")

            VStack(alignment: .leading, spacing: 3) {
                Text(model.book.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                Text(model.chapterTitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textColor.opacity(0.58))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controlIcon(settings.theme.isDark ? "sun.max.fill" : "moon.stars.fill",
                        label: settings.theme.isDark ? "Switch to light mode" : "Switch to dark mode") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settings.theme = settings.theme.isDark ? .paper : .night
                }
            }
            controlIcon("list.bullet", label: "Table of contents") { showingContents = true }
            controlIcon("textformat.size", label: "Reading appearance") { showingAppearance = true }
        }
        .padding(9)
        .background(chromeFill.opacity(0.97), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(chromeBorder))
        .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.08), radius: 18, y: 8)
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHAPTER PROGRESS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(theme.accentColor)
                    Text(model.isRevealed ?
                         "\(model.pagesRemainingInChapter) \(model.pagesRemainingInChapter == 1 ? "page" : "pages") left in chapter" :
                         "Preparing your pages")
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            focusMode.toggle()
                            model.chromeVisible = !focusMode
                        }
                    } label: {
                        Label(focusMode ? "EXIT FOCUS" : "FOCUS",
                              systemImage: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(focusMode ? "Exit full screen reading" : "Enter full screen reading")
                    Text(model.isRevealed ? "\(model.currentChapterPage) / \(model.pageCount)" : "···")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.textColor.opacity(0.7))
                }
            }

            HStack(spacing: 12) {
                Button { model.previous() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(theme.textColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!model.isRevealed || model.isAtStart)
                .accessibilityLabel("Previous page")

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { scrubbing ?? model.progress }, set: { scrubbing = $0 }),
                           in: 0...1) { editing in
                        if !editing, let value = scrubbing {
                            model.jump(toProgress: value)
                            scrubbing = nil
                        }
                    }
                    .tint(theme.accentColor)
                    HStack {
                        Text(scrubbing == nil ? "BOOK PROGRESS" : "JUMP TO")
                            .tracking(1)
                        Spacer()
                        Text("\(Int((scrubbing ?? model.progress) * 100))%")
                            .monospacedDigit()
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textColor.opacity(0.5))
                }

                Button { model.next() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(theme.accentColor.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!model.isRevealed || model.isAtEnd)
                .accessibilityLabel("Next page")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(chromeFill.opacity(0.98), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(chromeBorder))
        .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.08), radius: 20, y: 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 5)
    }
}

/// A soft shadow where the pages meet, so the fold reads as a book's spine.
private struct SpineShade: View {
    let theme: ReaderTheme

    var body: some View {
        let dark = theme.isDark
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(dark ? 0.35 : 0.10), location: 0.47),
            .init(color: .black.opacity(dark ? 0.45 : 0.16), location: 0.5),
            .init(color: .black.opacity(dark ? 0.35 : 0.10), location: 0.53),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
        .allowsHitTesting(false)
    }
}

// MARK: - Contents

struct ContentsView: View {
    @ObservedObject var model: ReaderModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
                List {
                    if model.book.manifest.toc.isEmpty {
                        ForEach(model.book.manifest.spine.indices, id: \.self) { index in
                            row(title: "Section \(index + 1)", level: 0, current: index == model.chapter) {
                                model.open(index, at: .start)
                            }
                        }
                    } else {
                        ForEach(model.book.manifest.toc) { entry in
                            row(title: entry.title, level: entry.level, current: entry == model.currentTOCEntry) {
                                model.jump(to: entry)
                            }
                            .id(entry.id)
                        }
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let entry = model.currentTOCEntry { scroller.scrollTo(entry.id, anchor: .center) }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(title: String, level: Int, current: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: level == 0 ? 17 : 15, weight: current ? .semibold : .regular, design: .serif))
                    .foregroundStyle(current ? Color.accentColor : Color.primary)
                    .padding(.leading, CGFloat(min(level, 4)) * 18)
                Spacer()
                if current { Image(systemName: "bookmark.fill").font(.system(size: 12)).foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Appearance

struct AppearanceView: View {
    @EnvironmentObject private var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ForEach(ReaderTheme.allCases) { theme in
                            Button { settings.theme = theme } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle().fill(theme.backgroundColor)
                                        Text("Aa").font(.system(size: 16, weight: .medium, design: .serif))
                                            .foregroundStyle(theme.textColor)
                                    }
                                    .frame(width: 50, height: 50)
                                    .overlay(Circle().stroke(settings.theme == theme ? theme.accentColor : Color.gray.opacity(0.3),
                                                             lineWidth: settings.theme == theme ? 3 : 1))
                                    Text(theme.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(theme.name) theme")
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Text") {
                    HStack {
                        Button { settings.smaller() } label: {
                            Image(systemName: "textformat.size.smaller").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .accessibilityLabel("Smaller text")
                        Text("\(Int((settings.scale * 100).rounded()))%").monospacedDigit().frame(width: 60)
                        Button { settings.larger() } label: {
                            Image(systemName: "textformat.size.larger").frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .accessibilityLabel("Larger text")
                    }
                    .buttonStyle(.borderless)
                    Picker("Font", selection: $settings.font) {
                        ForEach(ReaderFont.allCases) { font in Text(font.name).tag(font) }
                    }
                    Picker("Line spacing", selection: $settings.lineHeight) {
                        Text("Tight").tag(1.3)
                        Text("Normal").tag(1.5)
                        Text("Loose").tag(1.75)
                    }
                    Picker("Margins", selection: $settings.margin) {
                        Text("Narrow").tag(0.6)
                        Text("Normal").tag(1.0)
                        Text("Wide").tag(1.5)
                    }
                    Toggle("Justify text", isOn: $settings.justify)
                }

                Section {
                    Picker("Layout", selection: $settings.spread) {
                        ForEach(SpreadMode.allCases) { mode in Text(mode.name).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Pages")
                } footer: {
                    Text("Two pages shows a spread whenever iPhone Duo is unfolded or the screen is wide, with the fold as the spine.")
                }
            }
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
