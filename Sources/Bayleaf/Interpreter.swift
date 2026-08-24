import Foundation
import FoundationModels

// Natural language → page selection, entirely on this Mac.
//
// Three tiers, cheapest first:
//   1. deterministic  — mechanical asks ("odd pages", "everything") answered by code;
//                       a language model has no business enumerating odd numbers.
//   2. model          — FoundationModels (on-device Apple Intelligence) TRANSLATES the
//                       request into the same compact range notation the Pages field
//                       uses ("1,5-9"), and PageGrammar validates it. The model never
//                       gets to invent structure — anything unparseable is rejected.
//   3. fallback       — if the model is off or its answer doesn't parse, a small
//                       regex parser catches the common phrasings.
enum Interpreter {

    struct InterpretError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    enum Via {
        case model, deterministic, fallback
        var label: String {
            switch self {
            case .model:         return "FoundationModels (on-device)"
            case .deterministic: return "deterministic (no model needed)"
            case .fallback:      return "fallback parser"
            }
        }
    }

    struct Result {
        let pages: [Int]   // sorted, unique, 1-based
        let via: Via
    }

    static var status: (available: Bool, detail: String) {
        switch SystemLanguageModel.default.availability {
        case .available:
            return (true, "Apple Intelligence · on-device")
        case .unavailable(let reason):
            return (false, String(describing: reason))
        }
    }

    static func interpret(_ utterance: String, pageCount: Int) async throws -> Result {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InterpretError(message: "nothing to interpret") }
        let normalised = normaliseNumberWords(trimmed.lowercased())

        if let pages = mechanical(normalised, pageCount: pageCount) {
            return Result(pages: pages, via: .deterministic)
        }

        guard status.available else {
            return Result(pages: try Fallback.interpret(normalised, pageCount: pageCount),
                          via: .fallback)
        }

