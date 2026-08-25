import Compression
import Foundation

/// Verbatim page extraction.
///
/// PDFKit cannot be used to *write* extracted pages. Quartz's PDF writer re-renders
/// a page rather than copying it, and when a page uses Type 3 fonts — glyphs defined
/// as little content streams, which is what most scanner and OCR pipelines emit — it
/// has no way to re-embed them, so it inlines every glyph's outline into the page.
/// A 71-page extract from a 12 MB scanned textbook came out at 30 MB with *zero*
/// selectable text: every letter had become Bézier curves. `CGContext.drawPDFPage`
/// and PDFKit's remove-the-other-pages route both do exactly the same thing, so this
/// is Quartz's writer, not one API's quirk.
///
/// So this does what pdfcpu's `TrimFile` does, which is the only correct thing: copy
/// the objects a page depends on **byte for byte**, renumber them, and write a fresh
/// file around them. Content streams are never decompressed, glyphs are never
/// touched, and the output is as small as the input's own encoding — 436 KB for the
/// case above, with all 27,000 words still selectable.
///
/// Deliberately not supported: encrypted documents. Their streams are ciphered with
/// per-object keys, so copying bytes verbatim would produce garbage. `extract` throws
/// `TrimError.encrypted` and the caller falls back to PDFKit, which handles the
/// decryption itself.
enum PDFTrim {

    enum TrimError: LocalizedError {
        case unreadable
        case encrypted
        case noCatalog
        case pageOutOfRange(Int)
        case writeFailed(URL)

        var errorDescription: String? {
            switch self {
            case .unreadable:            return "couldn't parse the PDF"
            case .encrypted:             return "the PDF is encrypted"
            case .noCatalog:             return "the PDF has no page tree"
            case .pageOutOfRange(let n): return "page \(n) doesn't exist"
            case .writeFailed(let url):  return "couldn't write \(url.path)"
            }
        }
    }

    // MARK: - Object model

    /// A parsed PDF object. Stream payloads are kept as a byte range into the source
    /// file rather than copied, so nothing large is duplicated until it is written.
    indirect enum Obj {
        case null
        case bool(Bool)
        case int(Int)
        case real(Double)
        case string([UInt8], hex: Bool)
        case name(String)
        case array([Obj])
        case dict([String: Obj])
        case stream([String: Obj], Range<Int>)
        case ref(Int)                       // generation is ignored; see Document.scan
    }

    // MARK: - Entry point

    static func extract(from url: URL, pages: [Int], to out: URL) throws {
        guard let data = try? Data(contentsOf: url) else { throw TrimError.unreadable }
        let doc = try Document([UInt8](data))
        let leaves = try doc.pageLeaves()
        for n in pages where n < 1 || n > leaves.count {
            throw TrimError.pageOutOfRange(n)
        }
        let writer = Writer(doc: doc)
        let bytes = try writer.build(selecting: pages.map { leaves[$0 - 1] })
        do {
            try Data(bytes).write(to: out, options: .atomic)
        } catch {
            throw TrimError.writeFailed(out)
        }
    }

    /// Page count without loading PDFKit. Used only by the headless CLI.
    static func pageCount(of url: URL) throws -> Int {
        guard let data = try? Data(contentsOf: url) else { throw TrimError.unreadable }
        return try Document([UInt8](data)).pageLeaves().count
    }

    // MARK: - Lexer / parser

    struct Parser {
        let b: [UInt8]
        var i: Int

        init(_ b: [UInt8], _ i: Int = 0) { self.b = b; self.i = i }

        static func isWhite(_ c: UInt8) -> Bool {
            c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32
        }
        static func isDelim(_ c: UInt8) -> Bool {
            c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B
                || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25
        }
        static func isRegular(_ c: UInt8) -> Bool { !isWhite(c) && !isDelim(c) }

        mutating func skipWhitespace() {
            while i < b.count {
                let c = b[i]
                if Parser.isWhite(c) {
                    i += 1
                } else if c == 0x25 {                       // % comment to end of line
                    while i < b.count, b[i] != 10, b[i] != 13 { i += 1 }
                } else {
                    break
                }
            }
        }

