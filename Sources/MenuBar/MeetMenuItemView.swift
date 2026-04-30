import AppKit

/// Indented "Join Google Meet meeting" sub-row inside an NSMenu. Renders the multi-colour Meet
/// SVG (NSImage from asset catalog, isTemplate = false) plus the label.
final class MeetMenuItemView: NSView {
    let event: CalendarEvent
    let onClick: (CalendarEvent) -> Void

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "Join Google Meet meeting")
    private var trackingArea: NSTrackingArea?

    init(event: CalendarEvent, onClick: @escaping (CalendarEvent) -> Void) {
        self.event = event
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        wantsLayer = true
        autoresizingMask = [.width]
        setUpSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setUpSubviews() {
        if let image = NSImage(named: "GoogleMeet") {
            image.isTemplate = false
            imageView.image = image
        }
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        label.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        onClick(self.event)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = enclosingMenuItem?.isHighlighted ?? false
        if highlighted {
            NSColor.selectedMenuItemColor.setFill()
            bounds.fill()
            label.textColor = .selectedMenuItemTextColor
        } else {
            label.textColor = .labelColor
        }
        super.draw(dirtyRect)
    }
}
