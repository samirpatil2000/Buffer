import SwiftUI

@main
struct BufferApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene - we're a menu bar only app
        Settings {
            EmptyView()
        }
    }
}
