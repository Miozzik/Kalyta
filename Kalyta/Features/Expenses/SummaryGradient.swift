import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    /// The teal-to-indigo fill of the summary card, which the Home Screen widget shares.
    ///
    /// The start is a darker teal than the system one, so white text on it reaches 4.5:1 (WCAG AA).
    static var summaryGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.45, blue: 0.51), .indigo],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
