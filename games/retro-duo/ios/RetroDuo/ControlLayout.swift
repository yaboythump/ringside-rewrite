// AVYDRIX Play - move and resize the on-screen controls.
// Copyright 2026 CT Network Studios. GPL v3 or later.
import SwiftUI

/// One group of on-screen controls that can be moved and resized as a piece.
enum ControlGroup: String, CaseIterable, Codable {
    case dpad, buttons, menu, select, start

    var title: String {
        switch self {
        case .dpad: return "D-pad"
        case .buttons: return "Buttons"
        case .menu: return "Start / Select"
        case .select: return "Select"
        case .start: return "Start"
        }
    }
}

/// Where a group sits relative to its automatic place, and how big it is.
struct ControlPlacement: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var scale: Double = 1

    static let scaleRange: ClosedRange<Double> = 0.6...1.8
}

/// The player's control placements for one system. Each screen arrangement ("portrait",
/// "tabletop", "landscape", "ds-panels", "ds-landscape") keeps its own, so moving the D-pad
/// in portrait doesn't disturb landscape. Saved in UserDefaults under
/// avydrix.layout.<system>.
@MainActor
final class ControlLayout: ObservableObject {
    let system: GameSystem
    @Published var editing = false
    @Published var selected: ControlGroup?
    /// The arrangement on screen while editing (Reset and the size slider act on it).
    @Published var arrangement = ""
    @Published private var placements: [String: ControlPlacement]

    private var key: String { "avydrix.layout.\(system.rawValue)" }

    init(system: GameSystem) {
        self.system = system
        if let data = UserDefaults.standard.data(forKey: "avydrix.layout.\(system.rawValue)"),
           let saved = try? JSONDecoder().decode([String: ControlPlacement].self, from: data) {
            placements = saved
        } else {
            placements = [:]
        }
    }

    func placement(_ group: ControlGroup, in arrangement: String) -> ControlPlacement {
        placements["\(arrangement).\(group.rawValue)"] ?? ControlPlacement()
    }

    func set(_ placement: ControlPlacement, for group: ControlGroup, in arrangement: String) {
        var placement = placement
        placement.scale = min(max(placement.scale, ControlPlacement.scaleRange.lowerBound),
                              ControlPlacement.scaleRange.upperBound)
        placements["\(arrangement).\(group.rawValue)"] = placement == ControlPlacement() ? nil : placement
        save()
    }

    func hasChanges(in arrangement: String) -> Bool {
        placements.keys.contains { $0.hasPrefix(arrangement + ".") }
    }

    func reset(_ arrangement: String) {
        placements = placements.filter { !$0.key.hasPrefix(arrangement + ".") }
        selected = nil
        save()
    }

    private func save() {
        if placements.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(placements) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

extension View {
    /// Lets the player move and resize this group of controls in edit mode.
    /// `area` is the whole screen, which keeps a group from being dragged out of reach.
    func placed(_ group: ControlGroup, _ arrangement: String, layout: ControlLayout, area: CGSize) -> some View {
        modifier(PlacedControl(layout: layout, group: group, arrangement: arrangement, area: area))
    }
}

private struct PlacedControl: ViewModifier {
    @ObservedObject var layout: ControlLayout
    let group: ControlGroup
    let arrangement: String
    let area: CGSize
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1

    func body(content: Content) -> some View {
        let placement = layout.placement(group, in: arrangement)
        let scale = clampedScale(placement.scale * pinch)
        let offset = clampedOffset(CGSize(width: placement.x + drag.width, height: placement.y + drag.height))
        let isSelected = layout.editing && layout.selected == group
        content
            // While editing, the controls don't press: touches move them instead.
            .allowsHitTesting(!layout.editing)
            .overlay {
                if layout.editing {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Theme.accent : .white.opacity(0.55),
                                      style: StrokeStyle(lineWidth: isSelected ? 3 : 1.5, dash: isSelected ? [] : [6, 4]))
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(isSelected ? 0.16 : 0.06)))
                        .padding(-6)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(placement).simultaneously(with: pinchGesture(placement)))
                        .onTapGesture { layout.selected = group }
                        .accessibilityElement()
                        .accessibilityLabel("Move \(group.title)")
                        .accessibilityIdentifier("layout-\(group.rawValue)")
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .zIndex(isSelected ? 1 : 0)
            .onAppear { if layout.editing { layout.arrangement = arrangement } }
            .onChange(of: layout.editing) { _, editing in if editing { layout.arrangement = arrangement } }
    }

    private func dragGesture(_ placement: ControlPlacement) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                layout.selected = group
                drag = value.translation
            }
            .onEnded { value in
                let moved = clampedOffset(CGSize(width: placement.x + value.translation.width,
                                                 height: placement.y + value.translation.height))
                var updated = layout.placement(group, in: arrangement)
                updated.x = moved.width
                updated.y = moved.height
                layout.set(updated, for: group, in: arrangement)
                drag = .zero
            }
    }

    private func pinchGesture(_ placement: ControlPlacement) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                layout.selected = group
                pinch = value.magnification
            }
            .onEnded { value in
                var updated = layout.placement(group, in: arrangement)
                updated.scale = clampedScale(updated.scale * value.magnification)
                layout.set(updated, for: group, in: arrangement)
                pinch = 1
            }
    }

    private func clampedScale(_ scale: Double) -> Double {
        min(max(scale, ControlPlacement.scaleRange.lowerBound), ControlPlacement.scaleRange.upperBound)
    }

    /// Far enough to cross the screen, never so far that a group leaves it.
    private func clampedOffset(_ offset: CGSize) -> CGSize {
        let maxX = max(40, area.width * 0.8), maxY = max(40, area.height * 0.8)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}

/// The bar shown while editing: what to do, the selected group's size, Reset and Done.
struct ControlLayoutEditBar: View {
    @ObservedObject var layout: ControlLayout
    let done: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(layout.selected.map { "\($0.title) selected. Drag to move, pinch or slide to resize." }
                 ?? "Drag any control to move it. Pinch or tap one to resize it.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let group = layout.selected {
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
                    Slider(value: Binding(
                        get: { layout.placement(group, in: layout.arrangement).scale },
                        set: { scale in
                            var updated = layout.placement(group, in: layout.arrangement)
                            updated.scale = scale
                            layout.set(updated, for: group, in: layout.arrangement)
                        }), in: ControlPlacement.scaleRange)
                    .tint(Theme.accent)
                    .accessibilityLabel("\(group.title) size")
                    .accessibilityIdentifier("layout-size")
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.white.opacity(0.7))
                }
            }
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    layout.reset(layout.arrangement)
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!layout.hasChanges(in: layout.arrangement))
                .accessibilityIdentifier("layout-reset")
                Button {
                    layout.selected = nil
                    done()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .accessibilityIdentifier("layout-done")
            }
        }
        .padding(14)
        .frame(maxWidth: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