        mutating func keyword(_ word: String) -> Bool {
            let w = [UInt8](word.utf8)
            guard i + w.count <= b.count else { return false }
            for (k, c) in w.enumerated() where b[i + k] != c { return false }
            let after = i + w.count
            if after < b.count, Parser.isRegular(b[after]) { return false }
            i = after
            return true
        }

        mutating func parse() -> Obj? {
            skipWhitespace()
            guard i < b.count else { return nil }
            switch b[i] {
            case 0x2F: return .name(parseName())
            case 0x28: return parseLiteralString()
            case 0x5B: return parseArray()
            case 0x3C:
                if i + 1 < b.count, b[i + 1] == 0x3C { return parseDictOrStream() }
                return parseHexString()
            case 0x74: return keyword("true")  ? .bool(true)  : nil
            case 0x66: return keyword("false") ? .bool(false) : nil
            case 0x6E: return keyword("null")  ? .null        : nil
            case 0x5D, 0x3E, 0x29: return nil                  // stray close delimiter
            default: return parseNumberOrRef()
            }
        }

        mutating func parseName() -> String {
            i += 1                                              // the '/'
            var out = [UInt8]()
            while i < b.count, Parser.isRegular(b[i]) {
                if b[i] == 0x23, i + 2 < b.count,
                   let hi = hexVal(b[i + 1]), let lo = hexVal(b[i + 2]) {
                    out.append(hi << 4 | lo)
                    i += 3
                } else {
                    out.append(b[i])
                    i += 1
                }
            }
            return String(decoding: out, as: UTF8.self)
        }

        private func hexVal(_ c: UInt8) -> UInt8? {
            switch c {
            case 0x30...0x39: return c - 0x30
            case 0x41...0x46: return c - 0x41 + 10
            case 0x61...0x66: return c - 0x61 + 10
            default: return nil
            }
        }

        mutating func parseLiteralString() -> Obj {
            i += 1                                              // the '('
            var out = [UInt8](), depth = 1
            while i < b.count {
                let c = b[i]
                if c == 0x5C {                                  // backslash escape
                    i += 1
                    guard i < b.count else { break }
                    out.append(0x5C)
                    out.append(b[i])
                    i += 1
                    continue
                }
                if c == 0x28 { depth += 1 }
                if c == 0x29 {
                    depth -= 1
                    if depth == 0 { i += 1; break }
                }
                out.append(c)
                i += 1
            }
            return .string(out, hex: false)
        }

        mutating func parseHexString() -> Obj {
            i += 1                                              // the '<'
            var out = [UInt8]()
            while i < b.count, b[i] != 0x3E {
                out.append(b[i])
                i += 1
            }
            if i < b.count { i += 1 }
            return .string(out, hex: true)
        }

        mutating func parseArray() -> Obj {
            i += 1                                              // the '['
            var items = [Obj]()
            while true {
                skipWhitespace()
                guard i < b.count else { break }
                if b[i] == 0x5D { i += 1; break }
                guard let o = parse() else { i += 1; continue }
                items.append(o)
            }
            return .array(items)
        }

        mutating func parseDictOrStream() -> Obj {
            i += 2                                              // the '<<'
            var d = [String: Obj]()
            while true {
                skipWhitespace()
                guard i < b.count else { break }
                if b[i] == 0x3E {
                    i += (i + 1 < b.count && b[i + 1] == 0x3E) ? 2 : 1
                    break
                }
                guard b[i] == 0x2F else {                       // resync on junk
                    guard parse() != nil else { i += 1; continue }
                    continue
                }
                let key = parseName()
                guard let value = parse() else { continue }
                d[key] = value
            }

            // A stream keyword may follow the dictionary. The payload's extent comes
            // from /Length when that is a plain integer and lands exactly on
            // "endstream"; otherwise the file is scanned for the keyword, which is how
            // most real-world PDFs with a wrong /Length still open elsewhere.
            let save = i
            skipWhitespace()
            if keyword("stream") {
                if i < b.count, b[i] == 13 { i += 1 }
                if i < b.count, b[i] == 10 { i += 1 }
                let start = i
                var payloadEnd = -1
                if case .int(let n)? = d["Length"], n >= 0, start + n <= b.count {
                    var probe = Parser(b, start + n)
                    probe.skipWhitespace()
                    // /Length is authoritative when it lands on "endstream". The
                    // payload is then exactly n bytes and must NOT be trimmed: a
                    // deflate stream ending in 0x0A is ordinary data, not a separator.
                    if probe.keyword("endstream") { payloadEnd = start + n }
                }
                var end = payloadEnd
                if payloadEnd < 0 {
                    // No usable /Length: find the keyword and drop the EOL before it,
                    // which in that case really is a separator.
                    end = Parser.find([UInt8]("endstream".utf8), in: b, from: start) ?? b.count
                    payloadEnd = end
                    if payloadEnd > start, b[payloadEnd - 1] == 10 { payloadEnd -= 1 }
                    if payloadEnd > start, b[payloadEnd - 1] == 13 { payloadEnd -= 1 }
                }
                i = min(end + 9, b.count)
                return .stream(d, start..<payloadEnd)
            }
            i = save
            return .dict(d)
        }

