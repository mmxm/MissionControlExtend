import Cocoa

public class CloseButtonView: NSView {
    private var isHovered = false {
        didSet {
            needsDisplay = true
        }
    }
    
    public var onClick: (() -> Void)?
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        let trackingArea = NSTrackingArea(rect: bounds,
                                          options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                          owner: self,
                                          userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }
    
    public override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
    
    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onClick?()
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw standard shadow for the button
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor(white: 0, alpha: 0.25).cgColor)
        
        // Draw white circle
        let buttonRect = bounds.insetBy(dx: 2, dy: 2)
        context.setFillColor(isHovered ? NSColor(white: 0.92, alpha: 1.0).cgColor : NSColor.white.cgColor)
        context.fillEllipse(in: buttonRect)
        context.restoreGState()
        
        // Subtle grey border to contrast with white backgrounds
        context.setStrokeColor(NSColor(white: 0.8, alpha: 0.6).cgColor)
        context.setLineWidth(0.5)
        context.strokeEllipse(in: buttonRect)
        
        // Draw the cross symbol (X)
        let crossColor = NSColor(white: 0.25, alpha: 1.0)
        context.setStrokeColor(crossColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineCap(.round)
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let size: CGFloat = 3.5 // Cross size radius (7px total width)
        
        // Diagonal 1: Top-Left to Bottom-Right
        context.move(to: CGPoint(x: center.x - size, y: center.y + size))
        context.addLine(to: CGPoint(x: center.x + size, y: center.y - size))
        
        // Diagonal 2: Bottom-Left to Top-Right
        context.move(to: CGPoint(x: center.x - size, y: center.y - size))
        context.addLine(to: CGPoint(x: center.x + size, y: center.y + size))
        
        context.strokePath()
    }
}
