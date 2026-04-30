import AppKit

/// Custom NSMenuItem view used to render an event row with a dotted rounded-rect border.
/// `NSAttributedString` has no border attribute, so the only way to draw a real border around
/// a menu row is to take over rendering with `item.view = ...`. We then own everything: the
/// colour bar, the title text, the hover highlight, and click handling.
final class EventMenuItemView: NSView {
    private let timeStr: String
    private let titleStr: String
    private let leadingColor: NSColor
    private let onClick: () -> Void

    // Tuned empirically to match AppKit's rendering for items that use `item.image` (a 16-wide
    // image well) and `attributedTitle`. Bar X = 5 (matches the image's leading offset); title X
    // = 23 lines up with how AppKit lays out a 16-wide image's bar at x=0 followed by the title.
    private static let leadingInset: CGFloat = 16
    private static let trailingInset: CGFloat = 14
    private static let barWidth: CGFloat = 4
    private static let barHeight: CGFloat = 16
    private static let barTitleGap: CGFloat = 14
    private static let rowHeight: CGFloat = 22
    private static let borderInsetX: CGFloat = 8
    private static let borderInsetY: CGFloat = 2
    private static let highlightInsetX: CGFloat = 5

    private static let timeFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .regular
    )
    private static let titleFont = NSFont.menuFont(ofSize: NSFont.systemFontSize)

    private var isObservingHighlight = false

    init(timeStr: String, titleStr: String, leadingColor: NSColor, onClick: @escaping () -> Void) {
        self.timeStr = timeStr
        self.titleStr = titleStr
        self.leadingColor = leadingColor
        self.onClick = onClick
        super.init(frame: NSRect(origin: .zero, size: Self.intrinsicSize(timeStr: timeStr, titleStr: titleStr)))
        autoresizingMask = .width
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        Self.intrinsicSize(timeStr: timeStr, titleStr: titleStr)
    }

    private static func intrinsicSize(timeStr: String, titleStr: String) -> NSSize {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: timeStr, attributes: [.font: timeFont]))
        text.append(NSAttributedString(string: "  ·  ", attributes: [.font: titleFont]))
        text.append(NSAttributedString(string: titleStr, attributes: [.font: titleFont]))
        let textSize = text.size()
        let width = leadingInset + barWidth + barTitleGap + textSize.width + trailingInset
        return NSSize(width: ceil(width), height: rowHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let highlighted = enclosingMenuItem?.isHighlighted ?? false

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let bg = bounds.insetBy(dx: Self.highlightInsetX, dy: 0)
            NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        }

        leadingColor.setFill()
        let bar = NSRect(
            x: Self.leadingInset,
            y: (bounds.height - Self.barHeight) / 2,
            width: Self.barWidth,
            height: Self.barHeight
        )
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()

        let attrText = renderedText(highlighted: highlighted)
        let textSize = attrText.size()
        let textX = Self.leadingInset + Self.barWidth + Self.barTitleGap
        let textY = (bounds.height - textSize.height) / 2
        attrText.draw(at: NSPoint(x: textX, y: textY))

        let borderRect = bounds.insetBy(dx: Self.borderInsetX, dy: Self.borderInsetY)
        let path = NSBezierPath(roundedRect: borderRect, xRadius: 4, yRadius: 4)
        path.lineWidth = 1
        path.setLineDash([2, 2], count: 2, phase: 0)
        let stroke: NSColor = highlighted
            ? NSColor.selectedMenuItemTextColor.withAlphaComponent(0.6)
            : NSColor.secondaryLabelColor
        stroke.setStroke()
        path.stroke()
    }

    private func renderedText(highlighted: Bool) -> NSAttributedString {
        let primary = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        let secondary = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor
        let timeAttrs: [NSAttributedString.Key: Any] = [.font: Self.timeFont, .foregroundColor: secondary]
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: Self.titleFont, .foregroundColor: primary]
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: timeStr, attributes: timeAttrs))
        result.append(NSAttributedString(string: "  ·  ", attributes: titleAttrs))
        result.append(NSAttributedString(string: titleStr, attributes: titleAttrs))
        return result
    }

    // MARK: Highlight observation

    // AppKit doesn't redraw a custom-view menu item when its highlight state changes (whether from
    // mouse motion or arrow-key navigation), so we observe the property directly.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        detachHighlightObserver()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { attachHighlightObserver() }
    }

    private func attachHighlightObserver() {
        guard !isObservingHighlight, let item = enclosingMenuItem else { return }
        item.addObserver(self, forKeyPath: #keyPath(NSMenuItem.isHighlighted), options: [.new], context: nil)
        isObservingHighlight = true
    }

    private func detachHighlightObserver() {
        guard isObservingHighlight, let item = enclosingMenuItem else { return }
        item.removeObserver(self, forKeyPath: #keyPath(NSMenuItem.isHighlighted))
        isObservingHighlight = false
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == #keyPath(NSMenuItem.isHighlighted) {
            MainActor.assumeIsolated {
                self.setNeedsDisplay(self.bounds)
            }
        }
    }

    // MARK: Click handling

    override func mouseUp(with event: NSEvent) {
        guard let menu = enclosingMenuItem?.menu else { return }
        menu.cancelTracking()
        let action = onClick
        DispatchQueue.main.async { action() }
    }
}