        mutating func parseNumberOrRef() -> Obj? {
            let save = i
            guard let first = parseNumber() else { i = save; return nil }
            if case .int(let num) = first, num >= 0 {
                let afterFirst = i
                var probe = self
                probe.skipWhitespace()
                if case .int(let gen)? = probe.parseNumber(), gen >= 0 {
                    probe.skipWhitespace()
                    if probe.keyword("R") {
                        i = probe.i
                        return .ref(num)
                    }
                }
                i = afterFirst
            }
            return first
        }

        mutating func parseNumber() -> Obj? {
            var out = [UInt8]()
            while i < b.count, Parser.isRegular(b[i]) {
                out.append(b[i])
                i += 1
            }
            guard !out.isEmpty else { return nil }
            let s = String(decoding: out, as: UTF8.self)
            if let n = Int(s) { return .int(n) }
            if let d = Double(s) { return .real(d) }
            return nil
        }

        static func find(_ needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
            guard !needle.isEmpty, from < hay.count else { return nil }
            let last = hay.count - needle.count
            guard last >= from else { return nil }
            var k = from
            while k <= last {
                if hay[k] == needle[0] {
                    var m = 1
                    while m < needle.count, hay[k + m] == needle[m] { m += 1 }
                    if m == needle.count { return k }
                }
                k += 1
            }
            return nil
        }
    }

    // MARK: - Document

    /// The object table, built by scanning the file rather than by trusting its xref.
    ///
    /// Rebuilding beats parsing the cross-reference table here: broken, stale and
    /// hybrid xrefs are common in the wild (and are exactly what turns up in scanned
    /// books), while a sequential scan cannot be stale. Incremental updates fall out
    /// correctly for free — a later definition of an object number overwrites an
    /// earlier one, which is precisely what an incremental update means.
    ///
    /// The scan steps *over* stream payloads, so binary data that happens to contain
    /// something shaped like "12 0 obj" can never shadow a real object.
    final class Document {
        let b: [UInt8]
        private(set) var objects: [Int: Obj] = [:]
        private(set) var trailer: [String: Obj] = [:]
        /// Where each object was defined, as a byte offset. Later in the file wins,
        /// which is exactly what an incremental update means. Objects unpacked from a
        /// container stream inherit the container's offset, so the same one rule
        /// orders every definition — and, unlike iterating a Swift dictionary, it is
        /// deterministic. (It was not, once: the same file produced different output
        /// on consecutive runs because container order came from a hashed dictionary.)
        private var definedAt: [Int: Int] = [:]

        init(_ bytes: [UInt8]) throws {
            self.b = bytes
            scan()
            expandObjectStreams()
            guard trailer["Encrypt"] == nil else { throw TrimError.encrypted }
        }

