//
//  Components.swift
//  E-Merger
//
//  Created by Mr. t.
//

import AppKit
import SwiftUI

// The app's visual language: the icon's road-sign yellow and black on sky blue, rounded
// type, colored tiles, a little confetti. Models stay UI-free (the headless harness compiles them),
// so their colors live here.

enum Brand {
    /// Tint for text and icons: readable on light and dark backgrounds, unlike the yellow.
    static let sky = Color(red: 0.12, green: 0.44, blue: 0.91)
    static let skyDeep = Color(red: 0.04, green: 0.30, blue: 0.72)
    static let signYellow = Color(red: 1.0, green: 0.84, blue: 0.04)
    /// Sign yellow. Text on it is always `ink`.
    static let gradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.86, blue: 0.20), Color(red: 0.98, green: 0.74, blue: 0.0)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.08)
}

extension PullRequestPhase {
    var tint: Color {
        switch self {
        case .conflicted: return .red
        case .needsWork: return .orange
        case .ready: return .green
        case .awaitingMe: return Brand.sky
        case .waiting: return .secondary
        }
    }
}

extension PullRequestFilter {
    var tint: Color {
        switch self {
        case .all: return .orange
        case .awaitingMe: return Brand.sky
        case .ready: return .green
        case .mine: return .pink
        }
    }
}

extension BBParticipantStatus {
    var tint: Color {
        switch self {
        case .approved: return .green
        case .unapproved: return .secondary
        case .needsWork: return .orange
        }
    }
}

/// A PR's state as a small colored tile: the list's first read.
struct PhaseTile: View {
    let phase: PullRequestPhase
    var isBusy = false
    /// `.increased` on a selected row: its accent background would swallow the tint.
    @Environment(\.backgroundProminence) private var prominence

    private var isOnAccent: Bool { prominence == .increased }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOnAccent ? Color.white.opacity(0.22) : phase.tint.opacity(0.16))
            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: phase.systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isOnAccent ? AnyShapeStyle(.white) : AnyShapeStyle(phase.tint))
                    .symbolEffect(.bounce, value: phase)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// Stable colored initials for an account or a person.
struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 24

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .mint, .cyan]

    private var initials: String {
        let letters = name.split(separator: " ").compactMap { $0.first(where: \.isLetter) }
        return String(letters.prefix(2)).uppercased(with: Locale(identifier: "tr_TR"))
    }

    private var color: Color {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Self.palette[sum % Self.palette.count]
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}

/// `feature/x → develop`, truncating in the middle where branch names differ most.
struct BranchFlow: View {
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: 4) {
            Text(from).monospaced().lineLimit(1).truncationMode(.middle)
            Image(systemName: "arrow.right")
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .accessibilityLabel("hedef")
            Text(to).monospaced().lineLimit(1).truncationMode(.middle)
        }
    }
}

/// A number with an icon: comment and open-task counts, approvals.
struct CountLabel: View {
    let text: String
    let systemImage: String
    var help: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text).monospacedDigit()
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
    }
}

/// The primary button: the next thing to do on this screen, and only that.
struct BrandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Brand.gradient, in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// Exactly one button per screen is prominent.
    @ViewBuilder
    func prominent(_ isProminent: Bool) -> some View {
        if isProminent {
            buttonStyle(BrandButtonStyle())
        } else {
            buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    /// The rounded, softly outlined surface every section sits on.
    func card() -> some View {
        background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary.opacity(0.6)))
    }
}

/// Section title + content on a card.
struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

/// The app icon, gently bobbing: the empty states' mascot.
struct Mascot: View {
    var size: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .phaseAnimator(reduceMotion ? [0] : [0, -6]) { view, offset in
                view.offset(y: offset)
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
            .accessibilityHidden(true)
    }
}

/// Brief confirmation of a finished action; a merged PR leaves the screen, so this
/// is the only place its success can be shown.
struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .lineLimit(2)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.gradient, lineWidth: 1.5))
            .shadow(color: Brand.sky.opacity(0.25), radius: 14, y: 5)
    }
}

/// A burst of confetti falling from the top of its frame. Decorative: it takes no
/// input, is hidden from VoiceOver and callers skip it under Reduce Motion.
struct ConfettiView: View {
    private struct Piece {
        let x = Double.random(in: 0...1)
        let delay = Double.random(in: 0...0.5)
        let fall = Double.random(in: 0.45...0.8)
        let sway = Double.random(in: 2...5)
        let spin = Double.random(in: -7...7)
        let width = Double.random(in: 6...11)
        let color: Color = [.yellow, .mint, .pink, .orange, .cyan, Brand.sky].randomElement()!
    }

    static let duration = 2.4
    private let pieces = (0..<110).map { _ in Piece() }
    @State private var start = Date()
    @State private var isFinished = false

    var body: some View {
        Group {
            // Gone once it has fallen: an idle animation timeline would keep burning CPU.
            if !isFinished {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(in: &context, size: size, elapsed: timeline.date.timeIntervalSince(start))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            isFinished = true
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        for piece in pieces {
            let age = elapsed - piece.delay
            guard age > 0 else { continue }
            let y = -20 + age * age * piece.fall * size.height
            let x = piece.x * size.width + sin(age * piece.sway) * 26
            var layer = context
            layer.opacity = min(1, max(0, (Self.duration - elapsed) * 2))
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .radians(age * piece.spin))
            let rect = CGRect(x: -piece.width / 2, y: -3, width: piece.width, height: 6)
            layer.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(piece.color))
        }
    }
}

@MainActor
func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
