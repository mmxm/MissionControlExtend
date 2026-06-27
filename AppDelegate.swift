import Cocoa
import ServiceManagement

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
            button.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Mission Control Extend")
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
        
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        if #available(macOS 13.0, *) {
            launchItem.state = isLaunchAtLoginEnabled ? .on : .off
        } else {
            launchItem.isEnabled = false
            launchItem.title = "Launch at Login (macOS 13+ required)"
        }
        menu.addItem(launchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
    
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if service.status == .enabled {
                do {
                    try service.unregister()
                    print("Successfully unregistered launch at login service.")
                } catch {
                    print("[Error] Failed to unregister launch at login: \(error.localizedDescription)")
                }
            } else {
                do {
                    try service.register()
                    print("Successfully registered launch at login service.")
                } catch {
                    print("[Error] Failed to register launch at login: \(error.localizedDescription)")
                }
            }
        }
        updateMenu()
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
        
        AccessibilityEngine.shared.logDebug("checkPermissionsAndStart: hasPermissions = \(hasPermissions), isRunning = \(isRunning)")
        
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
