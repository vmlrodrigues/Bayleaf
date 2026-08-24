# Bayleaf

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-brightgreen)
![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1%2B-black?logo=apple&logoColor=white)
![Notarised](https://img.shields.io/badge/Notarised-Developer%20ID-success)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/vmlrodrigues/Bayleaf?label=latest)](https://github.com/vmlrodrigues/Bayleaf/releases/latest)

[![Download for Mac](https://img.shields.io/badge/Download_for_Mac-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/vmlrodrigues/Bayleaf/releases/latest/download/Bayleaf.dmg)

Pull pages out of a PDF — **tap them, type a range, or just ask**, typed or out loud.
The asking is understood on your Mac by Apple Intelligence; nothing you open, say,
or extract ever leaves the machine.

<img src="docs/screenshot.png" width="760"
     alt="Bayleaf with a lecture PDF loaded: pages 3–5 and 9 selected with green rings after asking
          'grab 3 to 5 and page 9', a suggested filename ready, and an Extract 4 pages button.">

Drop a PDF on the window, pick pages any way you like, and Bayleaf writes a new PDF
with just those pages — a sensible filename already suggested, never overwriting
anything. Signed with a Developer ID and notarised by Apple, so Gatekeeper stays quiet.

## Three ways to pick pages

- **Tap** thumbnails — shift-click for a run, or the All · None · Invert · Odd · Even chips
- **Type** a range: `1-3,5,8-10` · `l` for the last page · `3-l` · `odd`
- **Ask** — *"the last three pages"*, *"everything except page 4"*, *"5 to 9 and the
  cover"* — or press the mic and say it. Interpreted on-device; with Apple
  Intelligence switched off, simple phrasings still work.

## Requirements

macOS 26 (Tahoe) or later on Apple Silicon. First use of the mic asks for
microphone and speech-recognition permission — both stay on-device.

## Build from source

    ./Scripts/build.sh          # signed app → dist/Bayleaf.app   (SIGN=0 to skip signing)
    ./Scripts/notarize.sh       # notarised, stapled DMG           (creds: see .env.example)

The binary is its own test harness — try
`.build/release/Bayleaf --interpret "the last three pages" 42`.
Design details live in [SPEC.md](SPEC.md).

---

MIT — see [LICENSE](LICENSE). Made for my daughter. 🌿
