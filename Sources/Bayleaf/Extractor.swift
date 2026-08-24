import PDFKit

// The one thing the app actually does. PDFKit end to end: pages are copied into a
// fresh document so the original is never touched, whatever else goes wrong.
enum Extractor {

    enum ExtractError: LocalizedError {
        case emptySelection
        case locked
        case pageUnavailable(Int)
        case writeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .emptySelection:        return "no pages selected"
            case .locked:                return "this PDF is password-protected — unlock it first"
            case .pageUnavailable(let n): return "couldn't copy page \(n)"
            case .writeFailed(let url):  return "couldn't write \(url.path)"
            }
        }
    }

    /// Copies `pages` (1-based, in the given order) from `document` into a new PDF at `url`.
    static func extract(from document: PDFDocument, pages: [Int], to url: URL) throws {
        guard !pages.isEmpty else { throw ExtractError.emptySelection }
        guard !document.isLocked else { throw ExtractError.locked }

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
