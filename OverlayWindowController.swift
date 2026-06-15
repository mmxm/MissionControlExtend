import Cocoa

class CloseButtonPanel: NSPanel {
    init(contentRect: NSRect, onClick: @escaping () -> Void) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        
        self.level = .screenSaver // High level to float on top of Mission Control
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = true // Pass click events to the low-level event tap
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let buttonView = CloseButtonView(frame: NSRect(origin: .zero, size: contentRect.size))
        buttonView.onClick = onClick
        self.contentView = buttonView
    }
}

public class OverlayWindowController {
    public static let shared = OverlayWindowController()
    
    private var buttonPanels: [CGWindowID: CloseButtonPanel] = [:]
    private var activeThumbnails: [(element: AXUIElement, window: WindowInfo, bounds: CGRect)] = []
    private var globalKeyMonitor: Any?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private init() {}
    
    // Starts monitoring Mission Control events and key/mouse events
    public func start() {
        MissionControlDetector.shared.onStateChange = { [weak self] active in
            self?.handleMissionControlStateChange(active)
        }
        
        MissionControlDetector.shared.onUpdate = { [weak self] thumbnails in
            self?.updateOverlays(with: thumbnails)
        }
        
        startKeyMonitoring()
        startMouseTap()
    }
    
    // Stops monitoring and clears overlays
    public func stop() {
        stopKeyMonitoring()
        stopMouseTap()
        clearAllOverlays()
    }
    
    private func handleMissionControlStateChange(_ active: Bool) {
        if !active {
            clearAllOverlays()
        }
    }
    
    private func updateOverlays(with thumbnails: [(element: AXUIElement, window: WindowInfo, bounds: CGRect)]) {
        self.activeThumbnails = thumbnails
        
        // Window IDs present in the current update
        let currentWindowIDs = Set(thumbnails.map { $0.window.windowID })
        
        // Remove overlays for windows that no longer exist
        for (winID, panel) in buttonPanels {
            if !currentWindowIDs.contains(winID) {
                panel.close()
                buttonPanels.removeValue(forKey: winID)
            }
        }
        
        // Add or move overlays for each window thumbnail
        for thumb in thumbnails {
            let winID = thumb.window.windowID
            let bounds = thumb.bounds
            
            // Convert CoreGraphics coords (y=0 at top) to AppKit screen coords (y=0 at bottom)
            let appKitRect = convertToAppKitCoords(bounds)
            
            // Calculate close button position (top-left of the thumbnail)
            // Button is 24x24 px. Center it exactly on the top-left corner.
            let buttonSize: CGFloat = 24
            let buttonFrame = CGRect(
                x: appKitRect.minX - (buttonSize / 2),
                y: appKitRect.maxY - (buttonSize / 2),
                width: buttonSize,
                height: buttonSize
            )
            
            if let panel = buttonPanels[winID] {
                // Move the overlay panel to follow animation or drag movement
                panel.setFrame(buttonFrame, display: true)
            } else {
                // Create a visual indicator panel (clicks are handled by the low-level event tap)
                let panel = CloseButtonPanel(contentRect: buttonFrame) {}
                panel.orderFront(nil)
                buttonPanels[winID] = panel
            }
        }
    }
    
    private func clearAllOverlays() {
        for panel in buttonPanels.values {
            panel.close()
        }
        buttonPanels.removeAll()
        activeThumbnails.removeAll()
    }
    
    // Converts global macOS screen coordinates (y=0 at top) to standard AppKit screen coordinates (y=0 at bottom)
    private func convertToAppKitCoords(_ rect: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first else { return rect }
        let screenHeight = screen.frame.height
        let appKitY = screenHeight - rect.origin.y - rect.size.height
        return CGRect(x: rect.origin.x, y: appKitY, width: rect.size.width, height: rect.size.height)
    }
    
    // Monitors global keyboard shortcuts when Mission Control is active
    private func startKeyMonitoring() {
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobalKeyDown(event)
        }
    }
    
    private func stopKeyMonitoring() {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }
    
    private func handleGlobalKeyDown(_ event: NSEvent) {
        // Only trigger shortcuts if overlays are active (Mission Control is visible)
        guard !buttonPanels.isEmpty else { return }
        
        // Command (⌘) modifier is required
        guard event.modifierFlags.contains(.command) else { return }
        
        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard char == "w" || char == "q" else { return }
        
        // Current cursor screen position
        let mouseLoc = NSEvent.mouseLocation
        
        // Find which thumbnail is currently hovered
        if let hoveredThumb = activeThumbnails.first(where: {
            let appKitRect = convertToAppKitCoords($0.bounds)
            return appKitRect.contains(mouseLoc)
        }) {
            if char == "w" {
                print("Shortcut ⌘W detected on: '\(hoveredThumb.window.title)' -> closing window")
                _ = AccessibilityEngine.shared.closeWindow(hoveredThumb.window)
            } else if char == "q" {
                print("Shortcut ⌘Q detected on: '\(hoveredThumb.window.ownerName)' -> quitting application")
                _ = AccessibilityEngine.shared.quitApplication(of: hoveredThumb.window)
            }
        }
    }
    
    // Low-level mouse event tap to intercept and handle clicks on the close buttons
    private func startMouseTap() {
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .leftMouseDown {
                    let location = event.location
                    if OverlayWindowController.shared.handleMouseClick(at: location) {
                        return nil // Swallow the click event
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )
        
        guard let tap = eventTap else {
            print("[Error] Failed to create CGEventTap for mouse clicks.")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("CGEventTap mouse monitor started successfully.")
        }
    }
    
    private func stopMouseTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }
    
    // Handles left mouse click in CoreGraphics screen coordinates
    public func handleMouseClick(at location: CGPoint) -> Bool {
        guard !buttonPanels.isEmpty else { return false }
        
        for thumb in activeThumbnails {
            let bounds = thumb.bounds // CoreGraphics coordinates (y=0 at top)
            let buttonSize: CGFloat = 24
            
            // Re-create the close button rect in CoreGraphics coordinates
            let closeButtonRect = CGRect(
                x: bounds.minX - (buttonSize / 2),
                y: bounds.minY - (buttonSize / 2),
                width: buttonSize,
                height: buttonSize
            )
            
            if closeButtonRect.contains(location) {
                print("Click intercepted: closing window '\(thumb.window.title)'")
                _ = AccessibilityEngine.shared.closeWindow(thumb.window)
                return true // Swallow the click event so Mission Control doesn't register it
            }
        }
        return false
    }
}