        private func scan() {
            let objKeyword: [UInt8] = [0x6F, 0x62, 0x6A]                  // "obj"
            var i = 0
            while let hit = Parser.find(objKeyword, in: b, from: i) {
                i = hit + 3
                // Walk back over "<num> <gen> " to find the object header's start.
                var k = hit - 1
                while k >= 0, Parser.isWhite(b[k]) { k -= 1 }
                let genEnd = k
                while k >= 0, b[k] >= 0x30, b[k] <= 0x39 { k -= 1 }
                guard genEnd > k else { continue }
                while k >= 0, Parser.isWhite(b[k]) { k -= 1 }
                let numEnd = k
                while k >= 0, b[k] >= 0x30, b[k] <= 0x39 { k -= 1 }
                guard numEnd > k else { continue }
                let num = Int(String(decoding: b[(k + 1)...numEnd], as: UTF8.self)) ?? -1
                guard num >= 0 else { continue }

                let headerOffset = k + 1
                var p = Parser(b, hit + 3)
                guard let obj = p.parse() else { continue }
                if definedAt[num] ?? -1 <= headerOffset {
                    objects[num] = obj
                    definedAt[num] = headerOffset
                }
                if case .stream(let d, let range) = obj {
                    i = max(i, range.upperBound)
                    if case .name("XRef")? = d["Type"] {                  // xref stream
                        mergeTrailer(d)
                    }
                } else {
                    i = max(i, p.i)
                }
            }

            // Classic trailers, oldest first so the newest /Root wins.
            var t = 0
            while let hit = Parser.find([UInt8]("trailer".utf8), in: b, from: t) {
                var p = Parser(b, hit + 7)
                if case .dict(let d)? = p.parse() { mergeTrailer(d) }
                t = hit + 7
            }

            if trailer["Root"] == nil {
                // No usable trailer: find the catalog by inspection, taking the last
                // one defined (sorted, so the choice cannot vary between runs).
                for num in objects.keys.sorted() {
                    if case .dict(let d)? = objects[num], case .name("Catalog")? = d["Type"] {
                        trailer["Root"] = .ref(num)
                    }
                }
            }
        }

        private func mergeTrailer(_ d: [String: Obj]) {
            for k in ["Root", "Encrypt", "Info", "ID"] where d[k] != nil {
                trailer[k] = d[k]
            }
        }

        /// Objects living inside /ObjStm containers (PDF 1.5+) are invisible to a raw
        /// scan, so each container is inflated and its contents parsed out. They are
        /// then written as ordinary top-level objects, which is always legal.
        private func expandObjectStreams() {
            // Snapshot the containers in file order first: expanding one inserts into
            // `objects`, and the order containers are processed decides which
            // definition of a repeated object number survives.
            let containers: [(offset: Int, dict: [String: Obj], range: Range<Int>)] =
                objects.keys.sorted().compactMap { num in
                    guard case .stream(let d, let range)? = objects[num],
                          case .name("ObjStm")? = d["Type"] else { return nil }
                    return (definedAt[num] ?? 0, d, range)
                }
                .sorted { $0.offset < $1.offset }

            for (containerOffset, d, range) in containers {
                guard case .int(let n)? = resolve(d["N"]),
                      case .int(let first)? = resolve(d["First"]),
                      let payload = decodedStream(dict: d, range: range)
                else { continue }

                var header = Parser(payload, 0)
                var pairs = [(num: Int, offset: Int)]()
                for _ in 0..<n {
                    header.skipWhitespace()
                    guard case .int(let num)? = header.parseNumber() else { break }
                    header.skipWhitespace()
                    guard case .int(let off)? = header.parseNumber() else { break }
                    pairs.append((num, off))
                }
                for (num, off) in pairs where (definedAt[num] ?? -1) < containerOffset {
                    guard first + off < payload.count else { continue }
                    var p = Parser(payload, first + off)
                    if let o = p.parse() {
                        objects[num] = o
                        definedAt[num] = containerOffset
                    }
                }
            }
        }

        // MARK: Resolution

        func resolve(_ o: Obj?) -> Obj? {
            var seen = 0
            var cur = o
            while case .ref(let n)? = cur, seen < 64 {
                cur = objects[n]
                seen += 1
            }
            return cur
        }

        func dict(_ o: Obj?) -> [String: Obj]? {
            switch resolve(o) {
            case .dict(let d): return d
            case .stream(let d, _): return d
            default: return nil
            }
        }

