import AppKit

/// Custom NSView used inside an NSMenuItem to render an event row with a calendar-colour bar,
/// time, and title. The view repaints itself based on `enclosingMenuItem?.isHighlighted` so it
/// participates in NSMenu's normal hover + keyboard nav.
final class EventMenuItemView: NSView {
    let event: CalendarEvent
    let onClick: (CalendarEvent) -> Void

    private let colourBar = NSView()
    private let timeLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

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
        colourBar.wantsLayer = true
        colourBar.layer?.cornerRadius = 2
        colourBar.layer?.backgroundColor = event.calendarColor.cgColor
        colourBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(colourBar)

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        timeLabel.stringValue = formatter.string(from: event.start)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        titleLabel.stringValue = "·  \(event.title)"
        titleLabel.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            colourBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            colourBar.centerYAnchor.constraint(equalTo: centerYAnchor),
            colourBar.widthAnchor.constraint(equalToConstant: 4),
            colourBar.heightAnchor.constraint(equalToConstant: 16),

            timeLabel.leadingAnchor.constraint(equalTo: colourBar.trailingAnchor, constant: 8),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
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
            let pill = bounds.insetBy(dx: 5, dy: 0)
            let path = NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4)
            NSColor.controlAccentColor.setFill()
            path.fill()
            timeLabel.textColor = .white
            titleLabel.textColor = .white
            colourBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        } else {
            timeLabel.textColor = .labelColor
            titleLabel.textColor = .labelColor
            colourBar.layer?.backgroundColor = event.calendarColor.cgColor
        }
        super.draw(dirtyRect)
    }
}
