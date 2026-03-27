// Jammerman — App Entry Point

import SwiftUI

@main
struct JammermanApp: App {
    @StateObject private var coordinator = TrackingCoordinator()
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                PerformanceView(coordinator: coordinator)
                    .preferredColorScheme(.dark)

                if showSplash {
                    SplashView(showSplash: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: showSplash)
        }
    }
}
