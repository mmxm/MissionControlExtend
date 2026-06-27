import Cocoa
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public struct WindowInfo {
    public let windowID: CGWindowID
    public let title: String
    public let ownerPID: pid_t
    public let ownerName: String
    public let bounds: CGRect
}

public class AccessibilityEngine {
    public static let shared = AccessibilityEngine()
    
    public static let logURL: URL = {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDirectory = libraryURL.appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true, attributes: nil)
        return logsDirectory.appendingPathComponent("com.francois.MissionControlExtend.log")
    }()
    
    private init() {
        // Clear previous log on startup
        try? "".write(to: AccessibilityEngine.logURL, atomically: true, encoding: .utf8)
    }
    
    func logDebug(_ message: String) {
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: AccessibilityEngine.logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: AccessibilityEngine.logURL)
            }
        }
    }
    
    // Checks if the application has accessibility permissions
    public func checkAccessibilityPermissions(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            return AXIsProcessTrusted()
        }
    }
    
    // Retrieves a list of all visible windows directly via the Accessibility API
    public func getOpenWindows() -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        let runningApps = NSWorkspace.shared.runningApplications
        logDebug("getOpenWindows: Found \(runningApps.count) running apps in total.")
        
        for app in runningApps {
            // Only query standard GUI applications that appear in Mission Control
            guard app.activationPolicy == .regular else { continue }
            
            let appPID = app.processIdentifier
            let appName = (app.localizedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let appRef = AXUIElementCreateApplication(appPID)
            
            var windowsValue: AnyObject?
            let err = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
            if err != .success {
                logDebug("getOpenWindows: [Warning] Could not get windows for \(appName) (PID \(appPID)), error: \(err.rawValue)")
                continue
            }
            
            guard let appWindows = windowsValue as? [AXUIElement] else {
                logDebug("getOpenWindows: [Warning] kAXWindowsAttribute for \(appName) was not an array.")
                continue
            }
            
            logDebug("getOpenWindows: \(appName) (PID \(appPID)) has \(appWindows.count) windows.")
            
            for winRef in appWindows {
                var winID: CGWindowID = 0
                _ = _AXUIElementGetWindow(winRef, &winID)
                
                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(winRef, kAXTitleAttribute as CFString, &titleValue)
                let title = (titleValue as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                var posValue: AnyObject?
                var pos = CGPoint.zero
                if AXUIElementCopyAttributeValue(winRef, kAXPositionAttribute as CFString, &posValue) == .success {
                    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
                }
                
                var sizeValue: AnyObject?
                var size = CGSize.zero
                if AXUIElementCopyAttributeValue(winRef, kAXSizeAttribute as CFString, &sizeValue) == .success {
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                }
                let bounds = CGRect(origin: pos, size: size)
                
                logDebug("getOpenWindows: Window found -> App: \(appName), Title: '\(title)', ID: \(winID), Bounds: \(bounds)")
                windows.append(WindowInfo(windowID: winID, title: title, ownerPID: appPID, ownerName: appName, bounds: bounds))
            }
        }
        logDebug("getOpenWindows: Returning \(windows.count) open windows.")
        return windows
    }
    
    // Recursively traverses the Dock's accessibility tree to gather thumbnails and their coordinates
    public func findMissionControlThumbnails() -> [(element: AXUIElement, window: WindowInfo, bounds: CGRect)] {
        guard checkAccessibilityPermissions(prompt: false) else { return [] }
        
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        guard let dockApp = apps.first else { return [] }
        let dockRef = AXUIElementCreateApplication(dockApp.processIdentifier)
        
        let openWindows = getOpenWindows()
        var results: [(element: AXUIElement, window: WindowInfo, bounds: CGRect)] = []
        
        findThumbnailsRecursive(in: dockRef, openWindows: openWindows, results: &results)
        logDebug("findMissionControlThumbnails: Found \(results.count) matched thumbnails.")
        return results
    }
    
    private func findThumbnailsRecursive(in element: AXUIElement, openWindows: [WindowInfo], results: inout [(element: AXUIElement, window: WindowInfo, bounds: CGRect)]) {
        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String ?? ""
        
        // Ignore static Dock bar elements to speed up traversal
        if role == "AXDockItem" {
            return
        }
        
        let desc = getStringAttribute(element, kAXDescriptionAttribute)
        let title = getStringAttribute(element, kAXTitleAttribute)
        
        if !desc.isEmpty || !title.isEmpty {
            logDebug("findThumbnailsRecursive: Inspected element Role: \(role), Title: '\(title)', Desc: '\(desc)'")
            if let matchedWindow = matchElement(element, description: desc, title: title, openWindows: openWindows) {
                if let pos = getPosition(of: element), let size = getSize(of: element) {
                    let bounds = CGRect(origin: pos, size: size)
                    logDebug("findThumbnailsRecursive: Match found! App: \(matchedWindow.ownerName), Title: '\(matchedWindow.title)', Bounds: \(bounds)")
                    // Filter out tiny hover zones or off-screen elements
                    if bounds.width > 50 && bounds.height > 50 {
                        results.append((element, matchedWindow, bounds))
                        // Once matched, no need to inspect this thumbnail's children
                        return
                    }
                }
            }
        }
        
        var childrenValue: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
        if error == .success, let children = childrenValue as? [AXUIElement] {
            for child in children {
                findThumbnailsRecursive(in: child, openWindows: openWindows, results: &results)
            }
        }
    }
    
    // Performs a robust match between the Dock element description and open windows
    private func matchElement(_ element: AXUIElement, description: String, title: String, openWindows: [WindowInfo]) -> WindowInfo? {
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        for win in openWindows {
            // 1. Exact match: "Window Title, App Name" (typical macOS format)
            if !win.title.isEmpty {
                if cleanDesc == "\(win.title), \(win.ownerName)" || cleanDesc == "\(win.ownerName) — \(win.title)" || cleanDesc == "\(win.ownerName) - \(win.title)" {
                    return win
                }
                
                // 2. Substring match (thumbnail contains window title and app name)
                if cleanDesc.contains(win.title) && cleanDesc.contains(win.ownerName) {
                    return win
                }
            } else {
                // 3. Fallback: window without title (e.g. calculator, empty Finder, Chrome PWA)
                if cleanDesc == win.ownerName || cleanDesc.localizedCaseInsensitiveContains(win.ownerName) {
                    return win
                }
            }
        }
        
        // 4. Prefix/Contains match (handles truncated titles in Mission Control, like Apple Notes)
        for win in openWindows {
            if !win.title.isEmpty && !cleanDesc.isEmpty {
                // Check if the window title starts with the thumbnail title, or vice-versa
                if win.title.hasPrefix(cleanDesc) || cleanDesc.hasPrefix(win.title) {
                    return win
                }
                // Substring fallback for longer descriptions
                if cleanDesc.count >= 4 && win.title.localizedCaseInsensitiveContains(cleanDesc) {
                    return win
                }
            }
        }
        
        // 5. Soft match by title only
        for win in openWindows {
            if !win.title.isEmpty && (cleanDesc == win.title || cleanTitle == win.title) {
                return win
            }
        }
        
        return nil
    }
    
    // Closes the specified window using multiple fallback mechanisms
    public func closeWindow(_ window: WindowInfo) -> Bool {
        let appRef = AXUIElementCreateApplication(window.ownerPID)
        logDebug("closeWindow: Attempting to close window ID \(window.windowID) of \(window.ownerName) (PID \(window.ownerPID))")
        
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            logDebug("closeWindow: [Error] Unable to list window elements for application with PID \(window.ownerPID)")
            return false
        }
        
        for winRef in windows {
            var isTarget = false
            var currentWinID: CGWindowID = 0
            
            if _AXUIElementGetWindow(winRef, &currentWinID) == .success {
                if currentWinID == window.windowID && currentWinID != 0 {
                    isTarget = true
                }
            } else {
                // Fallback: title comparison if the AXWindowID attribute is not available
                var titleValue: AnyObject?
                if AXUIElementCopyAttributeValue(winRef, kAXTitleAttribute as CFString, &titleValue) == .success,
                   let titleStr = titleValue as? String, titleStr == window.title {
                    isTarget = true
                }
            }
            
            if isTarget {
                // Method 1: Click the native close button (AXPress)
                if let closeButton = findCloseButton(in: winRef) {
                    let error = AXUIElementPerformAction(closeButton, "AXPress" as CFString)
                    logDebug("closeWindow: Tried AXPress on close button -> result: \(error.rawValue)")
                    if error == .success { return true }
                }
                
                // Method 2: Fallback to AXCancel action directly on the window
                let cancelError = AXUIElementPerformAction(winRef, "AXCancel" as CFString)
                logDebug("closeWindow: Tried AXCancel on window -> result: \(cancelError.rawValue)")
                if cancelError == .success { return true }
                
                // Method 3: Fallback to AXClose action directly on the window
                let closeActionError = AXUIElementPerformAction(winRef, "AXClose" as CFString)
                logDebug("closeWindow: Tried AXClose on window -> result: \(closeActionError.rawValue)")
                if closeActionError == .success { return true }
                
                logDebug("closeWindow: [Error] Could not close window ID \(window.windowID) using AXPress, AXCancel, or AXClose actions.")
            }
        }
        return false
    }
    
    // Gracefully terminates the application
    public func quitApplication(of window: WindowInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.ownerPID) else { return false }
        return app.terminate()
    }
    
    // Accessibility attribute retrieval helpers
    
    private func getStringAttribute(_ element: AXUIElement, _ attribute: String) -> String {
        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String ?? ""
    }
    
    private func getPosition(of element: AXUIElement) -> CGPoint? {
        var v: AnyObject?, p = CGPoint.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &v) == .success else { return nil }
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }
    
    private func getSize(of element: AXUIElement) -> CGSize? {
        var v: AnyObject?, s = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &v) == .success else { return nil }
        AXValueGetValue(v as! AXValue, .cgSize, &s)
        return s
    }
    
    private func findCloseButton(in windowElement: AXUIElement) -> AXUIElement? {
        var val: AnyObject?
        guard AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &val) == .success,
              let children = val as? [AXUIElement] else { return nil }
        
        return children.first { child in
            var role: AnyObject?, subrole: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subrole)
            return (role as? String) == kAXButtonRole && (subrole as? String) == kAXCloseButtonSubrole
        }
    }
}
