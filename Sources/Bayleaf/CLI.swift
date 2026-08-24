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
                try Extractor.extract(from: doc, pages: pages, to: URL(fileURLWithPath: dst))
                print("wrote \(src) (pages \(PageGrammar.format(Set(pages)))) -> \(dst)")
                exit(0)
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
