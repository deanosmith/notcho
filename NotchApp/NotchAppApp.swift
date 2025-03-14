import SwiftUI

@main
struct NotchAppApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 0, height: 0)
                .hidden()
        }
    }
}
