import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusItem: NSStatusItem!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a borderless window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window appearance and position
        window.isOpaque = false
        window.backgroundColor = NSColor.clear
        window.level = .statusBar
        window.hasShadow = false
        
        // Position in the notch area
        if let screen = NSScreen.main {
            let menuBarHeight = NSStatusBar.system.thickness
            let yPos = screen.frame.maxY - menuBarHeight
            let xPos = (screen.frame.width - 400) / 2
            window.setFrame(NSRect(x: xPos, y: yPos, width: 400, height: 22), display: true)
            window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        }
        
        // Register for notifications from music apps
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        // Set SwiftUI content view
        window.contentView = NSHostingView(rootView: ContentView())
        window.makeKeyAndOrderFront(nil)
    }
    
    @objc func appDidActivate(_ notification: Notification) {
        // Always keep the window on top
        window.level = .statusBar
        window.orderFrontRegardless()
    }
}
