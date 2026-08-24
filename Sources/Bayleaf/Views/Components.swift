import SwiftUI

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.dimText)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardStroke, lineWidth: 1))
    }
}

struct Chip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct GradientButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(enabled ? Color.black.opacity(0.85) : Color.white.opacity(0.35))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(enabled ? AnyShapeStyle(Theme.accentGradient)
                                  : AnyShapeStyle(Color.white.opacity(0.07)))
            )
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct LogoMark: View {
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Theme.accentGradient)
                .frame(width: size, height: size)
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.55, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
        }
    }
}

struct StatusDot: View {
    let ok: Bool
    var body: some View {
        Circle()
            .fill(ok ? Theme.leafA : Color.orange)
            .frame(width: 7, height: 7)
            .shadow(color: ok ? Theme.leafA.opacity(0.8) : .clear, radius: 3)
    }
}

struct ToastView: View {
    @EnvironmentObject var model: AppModel
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            if let url = toast.revealURL {
                Button("Reveal") { model.reveal(url) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.leafB)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule().fill(Color(red: 0.10, green: 0.13, blue: 0.12))
                .shadow(color: .black.opacity(0.5), radius: 14, y: 4)
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var icon: String {
        switch toast.kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }
    private var color: Color {
        switch toast.kind {
        case .success: return Theme.leafA
        case .failure: return .orange
        case .info:    return .cyan
        }
    }
}

struct DropHighlight: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.leafA.opacity(0.08))
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.accentGradient, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.accentGradient)
                Text("Drop to open")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
        }
        .padding(14)
        .allowsHitTesting(false)
    }
}
