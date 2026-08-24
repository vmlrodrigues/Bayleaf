import SwiftUI

// ImageRenderer (the --snapshot path) can't draw AppKit-backed TextFields; this is a
// pixel-for-pixel stand-in used only in snapshot mode.
private struct StaticField: View {
    let text: String
    let placeholder: String
    var mono = false
    var size: CGFloat = 13

    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(mono ? .system(size: size, weight: .medium, design: .monospaced)
                       : .system(size: size))
            .foregroundStyle(text.isEmpty ? Theme.dimText.opacity(0.6) : .white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var dictation = Dictation()
    @FocusState private var rangeFieldFocused: Bool

    var body: some View {
        Group {
            if model.snapshotMode {
                VStack(spacing: 12) { cards; Spacer(minLength: 0) }.padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 12) { cards }.padding(14)
                }
            }
        }
        .frame(width: 336)
        .background(Color.black.opacity(0.25))
        .onAppear {
            dictation.onFinal = { text in
                model.askText = text
                Task { await model.ask() }
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        documentCard
        pagesCard
        askCard
        saveCard
    }

    private var documentCard: some View {
        Card(title: "Document") {
            HStack(spacing: 10) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accentGradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.sourceURL?.lastPathComponent ?? "—")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text("\(model.pageCount) pages\(model.sourceSizeLabel.isEmpty ? "" : " · \(model.sourceSizeLabel)")")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dimText)
                }
                Spacer()
                Button {
                    model.openPanel()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.dimText)
                .help("Open a different PDF (⌘O)")
            }
        }
    }

    private var pagesCard: some View {
        Card(title: "Pages") {
            if model.snapshotMode {
                StaticField(text: model.selectionText, placeholder: "e.g. 1-3, 8, l",
                            mono: true, size: 14)
            } else {
                TextField("e.g. 1-3, 8, l", text: $model.selectionText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .focused($rangeFieldFocused)
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(
                        model.selectionError == nil ? Color.white.opacity(0.10) : Color.orange.opacity(0.7),
                        lineWidth: 1))
                    .onChange(of: model.selectionText) {
                        if rangeFieldFocused { model.applySelectionText() }
                    }
                    .onSubmit { model.canonicaliseSelectionText() }
            }

            if let error = model.selectionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 6) {
                Chip(label: "All")    { model.selectAll() }
                Chip(label: "None")   { model.selectNone() }
                Chip(label: "Invert") { model.invert() }
                Chip(label: "Odd")    { model.selectOdd() }
                Chip(label: "Even")   { model.selectEven() }
            }

            Text(selectionSummary)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dimText)
        }
    }

    private var selectionSummary: String {
        model.selection.isEmpty
            ? "Nothing selected yet"
            : "\(model.selection.count) of \(model.pageCount) pages selected"
    }

    private var askCard: some View {
        Card(title: "Ask") {
            HStack(spacing: 8) {
                if model.snapshotMode {
                    StaticField(text: model.askText, placeholder: "“the last three pages”…")
                } else {
                    TextField("“the last three pages”…", text: $model.askText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.10), lineWidth: 1))
                        .onSubmit { Task { await model.ask() } }
                        .disabled(dictation.isRecording)
                }

                Button { dictation.toggle() } label: {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(dictation.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(Theme.accentGradient))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .overlay(Circle().stroke(
                            dictation.isRecording ? Color.red.opacity(0.7) : Color.white.opacity(0.12),
                            lineWidth: dictation.isRecording ? 2 : 1))
                }
                .buttonStyle(.plain)
                .help(dictation.isRecording ? "Stop and use what you said" : "Ask with your voice")
            }

            if dictation.isRecording {
                Text(dictation.partial.isEmpty ? "Listening…" : "“\(dictation.partial)”")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(Theme.leafB)
                    .lineLimit(2)
            } else if model.askBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(.system(size: 11)).foregroundStyle(Theme.dimText)
                }
            } else if let err = dictation.lastError {
                Text(err).font(.system(size: 11)).foregroundStyle(.orange)
            } else if let note = model.askNote {
                Text(note).font(.system(size: 11)).foregroundStyle(.orange)
            }

            HStack(spacing: 5) {
                StatusDot(ok: Interpreter.status.available)
                Text(Interpreter.status.available
                     ? "Apple Intelligence · on-device"
                     : "AI off — simple phrases still work")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.dimText)
            }
        }
    }

    private var saveCard: some View {
        Card(title: "Save as") {
            HStack(spacing: 6) {
                if model.snapshotMode {
                    StaticField(text: model.filename, placeholder: "filename.pdf", size: 12.5)
                } else {
                    TextField("filename.pdf", text: $model.filename)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(9)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.10), lineWidth: 1))
                }
                if model.filenameEdited && !model.lastSuggested.isEmpty {
                    Button { model.resetFilename() } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(Theme.dimText)
                    }
                    .buttonStyle(.plain)
                    .help("Back to the suggested name")
                }
            }

            Button {
                model.chooseDestination()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentGradient)
                    Text(destinationLabel)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.dimText)
                }
            }
            .buttonStyle(.plain)
            .help("Choose where extracted PDFs are saved")

            Button(extractLabel) { model.extract() }
                .buttonStyle(GradientButtonStyle(enabled: !model.selection.isEmpty))
                .disabled(model.selection.isEmpty)
                .keyboardShortcut("e", modifiers: .command)
        }
    }

    private var destinationLabel: String {
        guard let dest = model.destination else { return "next to the original" }
        if dest == model.sourceURL?.deletingLastPathComponent() {
            return "next to the original"
        }
        return dest.lastPathComponent
    }

    private var extractLabel: String {
        model.selection.isEmpty
            ? "Extract"
            : "Extract \(model.selection.count) page\(model.selection.count == 1 ? "" : "s")"
    }
}