        /// Inflates a stream far enough to read it. Only ever used for /ObjStm
        /// containers — page content is copied without ever being decoded.
        func decodedStream(dict d: [String: Obj], range: Range<Int>) -> [UInt8]? {
            var bytes = Array(b[range])
            var filters = [String]()
            switch resolve(d["Filter"]) {
            case .name(let n): filters = [n]
            case .array(let a): filters = a.compactMap { if case .name(let n) = $0 { return n } else { return nil } }
            default: break
            }
            for f in filters {
                guard f == "FlateDecode" || f == "Fl" else { return nil }
                guard let out = PDFTrim.inflate(bytes) else { return nil }
                bytes = out
            }
            if let parms = dict(d["DecodeParms"]),
               case .int(let predictor)? = resolve(parms["Predictor"]), predictor >= 10 {
                let columns: Int
                if case .int(let c)? = resolve(parms["Columns"]) { columns = c } else { columns = 1 }
                bytes = PDFTrim.undoPNGPredictor(bytes, columns: columns)
            }
            return bytes
        }

        // MARK: Page tree

        /// Page object numbers in document order, with inherited attributes resolved.
        func pageLeaves() throws -> [(num: Int, inherited: [String: Obj])] {
            guard let root = dict(trailer["Root"]) else { throw TrimError.noCatalog }
            guard let pagesRef = root["Pages"] else { throw TrimError.noCatalog }

            var out = [(num: Int, inherited: [String: Obj])]()
            var guardCount = 0
            let inheritable = ["Resources", "MediaBox", "CropBox", "Rotate"]

            func walk(_ node: Obj?, _ inherited: [String: Obj], _ depth: Int) {
                guard depth < 64, guardCount < 200_000 else { return }
                guard let d = dict(node) else { return }
                var passed = inherited
                for key in inheritable where d[key] != nil { passed[key] = d[key] }

                if let kids = resolve(d["Kids"]), case .array(let items) = kids {
                    for kid in items { walk(kid, passed, depth + 1) }
                    return
                }
                // A leaf: no /Kids. /Type is often missing in the wild, so it is not
                // required — anything without kids under the page tree is a page.
                guard case .ref(let num)? = node else { return }
                guardCount += 1
                out.append((num, passed))
            }

            walk(pagesRef, [:], 0)
            return out
        }
    }

    // MARK: - Writer

    /// Builds the output file: walks the object graph from the chosen pages, copies
    /// every object reached, renumbers, and emits a fresh catalog, page tree and xref.
    final class Writer {
        private let doc: Document
        private var mapping: [Int: Int] = [:]      // old object number → new
        private var order: [Int] = []              // old numbers, in emission order

        init(doc: Document) { self.doc = doc }

        func build(selecting leaves: [(num: Int, inherited: [String: Obj])]) throws -> [UInt8] {
            let selected = Set(leaves.map(\.num))

            // 1 is the catalog and 2 the page tree; copied objects start at 3.
            var next = 3
            for leaf in leaves where mapping[leaf.num] == nil {
                mapping[leaf.num] = next
                order.append(leaf.num)
                next += 1
            }

            // Breadth-first over everything the pages reference. Pages, page-tree nodes
            // and catalogs are pruned: a link annotation pointing at a page that was not
            // extracted would otherwise drag the entire document back in. Pruned
            // references are written as `null`, which viewers treat as a dead link —
            // the same thing pdfcpu does.
            var queue = leaves.map(\.num)
            var head = 0
            while head < queue.count {
                let num = queue[head]
                head += 1
                guard let obj = doc.objects[num] else { continue }
                forEachReference(in: obj, skippingPageKeys: selected.contains(num)) { ref in
                    guard mapping[ref] == nil else { return }
                    guard let target = doc.objects[ref] else { return }
                    if isPruned(target) { return }
                    mapping[ref] = next
                    next += 1
                    order.append(ref)
                    queue.append(ref)
                }
            }

            return serialize(leaves: leaves)
        }

        private func isPruned(_ obj: Obj) -> Bool {
            guard case .dict(let d) = obj else { return false }
            if case .name(let t)? = d["Type"], t == "Page" || t == "Pages" || t == "Catalog" {
                return true
            }
            return false
        }

        private func forEachReference(in obj: Obj, skippingPageKeys: Bool, _ visit: (Int) -> Void) {
            switch obj {
            case .ref(let n):
                visit(n)
            case .array(let items):
                for item in items { forEachReference(in: item, skippingPageKeys: false, visit) }
            case .dict(let d), .stream(let d, _):
                for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                    // /Parent is replaced by the new page tree; following it would pull
                    // in the whole original tree.
                    if skippingPageKeys, k == "Parent" { continue }
                    forEachReference(in: v, skippingPageKeys: false, visit)
                }
            default:
                break
            }
        }

