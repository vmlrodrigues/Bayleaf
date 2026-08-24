import Foundation

/// The page-selection mini-language, kept compatible with the `pdftools` CLI this app
/// replaces (pdfcpu's grammar), so anything the old CLI accepted keeps working:
///
///   5            a single page
///   1-3          a range
///   1-3,5,8-10   comma-separated mix
///   1-  /  -3    open at either end
///   3-l          page 3 to the last page
///   l            the last page
///   l-3          last page minus 3  (pdfcpu quirk: on 10 pages that's page 7)
///   odd / even   every odd / even page
enum PageGrammar {

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Parses `text` against a document of `pageCount` pages.
    /// Returns sorted, de-duplicated, 1-based page numbers.
    static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        guard pageCount > 0 else { throw ParseError(message: "no document loaded") }
        var pages = Set<Int>()

        for rawToken in text.split(separator: ",", omittingEmptySubsequences: true) {
            let token = rawToken.trimmingCharacters(in: .whitespaces).lowercased()
            if token.isEmpty { continue }

            switch token {
            case "odd":  pages.formUnion(stride(from: 1, through: pageCount, by: 2)); continue
            case "even": pages.formUnion(stride(from: 2, through: pageCount, by: 2)); continue
            case "l":    pages.insert(pageCount); continue
            default: break
            }

            // l-N: "last minus N". Checked before the generic a-b split, which would
            // otherwise choke on the leading l.
            if token.hasPrefix("l-") {
                guard let n = Int(token.dropFirst(2)), n >= 0 else {
                    throw ParseError(message: "'\(token)' isn't a page or a range")
                }
                let page = pageCount - n
                guard page >= 1 else {
                    throw ParseError(message: "l-\(n) points before page 1 (the PDF has \(pageCount) pages)")
                }
                pages.insert(page)
                continue
            }

            if let dash = token.firstIndex(of: "-") {
                let left = String(token[..<dash])
                let right = String(token[token.index(after: dash)...])

                let start: Int
                if left.isEmpty { start = 1 }                        // "-3"
                else if let n = Int(left) { start = n }
                else { throw ParseError(message: "'\(token)' isn't a page or a range") }

                let end: Int
                if right.isEmpty || right == "l" { end = pageCount } // "3-" / "3-l"
                else if let n = Int(right) { end = n }
                else { throw ParseError(message: "'\(token)' isn't a page or a range") }

                guard start >= 1 else { throw ParseError(message: "pages start at 1, not \(start)") }
                guard end <= pageCount else {
                    throw ParseError(message: "page \(end) — the PDF only has \(pageCount) pages")
                }
                guard start <= end else { throw ParseError(message: "'\(token)' is backwards") }
                pages.formUnion(start...end)
                continue
            }

            guard let n = Int(token) else {
                throw ParseError(message: "'\(token)' isn't a page or a range")
            }
            guard n >= 1 else { throw ParseError(message: "pages start at 1, not \(n)") }
            guard n <= pageCount else {
                throw ParseError(message: "page \(n) — the PDF only has \(pageCount) pages")
            }
            pages.insert(n)
        }

        guard !pages.isEmpty else { throw ParseError(message: "no pages selected") }
        return pages.sorted()
    }

    /// Canonical text for a selection: "1-3,5,8-10". Inverse of `parse` for round-tripping.
    static func format(_ pages: Set<Int>) -> String {
        let sorted = pages.sorted()
        guard !sorted.isEmpty else { return "" }
        var runs: [(Int, Int)] = []
        for p in sorted {
            if let last = runs.last, p == last.1 + 1 { runs[runs.count - 1].1 = p }
            else { runs.append((p, p)) }
        }
        return runs.map { $0.0 == $0.1 ? "\($0.0)" : "\($0.0)-\($0.1)" }.joined(separator: ",")
    }
}
