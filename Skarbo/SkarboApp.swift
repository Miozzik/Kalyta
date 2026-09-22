import SwiftUI

@main
struct SkarboApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(Store.container)
    }
}