        private func serialize(leaves: [(num: Int, inherited: [String: Obj])]) -> [UInt8] {
            var out = [UInt8]("%PDF-1.7\n%\u{00E2}\u{00E3}\u{00CF}\u{00D3}\n".utf8)
            var offsets = [Int: Int]()
            // Object numbers run 1 (catalog), 2 (page tree), then 3...2+order.count,
            // so /Size — and the xref subsection length — is the highest number PLUS
            // ONE. Getting this wrong leaves the final object off the end of the table:
            // it is still in the file, but nothing can look it up. That cost a day —
            // the casualty was a font's ToUnicode map, so the pages rendered perfectly
            // while their text came out as mojibake.
            let size = order.count + 3

            func emit(_ num: Int, _ body: [UInt8]) {
                offsets[num] = out.count
                out += [UInt8]("\(num) 0 obj\n".utf8)
                out += body
                out += [UInt8]("\nendobj\n".utf8)
            }

            // 1: catalog
            emit(1, [UInt8]("<< /Type /Catalog /Pages 2 0 R >>".utf8))

            // 2: page tree
            let kids = leaves.map { "\(mapping[$0.num]!) 0 R" }.joined(separator: " ")
            emit(2, [UInt8]("<< /Type /Pages /Count \(leaves.count) /Kids [\(kids)] >>".utf8))

            // The pages themselves, with /Parent repointed and inherited attributes
            // written explicitly — the originals may have inherited them from a tree
            // node that no longer exists.
            let inheritedByNum = Dictionary(leaves.map { ($0.num, $0.inherited) },
                                            uniquingKeysWith: { a, _ in a })
            for old in order {
                guard let obj = doc.objects[old], let new = mapping[old] else { continue }
                if let inherited = inheritedByNum[old], case .dict(var d) = obj {
                    d["Parent"] = nil
                    for k in inherited.keys.sorted() where d[k] == nil { d[k] = inherited[k] }
                    var body = [UInt8]("<< /Type /Page /Parent 2 0 R".utf8)
                    for k in d.keys.sorted() where k != "Type" {
                        body += [UInt8](" /\(k) ".utf8)
                        body += render(d[k]!)
                    }
                    body += [UInt8](" >>".utf8)
                    emit(new, body)
                } else {
                    emit(new, render(obj))
                }
            }

            // Classic cross-reference table. Object streams would shave a few percent
            // off, but a plain table is readable by everything and this file is already
            // as small as its own content allows.
            let xrefOffset = out.count
            out += [UInt8]("xref\n0 \(size)\n".utf8)
            out += [UInt8]("0000000000 65535 f \n".utf8)
            for num in 1..<size {
                let off = offsets[num] ?? 0
                out += [UInt8](String(format: "%010d 00000 n \n", off).utf8)
            }
            out += [UInt8]("trailer\n<< /Size \(size) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8)
            return out
        }

        /// Serializes an object. Stream payloads are copied straight out of the source
        /// file — never decoded, never re-encoded — which is the whole point.
        private func render(_ obj: Obj) -> [UInt8] {
            switch obj {
            case .null:
                return [UInt8]("null".utf8)
            case .bool(let v):
                return [UInt8]((v ? "true" : "false").utf8)
            case .int(let n):
                return [UInt8]("\(n)".utf8)
            case .real(let d):
                return [UInt8](trimmedReal(d).utf8)
            case .name(let n):
                return [UInt8]("/\(escapeName(n))".utf8)
            case .string(let bytes, let hex):
                return hex ? [0x3C] + bytes + [0x3E] : [0x28] + bytes + [0x29]
            case .array(let items):
                var out: [UInt8] = [0x5B]
                for (k, item) in items.enumerated() {
                    if k > 0 { out.append(0x20) }
                    out += render(item)
                }
                out.append(0x5D)
                return out
            case .dict(let d):
                return renderDict(d)
            case .stream(let d, let range):
                var dd = d
                dd["Length"] = .int(range.count)          // authoritative; may have been indirect
                var out = renderDict(dd)
                out += [UInt8]("\nstream\n".utf8)
                out += doc.b[range]
                out += [UInt8]("\nendstream".utf8)
                return out
            case .ref(let n):
                // A reference to something deliberately not copied becomes null.
                guard let new = mapping[n] else { return [UInt8]("null".utf8) }
                return [UInt8]("\(new) 0 R".utf8)
            }
        }

        private func renderDict(_ d: [String: Obj]) -> [UInt8] {
            var out = [UInt8]("<<".utf8)
            for (k, v) in d.sorted(by: { $0.key < $1.key }) {
                out += [UInt8](" /\(escapeName(k)) ".utf8)
                out += render(v)
            }
            out += [UInt8](" >>".utf8)
            return out
        }

        private func escapeName(_ n: String) -> String {
            var out = ""
            for byte in [UInt8](n.utf8) {
                if Parser.isRegular(byte), byte != 0x23 {
                    out.append(Character(UnicodeScalar(byte)))
                } else {
                    out += String(format: "#%02X", byte)
                }
            }
            return out
        }

        /// PDF has no exponential notation, so "%g" is unsafe: 1e-05 is a syntax
        /// error in a PDF file. Fixed notation, then trailing zeros trimmed.
        private func trimmedReal(_ d: Double) -> String {
            guard d.isFinite else { return "0" }
            if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
            var s = String(format: "%.6f", d)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            return s.isEmpty ? "0" : s
        }
    }

