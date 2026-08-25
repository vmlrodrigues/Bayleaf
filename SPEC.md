# Bayleaf — spec

Pull pages out of a PDF, three ways that all land in the same place: tap thumbnails,
type a range, or ask in plain English — typed or spoken. Built for my daughter, who does
this constantly at uni and deserves better than a terminal.

Named **Bayleaf**: a leaf *is* a page (folium), and the bay leaf is the good bit
you fish out and keep. Tagline: *Takes a leaf out of anything.*

Namesake, noted and accepted: bayleafapp.com is an unrelated iOS social-cooking
app. Victor intends public distribution (outside the App Store), so the name was
checked at trademark level, not just app-store level: no registered "BAYLEAF"
software mark surfaced (US or AU), the cooking app's own site claims no ™/® and
names no company, "bay leaf" is a weak common-word mark, and the products don't
overlap. The Homebrew namespace (`bayleaf`) is also unclaimed. Kept with
confidence; the demonstrated ~30-minute rename is the entire downside if anyone
ever objects. The App Store specifically would still warrant a fresh look —
that's the one storefront the namesake actually lives in.

## Principles

1. **Local to the bone.** PDF parsing (PDFKit), speech (SFSpeechRecognizer,
   on-device forced), language understanding (FoundationModels — Apple Intelligence's
   on-device model). No network entitlement exists in the binary. The empty screen
   says so, because it's a feature.
2. **Three inputs, one selection.** Grid taps, the range field, and Ask all read and
   write the same `Set<Int>`. Ask writes the range field; the range field lights up
   the grid; the grid rewrites the range field in canonical form. There is no mode.
3. **Never destructive.** Extraction copies pages into a new document. Output names
   are auto-uniqued (`name 2.pdf`) rather than overwriting. The source is read-only.
4. **Degrade, don't die.** AI off → deterministic parsing still answers the common
   phrasings, labelled honestly in the UI.

## The selection grammar

Compatible with the `pdftools` Go CLI this app replaces (pdfcpu grammar), plus sugar:

| form | meaning |
|---|---|
| `5` | single page |
| `1-3,5,8-10` | comma-separated mix |
| `1-` / `-3` | open at either end |
| `3-l` | page 3 to the last |
| `l` | the last page |
| `l-3` | last page minus 3 (**pdfcpu quirk kept deliberately** — on 10pp this is page 7) |
| `odd` / `even` | parity |

Errors are teaching errors: `page 99 — the PDF only has 10 pages`, `'5-2' is backwards`.

## Ask — the Apple Intelligence design

Three tiers, cheapest first:

1. **Deterministic** — mechanical asks answered by code, no model: `odd`/`even`/
   "everything" (guarded: any digits or carve-out words route to the model). A
   language model has no business enumerating odd numbers.
2. **Model as translator** — FoundationModels *translates* the request into the same
   compact notation the Pages field uses (`"1,5-9"`), via guided generation
   (`@Generable`), greedy sampling. Carve-outs get their own `exclude` field and the
   subtraction happens in code. The output must survive `PageGrammar.parse` — the
   model cannot invent structure, only notation.
3. **Fallback parser** — if the model is unavailable *or its answer doesn't parse*,
   a consuming regex parser handles the common phrasings. Patterns eat the text they
   match so "last 3 pages" can't also yield page 3.

Learned the hard way (all reproduced in `--interpret` before fixing):
- Few-shot examples with concrete numbers **leak into answers** on a small model —
  the instruction example `(19,20)` appeared verbatim in an unrelated answer. The
  prompt now has exactly one notation example.
- Asking for structured ranges invited run-merging ("5 to 9 and the cover" → 1-9).
  Translation-to-DSL + hard validation fixed it.
- Complement arithmetic ("everything except 4") is unreliable in-model; the
  `exclude` field moved it into code.

Verified end-to-end on-device (all 12 correct):

| utterance (42pp unless noted) | result | via |
|---|---|---|
| "um, can you get me pages five to nine, and also the cover please" | `1,5-9` | fallback¹ |
| "the last three pages" | `40-42` | model |
| "everything except page 4" (10pp) | `1-3,5-10` | model |
| "3 to 7 but not 5" (20pp) | `3-4,6-7` | model |
| "all of it without the last page" (15pp) | `1-14` | model |
| "the first two and the last two" (30pp) | `1-2,29-30` | fallback¹ |
| "odd pages only" (8pp) | `1,3,5,7` | deterministic |
| "the whole thing" (12pp) | `1-12` | deterministic |
| "the intro and the last chapter, say pages 1 to 4 and 38 to 42" | `1-4,38-42` | model |
| "give me half of it, the front half" (20pp) | `1-10` | model |

¹ model answer failed validation; tier 3 caught it with the right answer — the
degradation path working as designed, invisible to the user.

## Dictation

