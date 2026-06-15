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
    
    private init() {
        // Clear previous log on startup
        try? "".write(to: URL(fileURLWithPath: "/tmp/MissionControlExtend.log"), atomically: true, encoding: .utf8)
    }
    
    private func logDebug(_ message: String) {
        let logURL = URL(fileURLWithPath: "/tmp/MissionControlExtend.log")
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: logURL)
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
            let appName = app.localizedName ?? ""
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
                let title = titleValue as? String ?? ""
                
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
        
        let desc = getElementDescription(element)
        let title = getElementTitle(element)
        
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
            let winTitle = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let winOwner = win.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Exact match: "Window Title, App Name" (typical macOS format)
            if !winTitle.isEmpty {
                if cleanDesc == "\(winTitle), \(winOwner)" || cleanDesc == "\(winOwner) — \(winTitle)" || cleanDesc == "\(winOwner) - \(winTitle)" {
                    return win
                }
            }
            
            // 2. Substring match (thumbnail contains window title and app name)
            if !winTitle.isEmpty && cleanDesc.contains(winTitle) && cleanDesc.contains(winOwner) {
                return win
            }
            
            // 3. Fallback: window without title (e.g. calculator, empty Finder, Chrome PWA), matches app name
            if winTitle.isEmpty {
                if cleanDesc == winOwner || cleanDesc.localizedCaseInsensitiveContains(winOwner) {
                    return win
                }
            }
        }
        
        // 4. Prefix/Contains match (handles truncated titles in Mission Control, like Apple Notes)
        for win in openWindows {
            let winTitle = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !winTitle.isEmpty && !cleanDesc.isEmpty {
                // Check if the window title starts with the thumbnail title, or vice-versa
                if winTitle.hasPrefix(cleanDesc) || cleanDesc.hasPrefix(winTitle) {
                    return win
                }
                // Substring fallback for longer descriptions
                if cleanDesc.count >= 4 && winTitle.localizedCaseInsensitiveContains(cleanDesc) {
                    return win
                }
            }
        }
        
        // 5. Soft match by title only
        for win in openWindows {
            let winTitle = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !winTitle.isEmpty && (cleanDesc == winTitle || cleanTitle == winTitle) {
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
    
    private func getElementDescription(_ element: AXUIElement) -> String {
        var desc: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &desc)
        return desc as? String ?? ""
    }
    
    private func getElementTitle(_ element: AXUIElement) -> String {
        var title: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        return title as? String ?? ""
    }
    
    private func getPosition(of element: AXUIElement) -> CGPoint? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }
    
    private func getSize(of element: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
    
    private func findCloseButton(in windowElement: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(windowElement, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return nil
        }
        
        for child in children {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            var subrole: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &subrole)
            
            if let roleStr = role as? String, roleStr == kAXButtonRole {
                if let subroleStr = subrole as? String, subroleStr == kAXCloseButtonSubrole {
                    return child
                }
            }
        }
        return nil
    }
}
