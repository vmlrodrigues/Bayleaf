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
        HStack(spacing: 0) {
            PageGridView()
            Divider().overlay(Color.white.opacity(0.06))
            SidebarView()
        }
    }
}
