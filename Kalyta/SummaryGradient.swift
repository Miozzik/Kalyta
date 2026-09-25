import SwiftUI

extension ShapeStyle where Self == LinearGradient {
    /// The teal-to-indigo fill of the summary card, which the Home Screen widget shares.
    static var summaryGradient: LinearGradient {
        LinearGradient(colors: [.teal, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