Push-to-talk, not always-listening: mic button starts, click again (or a natural
pause finalising the result) stops and submits to Ask. `SFSpeechRecognizer` with
`requiresOnDeviceRecognition` wherever supported (en_AU: yes). Live partial
transcript shows under the field while recording. Both privacy prompts have
human-written usage strings. Upgrade path: the SpeechAnalyzer/SpeechTranscriber API
(macOS 26) for better long-form accuracy.

## Filename suggestion

`<source base> – pages <canonical selection>.pdf` (`– page N` when single), updated
live as the selection changes — **until** the field diverges from the suggestion,
after which the user's text wins and a ↺ button restores the suggestion.
`filenameEdited` is *computed* (`filename != lastSuggested`), so there's no flag to
get stale. Slashes and colons sanitised. Saves next to the original by default;
folder picker to change; auto-unique on collision.

## UX inventory

- **Empty state**: full-window drop target, dashed well, ⌘O, gradient CTA, privacy line.
- **Grid**: click toggles; shift-click extends from last click; per-page rings +
  checkmarks; unselected pages dim when a selection exists (the grid previews the
  output); page numbers under each thumbnail.
- **Chips**: All · None · Invert · Odd · Even. "N of M pages selected" counter.
- **Ask card**: text field + mic; status line (green dot "Apple Intelligence ·
  on-device" / amber "AI off — simple phrases still work"); busy spinner; notes when
  the quick parser answered.
- **Save card**: filename field (+↺), destination chip, gradient **Extract N pages**
  button (⌘E).
- **Toasts**: success with **Reveal** (selects the file in Finder), failure, info.
  Auto-dismiss 6s.
- **Menu**: ⌘O open, ⌘E extract, ⇧⌘A select all pages, clear selection, Check for Updates.
- **Toolbar**: a real unified `NSToolbar` (`.windowToolbarStyle(.unified(showsTitle:
  false))`), the same thing Mud does with `window.toolbarStyle = .unified`. Brand at
  the leading edge, Open and Extract as icon buttons at the trailing edge, separated
  by a `ToolbarSpacer(.flexible)` — without that spacer, `.primaryAction` items sit
  next to the brand instead of at the trailing edge, because hiding the title removes
  the flexible gap the toolbar would otherwise split on.

  This replaced a hand-rolled header row, twice. The first attempt just trimmed the
  header's padding, which missed the point: under `.hiddenTitleBar` the window still
  reserves the traffic-light strip as safe area, so *any* content row lands beneath
  it and the chrome is two rows tall (~53pt measured) no matter how tight the
  padding. A toolbar puts the brand on the same row as the traffic lights — one row,
  ~34pt, measured identical to Mud's in the same screen region. Do not reintroduce a
  header view in the content area.
- Drag & drop accepts a PDF over any state. Finder "Open With → Bayleaf" works
  (CFBundleDocumentTypes, rank Alternate — never steals Preview's default).
- Deliberate: dark-only visual identity for the prototype (`preferredColorScheme(.dark)`).

## Extraction: why PDFKit cannot write the file

**Quartz's PDF writer re-renders pages; it does not copy them.** When a page uses
Type 3 fonts — glyphs defined as little content streams, which is what scanner and
OCR pipelines emit — it cannot re-embed them, so it inlines every glyph's outline
into the page. Measured on a real 2,152-page scanned law textbook (12.7 MB, 213
Type 3 fonts), extracting pages 450–520:

| route | size | text |
|---|---|---|
| source, those 71 pages' share | ~430 KB | 27,251 words |
| PDFKit copy pages into a new document | **30.8 MB** | **0 words** |
| PDFKit remove-the-other-pages | 30.9 MB | 0 words |
| `CGContext.drawPDFPage` | 30.8 MB | 0 words |
| pdfcpu (the CLI this app replaces) | 436 KB | 27,251 words |
| **PDFTrim (what Bayleaf does now)** | **504 KB** | **27,251 words** |

All three Apple routes produce identical damage — 22,229 Bézier curves and zero text
operators per page — so this is the Quartz writer, not one API's quirk. Losing the
text is the serious half: a law student cannot search or quote her own extract.

`PDFTrim.swift` therefore does what pdfcpu does: parse the file, walk the object
graph from the selected pages, and copy every object it reaches **byte for byte**,
renumbering as it goes. Content streams are never decoded. Notes:

- **The object table is rebuilt by scanning, not read from the xref.** Broken, stale
  and hybrid cross-reference tables are common in exactly the scanned files this is
  for. The scan steps over stream payloads, so binary data shaped like `12 0 obj`
  cannot shadow a real object, and later definitions win — which is what an
  incremental update means. Objects inside `/ObjStm` containers are inflated out and
  written as ordinary objects; they inherit the container's offset for precedence.
- **Pruning.** Page, Pages and Catalog references are not followed — a link
  annotation pointing at a page that wasn't extracted would otherwise drag the whole
  document back in. Pruned references are written as `null`, as pdfcpu does.
  Inherited `/Resources`, `/MediaBox`, `/CropBox` and `/Rotate` are resolved and
  written explicitly onto each page, since the tree node they came from is gone.
- **Encrypted documents are refused** (`TrimError.encrypted`) and fall back to
  PDFKit, which does its own decryption. Verbatim copying of ciphered streams would
  produce garbage.

Three bugs this cost, all now regression-covered by `--verify`:

1. **xref off-by-one.** `/Size` and the table length were the highest object number
   rather than that plus one, so the *last* object was in the file but unreachable.
   It happened to be a font's ToUnicode map: pages rendered perfectly while their
   text came out as mojibake. Renders are not evidence that a PDF is correct.
2. **Nondeterminism.** Container precedence and dictionary emission both came from
   unordered Swift dictionaries, so the same input produced different bytes each run.
   Everything order-sensitive is now sorted; five consecutive runs are byte-identical.
3. **Stream truncation.** The EOL before `endstream` was trimmed even when `/Length`
   was authoritative, corrupting any stream whose data happened to end in 0x0A.

## Architecture

SPM executable (no .xcodeproj), ClawBar's mold: `Scripts/build.sh` assembles and
signs the bundle; `swift build` does the compiling.

```
Sources/Bayleaf/
  Main.swift          @main; routes --flags to CLI, else launches the app
  PDFTrim.swift       verbatim object-graph extraction (parser, scanner, writer)
  CLI.swift           headless: --probe-ai / --interpret / --interpret-basic /
                      --extract / --snapshot
  PageGrammar.swift   parse/format, pure
  Extractor.swift     PDFTrim first, PDFKit fallback for encrypted/unparseable
  Interpreter.swift   3-tier NL → pages (FoundationModels + fallbacks)
  Dictation.swift     SFSpeechRecognizer push-to-talk
  AppModel.swift      @MainActor ObservableObject singleton; all state
  Snapshot.swift      ImageRenderer → PNGs of real views (headless)
  BayleafApp.swift    scene, menu commands, NSApplicationDelegate for file opens
  Views/              Theme, Components, EmptyState, PageGrid, Sidebar, Main
```

The CLI modes are the test suite: grammar and extraction verified against the Go
CLI's outputs for all ten forms; the interpreter table above; error paths. Snapshot
mode re-renders the real SwiftUI views headless (ScrollView/TextField swapped for
eager/static stand-ins — ImageRenderer can't drive either).

## Build, signing, notarisation

- `./Scripts/build.sh` — release build, Developer ID auto-detected, hardened
  runtime + `com.apple.security.device.audio-input` entitlement (mic under hardened
  runtime). `SIGN=0` for local iteration.
- `./Scripts/notarize.sh` — ClawBar's mechanism verbatim: App Store Connect API key
  from `.env` (falls back to `../ClawBar/.env` — same Apple account), two-stage
  (staple the .app, then ship it inside a notarised, stapled DMG), Gatekeeper
  assessment at the end.
- `Scripts/make-icon.swift` — programmatic icon (page + bay leaf on deep green),
  all ten iconset sizes re-drawn, ClawBar-style.
- **Sparkle 2 auto-updates** (from 0.1.1): appcast.xml lives in this public repo,
  served raw from GitHub; DMGs are release assets. EdDSA key in the login keychain
  (account "Bayleaf"); `Scripts/appcast.sh` signs the DMG and updates the feed,
  carrying over ClawBar's full set of release guards (clean tree, VERSION at HEAD,
  BUILD = commit count, HEAD pushed) — each one paid for by a real ClawBar mishap.

## Requirements — a decision, not an accident

**Apple Silicon + macOS 26 (Tahoe) + Apple Intelligence enabled.** FoundationModels
is the centrepiece and exists nowhere else. Back-deployment to Sequoia is possible
(availability-guard the AI, weak-link the framework) at the cost of shipping the app
with its centrepiece missing — do it only if her machine turns out to be older.
If Apple Intelligence is merely switched off, the app still works (tier 1 + 3).

## Cut from the prototype, spec'd for later

- **Reordering** (drag pages into a tray to build the output order — the engine
  already preserves order; the UI doesn't expose it)
- Drag the result out of the app (file promise) instead of/alongside Extract
- Page rotation and deletion-by-exception workflows
- Multi-document session (merge pages from several PDFs)
- Encrypted-PDF unlock flow (currently: friendly refusal)
- System light/dark theme, reduced-transparency audit
- AI-suggested *semantic* filenames from extracted text ("Week 5 — Calvin cycle.pdf")
- Sparkle auto-updates once it leaves prototype
- App Sandbox (drag/open-panel flows are sandbox-shaped already; add before any
  wider distribution)
