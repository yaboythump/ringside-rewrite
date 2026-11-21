import SwiftUI

/// The open book. Unfolded iPhone Duo shows a two-page spread with the fold as the spine.
struct ReaderView: View {
    @StateObject private var model: ReaderModel
    @EnvironmentObject private var settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingContents = false
    @State private var showingAppearance = false
    @State private var scrubbing: Double?

    init(book: Book, library: BookLibrary, startAt chapter: Int? = nil) {
        _model = StateObject(wrappedValue: ReaderModel(book: book, library: library, startAt: chapter))
    }

    private var theme: ReaderTheme { settings.theme }

    var body: some View {
        GeometryReader { proxy in
            let layout = PaneLayout.make(size: proxy.size, fold: PaneLayout.fold(in: proxy), mode: settings.spread)
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
            .onChange(of: layout, initial: true) { _, newLayout in model.setLayout(newLayout) }
        }
        .background(theme.backgroundColor.ignoresSafeArea())
        .overlay(alignment: .top) { if model.chromeVisible { topBar.transition(.move(edge: .top).combined(with: .opacity)) } }
        .overlay(alignment: .bottom) { if model.chromeVisible { bottomBar.transition(.move(edge: .bottom).combined(with: .opacity)) } }
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
        .onDisappear { model.save() }
        .accessibilityAction(named: "Next page") { model.next() }
        .accessibilityAction(named: "Previous page") { model.previous() }
    }

    // MARK: Pages

    private func pane(_ index: Int, frame: CGRect, layout: PaneLayout) -> some View {
        let footer: CGFloat = 22
        let pageSize = CGSize(width: frame.width, height: max(100, frame.height - footer))
        let number = model.page + index
        return VStack(spacing: 0) {
            PageWebView(request: model.request(for: index, settingsJSON: settings.json(for: pageSize))) { event in
                model.handle(event, pane: index)
            }
            .frame(width: pageSize.width, height: pageSize.height)
            .accessibilityLabel("Page")
            Text(number < model.pageCount && model.isRevealed ? "\(number + 1) of \(model.pageCount)" : " ")
                .font(.system(size: 11, weight: .medium, design: .serif))
                .monospacedDigit()
                .foregroundStyle(theme.textColor.opacity(0.4))
                .frame(width: frame.width, height: footer, alignment: .top)
                .allowsHitTesting(false)
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 4) {
            Button { model.save(); dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Library")
            VStack(spacing: 1) {
                Text(model.book.title).font(.system(size: 15, weight: .semibold, design: .serif)).lineLimit(1)
                Text(model.chapterTitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            Button { showingContents = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Contents")
            Button { showingAppearance = true } label: {
                Image(systemName: "textformat.size").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Appearance")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Slider(value: Binding(get: { scrubbing ?? model.progress }, set: { scrubbing = $0 }),
                   in: 0...1) { editing in
                if !editing, let value = scrubbing {
                    model.jump(toProgress: value)
                    scrubbing = nil
                }
            }
            HStack {
                Text(scrubbing == nil ? model.chapterTitle : "Go to \(Int((scrubbing ?? 0) * 100))%")
                    .lineLimit(1)
                Spacer()
                Text("\(Int((scrubbing ?? model.progress) * 100))%").monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
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
