import Cocoa

public class MissionControlDetector {
    public static let shared = MissionControlDetector()
    
    private var timer: Timer?
    private var isCurrentlyActive = false
    
    // Callback triggered when the Mission Control state changes
    public var onStateChange: ((Bool) -> Void)?
    
    // Callback triggered at each refresh cycle with the found thumbnails
    public var onUpdate: (([(element: AXUIElement, window: WindowInfo, bounds: CGRect)]) -> Void)?
    
    private init() {}
    
    public func start() {
        // Stop any existing timer
        stop()
        
        // Schedule verification check every 150 ms
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkState()
        }
    }
    
    public func stop() {
        timer?.invalidate()
        timer = nil
        isCurrentlyActive = false
    }
    
    private func checkState() {
        let thumbnails = AccessibilityEngine.shared.findMissionControlThumbnails()
        let active = !thumbnails.isEmpty
        
        if active != isCurrentlyActive {
            isCurrentlyActive = active
            onStateChange?(active)
        }
        
        if active {
            onUpdate?(thumbnails)
        }
    }
}
