// Jammerman — App Entry Point

import SwiftUI

@main
struct JammermanApp: App {
    @StateObject private var coordinator = TrackingCoordinator()

    var body: some Scene {
        WindowGroup {
            PerformanceView(coordinator: coordinator)
                .preferredColorScheme(.dark)
        }
    }
}
