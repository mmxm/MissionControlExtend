import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var permissionCheckTimer: Timer?
    private var isRunning = false
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        checkPermissionsAndStart()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Mission Control Extend")
            } else {
                button.title = "✕"
            }
            button.imagePosition = .imageLeft
        }
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Mission Control Extend", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let hasPermissions = AccessibilityEngine.shared.checkAccessibilityPermissions(prompt: false)
        let permTitle = hasPermissions ? "✓ Accessibility Permissions" : "⚠️ Grant Accessibility Permissions..."
        let permItem = NSMenuItem(title: permTitle, action: #selector(handlePermissionsAction), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func handlePermissionsAction() {
        _ = AccessibilityEngine.shared.checkAccessibilityPermissions(prompt: true)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func checkPermissionsAndStart() {
        let hasPermissions = AccessibilityEngine.shared.checkAccessibilityPermissions(prompt: false)
        updateMenu()
        
        let logURL = URL(fileURLWithPath: "/Users/francois/Documents/Mission control plus/debug.log")
        let logLine = "\(Date()): checkPermissionsAndStart: hasPermissions = \(hasPermissions), isRunning = \(isRunning)\n"
        if let data = logLine.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logURL)
            }
        }
        
        if hasPermissions {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            
            if !isRunning {
                isRunning = true
                print("Accessibility permissions granted. Initializing controllers...")
                MissionControlDetector.shared.start()
                OverlayWindowController.shared.start()
            }
        } else {
            // Keep checking periodically every 2.0 seconds until permissions are granted
            if permissionCheckTimer == nil {
                print("Accessibility permissions missing. Waiting for user authorization...")
                permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                    self?.checkPermissionsAndStart()
                }
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        MissionControlDetector.shared.stop()
        OverlayWindowController.shared.stop()
    }
}