        do {
            let pages = try await translate(normalised, pageCount: pageCount)
            return Result(pages: pages, via: .model)
        } catch {
            // The model misfired (or its answer didn't survive validation). Degrade
            // rather than die; if the fallback can't make sense of it either, surface
            // the friendlier of the two errors.
            if let pages = try? Fallback.interpret(normalised, pageCount: pageCount) {
                return Result(pages: pages, via: .fallback)
            }
            throw InterpretError(message: "couldn't work out which pages you mean by “\(trimmed)”")
        }
    }

    // MARK: - Tier 1: mechanical asks

    /// Whole-document and parity requests, answered without any model. Guarded to
    /// dodge compound asks ("odd pages of the first 10" has digits → model's job).
    private static func mechanical(_ text: String, pageCount: Int) -> [Int]? {
        guard text.rangeOfCharacter(from: .decimalDigits) == nil else { return nil }
        let hasOdd = text.contains("odd")
        let hasEven = text.contains("even")
        if hasOdd, !hasEven { return Array(stride(from: 1, through: pageCount, by: 2)) }
        if hasEven, !hasOdd { return Array(stride(from: 2, through: pageCount, by: 2)) }
        let wantsAll = text.contains("all") || text.contains("everything") || text.contains("whole")
        let hasCarveOut = ["except", "but", "apart", "without", "besides"].contains { text.contains($0) }
        if wantsAll, !hasCarveOut, pageCount > 0 { return Array(1...pageCount) }
        return nil
    }

    // MARK: - Tier 2: the model, as a translator

    @Generable
    struct SelectionTranslation {
        @Guide(description: "The pages the user wants, in compact range notation: comma-separated pieces, each a single page 'N' or a run 'A-B', ascending, no spaces. Only digits, commas and dashes. If the request carves pages out of a base set, this is the base set.")
        var selection: String
        @Guide(description: "Pages to remove from selection, same notation. Empty string when nothing is carved out.")
        var exclude: String
    }

    private static func translate(_ utterance: String, pageCount: Int) async throws -> [Int] {
        let instructions = """
        Translate one request about a PDF into compact page-range notation. \
        The PDF has \(pageCount) pages, numbered 1 to \(pageCount).
        Notation: a single page is its number; a run of consecutive pages is FIRST-LAST; \
        separate pieces with commas, ascending. No spaces, no words, no page 0, nothing \
        above \(pageCount).
        Vocabulary:
        - "the cover" or "the first page" → 1
        - "the last page" → \(pageCount)
        - "the last K pages" → the run ending at \(pageCount) with K pages in it
        - "the first K pages" → 1-K
        - "everything" / "all of it" → 1-\(pageCount)
        Keep separate pieces separate — "5 to 9 and the cover" is 1,5-9 and never 1-9.
        Carve-outs ("except", "but not", "without", "skip") go in exclude, in the same \
        notation, with the base set in selection — never do the subtraction yourself.
        Include ONLY pages the request itself asks for. Add nothing beyond them, and \
        ignore filler words in dictated speech.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: utterance,
            generating: SelectionTranslation.self,
            options: GenerationOptions(sampling: .greedy))

        let cleaned = response.content.selection.replacingOccurrences(of: " ", with: "")
        var pages = Set(try PageGrammar.parse(cleaned, pageCount: pageCount))
        let excluded = response.content.exclude.replacingOccurrences(of: " ", with: "")
        if !excluded.isEmpty, let out = try? PageGrammar.parse(excluded, pageCount: pageCount) {
            pages.subtract(out)
        }
        guard !pages.isEmpty else {
            throw InterpretError(message: "that selection excludes every page")
        }
        return pages.sorted()
    }

    // MARK: - Tier 3: deterministic understudy

    enum Fallback {
        static func interpret(_ utterance: String, pageCount: Int) throws -> [Int] {
            // Patterns CONSUME the text they match, so the 3 in "last 3 pages" can't
            // also be claimed as page 3 by the bare-number pass at the end.
            var text = normaliseNumberWords(utterance.lowercased())
            var pages = Set<Int>()

            func take(_ pattern: String, _ handler: ([Int]) -> Void) {
                let re = try! NSRegularExpression(pattern: pattern)
                while let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    let groups = (1..<m.numberOfRanges).compactMap { i in
                        Range(m.range(at: i), in: text).flatMap { Int(text[$0]) }
                    }
                    guard let whole = Range(m.range, in: text) else { break }
                    text.removeSubrange(whole)
                    handler(groups)
                }
            }

            if text.contains("all") || text.contains("everything") || text.contains("whole") {
                pages.formUnion(1...pageCount)
            }
            if text.contains("odd")  { pages.formUnion(stride(from: 1, through: pageCount, by: 2)) }
            if text.contains("even") { pages.formUnion(stride(from: 2, through: pageCount, by: 2)) }
            if text.contains("last page") { pages.insert(pageCount) }
            if text.contains("first page") || text.contains("cover") { pages.insert(1) }

            take("(\\d+)\\s*(?:to|through|thru|until|–|—|-)\\s*(\\d+)") { g in
                guard g.count == 2 else { return }
                let (a, b) = (min(g[0], g[1]), max(g[0], g[1]))
                if a >= 1 { pages.formUnion(a...min(b, pageCount)) }
            }
            take("last (\\d+)") { g in
                guard g.count == 1 else { return }
                pages.formUnion(max(1, pageCount - g[0] + 1)...pageCount)
            }
            take("first (\\d+)") { g in
                guard g.count == 1 else { return }
                pages.formUnion(1...min(g[0], pageCount))
            }
            take("(\\d+)") { g in
                guard g.count == 1 else { return }
                if g[0] >= 1 && g[0] <= pageCount { pages.insert(g[0]) }
            }

            guard !pages.isEmpty else {
                throw InterpretError(message: "couldn't work out any pages from “\(utterance)”")
            }
            return pages.sorted()
        }
    }

    // MARK: - Shared

    /// "five to nine" → "5 to 9". Helps both the small on-device model and the
    /// fallback regexes; dictation produces number words constantly.
    private static func normaliseNumberWords(_ input: String) -> String {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                     "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
                     "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
                     "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
                     "twenty": 20]
        var text = input
        for (word, n) in words {
            text = text.replacingOccurrences(of: "\\b\(word)\\b", with: "\(n)",
                                             options: .regularExpression)
        }
        return text
    }
}
