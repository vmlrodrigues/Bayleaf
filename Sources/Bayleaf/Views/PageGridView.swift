import SwiftUI

struct PageGridView: View {
    @EnvironmentObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 14)]

    var body: some View {
        if model.snapshotMode {
            eagerGrid
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(1...max(model.pageCount, 1), id: \.self) { page in
                        if page <= model.pageCount {
                            PageCell(page: page)
                        }
                    }
                }
                .padding(18)
                // Remount every cell when the document changes: cell identity is the
                // page NUMBER, so a reused cell's .task(id:) would never re-fire and
                // its thumbnail would stay stale/empty after switching PDFs.
                .id(model.sourceURL)
            }
        }
    }

    // Fixed five-across rows; only ever used for --snapshot renders.
    private var eagerGrid: some View {
        let perRow = 5
        let rows = stride(from: 1, through: model.pageCount, by: perRow).map { start in
            Array(start..<min(start + perRow, model.pageCount + 1))
        }
        return VStack(spacing: 16) {
            ForEach(rows, id: \.first) { row in
                HStack(alignment: .top, spacing: 14) {
                    ForEach(row, id: \.self) { page in
                        PageCell(page: page).frame(width: 118)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
    }
}

struct PageCell: View {
    @EnvironmentObject var model: AppModel
    let page: Int

    var body: some View {
        let selected = model.selection.contains(page)
        let anySelection = !model.selection.isEmpty

        VStack(spacing: 7) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = model.thumbnails[page] {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .aspectRatio(0.72, contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.accentGradient, lineWidth: selected ? 3 : 0)
                )
                // Fade what's being left behind, so the grid reads as a preview of
                // the output, not just a picker.
                .opacity(anySelection && !selected ? 0.45 : 1)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black, Theme.leafB)
                        .padding(5)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.45 : 0.25), radius: selected ? 8 : 4, y: 2)

            Text("\(page)")
                .font(.system(size: 11, weight: selected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(selected ? Theme.leafB : Theme.dimText)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(page: page) }
        .task(id: page) { model.ensureThumbnail(page) }
        .animation(.spring(duration: 0.25), value: selected)
        .help("Click to select · shift-click for a run of pages")
    }
}
