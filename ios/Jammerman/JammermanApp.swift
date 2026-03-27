// Jammerman — App Entry Point

import SwiftUI

@main
struct JammermanApp: App {
    @State private var state = JammermanState()

    var body: some Scene {
        WindowGroup {
            Text("Jammerman")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
        }
    }
}
