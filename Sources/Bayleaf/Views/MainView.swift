import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            if model.document == nil {
                EmptyStateView()
            } else {
                loadedContent
            }

            if model.dropTargeted { DropHighlight() }

            VStack {
                Spacer()
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .onDrop(of: [UTType.fileURL], isTargeted: $model.dropTargeted) { providers in
            model.handleDrop(providers)
        }
        .frame(minWidth: 1000, minHeight: 620)
    }

    private var loadedContent: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.06))
            HStack(spacing: 0) {
                PageGridView()
                Divider().overlay(Color.white.opacity(0.06))
                SidebarView()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LogoMark()
            Text("Bayleaf")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
            Text("tap a page · shift-click for a run · or just ask")
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText.opacity(0.8))
        }
        // Inline with the traffic lights (hidden title bar): the brand row shares
        // their strip instead of stacking a second band beneath it.
        .padding(.leading, 84)
        .padding(.trailing, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}