    // MARK: - Flate

    /// PDF's FlateDecode is zlib-wrapped (RFC 1950); Compression's ZLIB algorithm is
    /// raw DEFLATE (RFC 1951), so the two-byte zlib header is skipped when present.
    static func inflate(_ input: [UInt8]) -> [UInt8]? {
        guard input.count > 2 else { return nil }
        var start = 0
        if input[0] & 0x0F == 8, (Int(input[0]) << 8 | Int(input[1])) % 31 == 0 { start = 2 }

        var capacity = max(input.count * 8, 64 * 1024)
        for _ in 0..<6 {
            var out = [UInt8](repeating: 0, count: capacity)
            let written = input[start...].withUnsafeBufferPointer { src -> Int in
                out.withUnsafeMutableBufferPointer { dst in
                    compression_decode_buffer(dst.baseAddress!, capacity,
                                              src.baseAddress!, src.count,
                                              nil, COMPRESSION_ZLIB)
                }
            }
            if written == 0 { return nil }
            if written < capacity {
                out.removeSubrange(written...)
                return out
            }
            capacity *= 4                                   // output filled it exactly: retry bigger
        }
        return nil
    }

    /// Undoes PNG row predictors, which xref and occasionally object streams use.
    static func undoPNGPredictor(_ input: [UInt8], columns: Int) -> [UInt8] {
        let rowLength = max(columns, 1)
        guard input.count > rowLength else { return input }
        var out = [UInt8]()
        out.reserveCapacity(input.count)
        var previous = [UInt8](repeating: 0, count: rowLength)
        var i = 0
        while i + 1 <= input.count - 1 {
            let tag = input[i]
            i += 1
            let available = min(rowLength, input.count - i)
            guard available > 0 else { break }
            var row = Array(input[i..<(i + available)])
            i += available
            switch tag {
            case 1:                                          // Sub
                for k in 1..<row.count { row[k] = row[k] &+ row[k - 1] }
            case 2:                                          // Up
                for k in 0..<row.count { row[k] = row[k] &+ previous[k] }
            case 3:                                          // Average
                for k in 0..<row.count {
                    let left = k > 0 ? Int(row[k - 1]) : 0
                    row[k] = row[k] &+ UInt8((left + Int(previous[k])) / 2 & 0xFF)
                }
            case 4:                                          // Paeth
                for k in 0..<row.count {
                    let a = k > 0 ? Int(row[k - 1]) : 0
                    let b = Int(previous[k])
                    let c = k > 0 ? Int(previous[k - 1]) : 0
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    let pred = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                    row[k] = row[k] &+ UInt8(pred & 0xFF)
                }
            default:                                         // 0 = None
                break
            }
            out += row
            previous = row
        }
        return out
    }
}
