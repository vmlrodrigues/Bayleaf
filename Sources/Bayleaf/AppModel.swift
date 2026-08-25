import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    // A singleton, pragmatically: the NSApplicationDelegate (file opens) and the menu
    // bar commands both need to reach the same state as the views.
    static let shared = AppModel()

    @Published private(set) var document: PDFDocument?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var sourceSizeLabel = ""
    @Published private(set) var thumbnails: [Int: NSImage] = [:]

    @Published var selection: Set<Int> = [] { didSet { selectionDidChange() } }
    @Published var selectionText = ""
    @Published var selectionError: String?

    @Published var askText = ""
    @Published var askBusy = false
    @Published var askNote: String?

    @Published var filename = ""
    @Published private(set) var lastSuggested = ""
    @Published var destination: URL?
    @Published var dropTargeted = false
    @Published var toast: Toast?

    var pageCount: Int { document?.pageCount ?? 0 }
    /// Set by --snapshot before rendering: ImageRenderer can't drive ScrollView or
    /// lazy containers, so views swap in eager layouts when this is on.
    var snapshotMode = false
    /// True once the user has diverged from the suggestion; suggestions stop
    /// overwriting their words, and the ↺ button appears.
    var filenameEdited: Bool { filename != lastSuggested }

    private var applyingText = false
    private var shiftAnchor: Int?
    private var toastDismiss: Task<Void, Never>?

    struct Toast: Identifiable, Equatable {
        enum Kind { case success, failure, info }
        let id = UUID()
        let kind: Kind
        let message: String
        var revealURL: URL?
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    // MARK: - Loading

    func load(url: URL) {
        guard let doc = PDFDocument(url: url) else {
            showToast(.failure, "Couldn't open \(url.lastPathComponent) — is it a PDF?")
            return
        }
        if doc.isLocked {
            showToast(.failure, "\(url.lastPathComponent) is password-protected — unlock it in Preview first.")
            return
        }
        document = doc
        sourceURL = url
        thumbnails = [:]
        selection = []
        selectionText = ""
        selectionError = nil
        askText = ""
        askNote = nil
        destination = url.deletingLastPathComponent()
        lastSuggested = ""
        filename = ""

        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        sourceSizeLabel = bytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PDF to pull pages from"
        if panel.runModal() == .OK, let url = panel.url { load(url: url) }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            }
            guard let url else { return }
            Task { @MainActor in
                guard url.pathExtension.lowercased() == "pdf" else {
                    self.showToast(.failure, "\(url.lastPathComponent) isn't a PDF.")
                    return
                }
                self.load(url: url)
            }
        }
        return true
    }

    // MARK: - Thumbnails

    func ensureThumbnail(_ page: Int) {
        guard thumbnails[page] == nil, let p = document?.page(at: page - 1) else { return }
        thumbnails[page] = p.thumbnail(of: CGSize(width: 260, height: 360), for: .cropBox)
    }

    func generateAllThumbnails() {
        guard pageCount > 0 else { return }
        for page in 1...pageCount { ensureThumbnail(page) }
    }

    // MARK: - Selection

    func toggle(page: Int) {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        if shift, let anchor = shiftAnchor, anchor != page {
            selection.formUnion(min(anchor, page)...max(anchor, page))
        } else if selection.contains(page) {
            selection.remove(page)
        } else {
            selection.insert(page)
        }
        shiftAnchor = page
    }

    func selectAll()    { guard pageCount > 0 else { return }; selection = Set(1...pageCount) }
    func selectNone()   { selection = [] }
    func invert()       { guard pageCount > 0 else { return }; selection = Set(1...pageCount).subtracting(selection) }
    func selectOdd()    { guard pageCount > 0 else { return }; selection = Set(stride(from: 1, through: pageCount, by: 2)) }
    func selectEven()   { guard pageCount > 1 else { return }; selection = Set(stride(from: 2, through: pageCount, by: 2)) }

    /// The grid → text direction. Skipped while the text field itself is driving.
    private func selectionDidChange() {
        if !applyingText {
            selectionText = PageGrammar.format(selection)
            selectionError = nil
        }
        refreshSuggestion()
    }

    /// The text → grid direction, called on every keystroke in the range field.
    func applySelectionText() {
        guard pageCount > 0 else { return }
        let text = selectionText.trimmingCharacters(in: .whitespaces)
        applyingText = true
        defer { applyingText = false }
        if text.isEmpty {
            selection = []
            selectionError = nil
            return
        }
        do {
            selection = Set(try PageGrammar.parse(text, pageCount: pageCount))
            selectionError = nil
        } catch {
            selectionError = error.localizedDescription
        }
    }

    /// Tidies "3,1-2,5" into "1-3,5" once the user is done typing.
    func canonicaliseSelectionText() {
        if selectionError == nil, !selection.isEmpty {
            selectionText = PageGrammar.format(selection)
        }
    }

    // MARK: - Ask (Apple Intelligence)

    func ask() async {
        let utterance = askText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !utterance.isEmpty, pageCount > 0 else { return }
        askBusy = true
        askNote = nil
        defer { askBusy = false }
        do {
            let result = try await Interpreter.interpret(utterance, pageCount: pageCount)
            selection = Set(result.pages)
            askNote = result.via == .fallback ? "interpreted with the quick parser" : nil
        } catch {
            showToast(.failure, error.localizedDescription)
        }
    }

    // MARK: - Filename

    private func refreshSuggestion() {
        guard let sourceURL, !selection.isEmpty else {
            if !filenameEdited { filename = ""; lastSuggested = "" }
            return
        }
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let summary = selection.count == 1
            ? "page \(selection.first!)"
            : "pages \(PageGrammar.format(selection))"
        let suggested = sanitise("\(base) – \(summary).pdf")
        if !filenameEdited || filename.isEmpty { filename = suggested }
        lastSuggested = suggested
    }

    func resetFilename() { filename = lastSuggested }

    private func sanitise(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Extract

    func extract() {
        guard let document, let sourceURL else { return }
        guard !selection.isEmpty else {
            showToast(.info, "Pick some pages first — tap thumbnails, type a range, or ask.")
            return
        }
        var name = filename.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = lastSuggested }
        if name.isEmpty { name = "extract.pdf" }
        if !name.lowercased().hasSuffix(".pdf") { name += ".pdf" }

        let dir = destination ?? sourceURL.deletingLastPathComponent()
        let url = uniqueURL(in: dir, name: name)
        do {
            try Extractor.extract(from: document, sourceURL: sourceURL,
                                  pages: selection.sorted(), to: url)
            showToast(.success, "Saved \(url.lastPathComponent)", revealURL: url)
        } catch {
            showToast(.failure, error.localizedDescription)
        }
    }

    /// Never clobber: "name.pdf" → "name 2.pdf" → "name 3.pdf" …
    private func uniqueURL(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).pdf")
            n += 1
        }
        return candidate
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Where should extracted PDFs go?"
        if panel.runModal() == .OK, let url = panel.url { destination = url }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Toast

    func showToast(_ kind: Toast.Kind, _ message: String, revealURL: URL? = nil) {
        toast = Toast(kind: kind, message: message, revealURL: revealURL)
        toastDismiss?.cancel()
        toastDismiss = Task { [id = toast?.id] in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled, self.toast?.id == id { self.toast = nil }
        }
    }
}
