import PDFKit

// The one thing the app actually does.
//
// Two routes, and the order matters. PDFTrim copies the source's own objects byte
// for byte and is the right answer for essentially every real PDF — see the comment
// at the top of PDFTrim.swift for why PDFKit's writer cannot be used for this.
// PDFKit remains the fallback for what PDFTrim deliberately refuses (encrypted
// documents) or fails to parse, because a bloated file still beats no file.
enum Extractor {

    enum ExtractError: LocalizedError {
        case emptySelection
        case locked
        case pageUnavailable(Int)
        case writeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .emptySelection:         return "no pages selected"
            case .locked:                 return "this PDF is password-protected — unlock it first"
            case .pageUnavailable(let n): return "couldn't copy page \(n)"
            case .writeFailed(let url):   return "couldn't write \(url.path)"
            }
        }
    }

    /// Which route produced the file. Surfaced by the CLI for testing; the UI stays
    /// quiet about it, since by then the user has their file either way.
    enum Route: String {
        case verbatim = "verbatim object copy"
        case rendered = "PDFKit fallback (re-rendered)"
    }

    /// Copies `pages` (1-based, in the given order) into a new PDF at `url`.
    @discardableResult
    static func extract(from document: PDFDocument, sourceURL: URL?,
                        pages: [Int], to url: URL) throws -> Route {
        guard !pages.isEmpty else { throw ExtractError.emptySelection }
        guard !document.isLocked else { throw ExtractError.locked }

        if let sourceURL {
            do {
                try PDFTrim.extract(from: sourceURL, pages: pages, to: url)
                return .verbatim
            } catch {
                // Encrypted, or something in this file the parser doesn't understand.
                // Fall through rather than fail — PDFKit still produces a usable PDF.
            }
        }
        try renderWithPDFKit(from: document, pages: pages, to: url)
        return .rendered
    }

    private static func renderWithPDFKit(from document: PDFDocument, pages: [Int], to url: URL) throws {
        let out = PDFDocument()
        for (i, n) in pages.enumerated() {
            guard let page = document.page(at: n - 1),
                  let copy = page.copy() as? PDFPage else {
                throw ExtractError.pageUnavailable(n)
            }
            out.insert(copy, at: i)
        }
        guard out.write(to: url) else { throw ExtractError.writeFailed(url) }
    }
}
