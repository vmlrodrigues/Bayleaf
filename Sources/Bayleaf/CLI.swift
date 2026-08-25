import AppKit
import PDFKit

// Headless entry points. These exist so the extraction engine, the grammar and the
// on-device AI can each be exercised (and demonstrated) from a shell — the same code
// paths the UI calls, minus the UI.
enum CLI {
    private static let usage = """
    Bayleaf headless modes:
      Bayleaf --probe-ai                         report Apple Intelligence availability
      Bayleaf --interpret "<utterance>" <pages>  turn plain English into a page selection
      Bayleaf --extract <src.pdf> <sel> <dst>    extract pages (grammar: 1-3,5,l …)
      Bayleaf --verify <src.pdf> [sel]           extract, then check size + text survived
      Bayleaf --snapshot <src.pdf> <outdir>      render UI states to PNGs
    """

    static func run(_ args: [String]) async {
        switch args.first {
        case "--probe-ai":
            let status = Interpreter.status
            print(status.available ? "Apple Intelligence: available (on-device)"
                                   : "Apple Intelligence: unavailable — \(status.detail)")
            exit(0)

        // Hidden: exercises the no-AI fallback parser directly, so both paths are testable
        // on a machine where the model is available.
        case "--interpret-basic" where args.count >= 3:
            guard let pageCount = Int(args[2]), pageCount > 0 else {
                fail("page count must be a positive integer, got '\(args[2])'")
            }
            do {
                let pages = try Interpreter.Fallback.interpret(args[1], pageCount: pageCount)
                print("utterance:  \(args[1])")
                print("via:        fallback parser (forced)")
                print("selection:  \(PageGrammar.format(Set(pages)))")
                exit(0)
            } catch { fail(error.localizedDescription) }

        case "--interpret" where args.count >= 3:
            guard let pageCount = Int(args[2]), pageCount > 0 else {
                fail("page count must be a positive integer, got '\(args[2])'")
            }
            do {
                let result = try await Interpreter.interpret(args[1], pageCount: pageCount)
                print("utterance:  \(args[1])")
                print("document:   \(pageCount) pages")
                print("via:        \(result.via.label)")
                print("selection:  \(PageGrammar.format(Set(result.pages)))")
                print("pages:      \(result.pages.map(String.init).joined(separator: " "))")
                exit(0)
            } catch { fail("\(error.localizedDescription)") }

        case "--extract" where args.count >= 4:
            let (src, sel, dst) = (args[1], args[2], args[3])
            guard let doc = PDFDocument(url: URL(fileURLWithPath: src)) else {
                fail("cannot read \(src) as a PDF")
            }
            do {
                let pages = try PageGrammar.parse(sel, pageCount: doc.pageCount)
                let route = try Extractor.extract(from: doc, sourceURL: URL(fileURLWithPath: src),
                                                  pages: pages, to: URL(fileURLWithPath: dst))
                print("wrote \(src) (pages \(PageGrammar.format(Set(pages)))) -> \(dst)  [\(route.rawValue)]")
                exit(0)
            } catch { fail(error.localizedDescription) }

        // Extract, then measure the result against the source: size per page and
        // whether the text survived. This is the check that would have caught the
        // Type 3 outlining bug, so it stays in the binary.
        case "--verify" where args.count >= 3:
            let src = args[1]
            let sel = args.count >= 3 ? args[2] : "1-"
            guard let doc = PDFDocument(url: URL(fileURLWithPath: src)) else {
                fail("cannot read \(src) as a PDF")
            }
            do {
                let pages = try PageGrammar.parse(sel, pageCount: doc.pageCount)
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("bayleaf-verify-\(UUID().uuidString).pdf")
                defer { try? FileManager.default.removeItem(at: tmp) }
                let route = try Extractor.extract(from: doc, sourceURL: URL(fileURLWithPath: src),
                                                  pages: pages, to: tmp)

                func stats(_ url: URL, _ limit: [Int]?) -> (bytes: Int, pages: Int, words: Int) {
                    let size = (try? FileManager.default
                        .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    guard let d = PDFDocument(url: url) else { return (size ?? 0, 0, 0) }
                    let idx = limit.map { $0.map { $0 - 1 } } ?? Array(0..<d.pageCount)
                    let text = idx.compactMap { d.page(at: $0)?.string }.joined()
                    return (size ?? 0, d.pageCount, text.split(whereSeparator: { $0.isWhitespace }).count)
                }

                let before = stats(URL(fileURLWithPath: src), pages)
                let after = stats(tmp, nil)
                let srcTotal = (try? FileManager.default
                    .attributesOfItem(atPath: src)[.size] as? Int) ?? 0
                let perPageSource = Double(srcTotal ?? 0) / Double(max(doc.pageCount, 1))
                let perPageOut = Double(after.bytes) / Double(max(after.pages, 1))

                print("source:    \(doc.pageCount) pages, \(srcTotal ?? 0) bytes " +
                      "(\(Int(perPageSource)) B/page)")
                print("extracted: \(after.pages) pages, \(after.bytes) bytes " +
                      "(\(Int(perPageOut)) B/page) via \(route.rawValue)")
                print("bloat:     \(String(format: "%.2f", perPageOut / max(perPageSource, 1)))x per page")
                print("words:     \(before.words) in source pages -> \(after.words) in extract")
                let textKept = before.words == 0 || Double(after.words) / Double(before.words) > 0.95
                let sizeOK = perPageOut / max(perPageSource, 1) < 3.0
                print(textKept ? "TEXT: preserved" : "TEXT: LOST")
                print(sizeOK ? "SIZE: proportionate" : "SIZE: BLOATED")
                exit(textKept && sizeOK ? 0 : 1)
            } catch { fail(error.localizedDescription) }

        case "--snapshot" where args.count >= 3:
            await Snapshot.capture(source: args[1], outDir: args[2])
            exit(0)

        default:
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(2)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
        exit(1)
    }
}
