// Bayleaf — pull pages out of a PDF, by hand, by typed range, or by asking.
//
// The binary doubles as its own test harness: `--` flags run headless (extract,
// interpret, snapshot, probe) so the core paths are verifiable from a terminal
// without clicking through the UI. No flag → the app.
import AppKit

@main
enum Main {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, first.hasPrefix("--") {
            await CLI.run(args)
            return
        }
        BayleafApp.main()
    }
}
