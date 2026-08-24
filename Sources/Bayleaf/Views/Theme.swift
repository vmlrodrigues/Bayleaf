import SwiftUI

// One place for the look. Dark, botanical, a bit of shine — designed for someone
// who'd otherwise be doing this in a terminal at 11pm before a tute.
enum Theme {
    static let leafA = Color(red: 0.15, green: 0.80, blue: 0.48)   // emerald
    static let leafB = Color(red: 0.65, green: 0.95, blue: 0.66)   // mint

    static let accentGradient = LinearGradient(
        colors: [leafA, leafB], startPoint: .topLeading, endPoint: .bottomTrailing)

    static let background = LinearGradient(
        colors: [Color(red: 0.075, green: 0.10, blue: 0.09),
                 Color(red: 0.035, green: 0.055, blue: 0.06)],
        startPoint: .top, endPoint: .bottom)

    static let card = Color.white.opacity(0.05)
    static let cardStroke = Color.white.opacity(0.09)
    static let dimText = Color.white.opacity(0.55)
}
