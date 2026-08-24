import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LogoMark()
                Text("Bayleaf")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
            }
            .padding(.leading, 84)
            .padding(.trailing, 22)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 18) {
                ZStack {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 74))
                        .foregroundStyle(Color.white.opacity(0.14))
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.accentGradient)
                        .offset(x: 20, y: 16)
                        .rotationEffect(.degrees(-14))
                }
                Text("Drop a PDF here")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Then tap the pages you want, type a range,\nor just ask for them — out loud if you like.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.dimText)
                    .multilineTextAlignment(.center)
                Button("Open a PDF…  ⌘O") { model.openPanel() }
                    .buttonStyle(GradientButtonStyle())
                    .frame(width: 220)
                    .padding(.top, 6)
            }
            .padding(.vertical, 56)
            .frame(maxWidth: 460)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Color.white.opacity(0.15),
                                  style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            )

            Spacer()

            Text("Everything happens on this Mac — no cloud, no uploads.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText.opacity(0.7))
                .padding(.bottom, 16)
        }
    }
}
