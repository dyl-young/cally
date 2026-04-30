import AppKit

/// Custom NSMenuItem view used to render an event row with a dotted rounded-rect border.
/// `NSAttributedString` has no border attribute, so the only way to draw a real border around
/// a menu row is to take over rendering with `item.view = ...`. We then own everything: the
/// colour bar, the title text, the hover highlight, and click handling.
final class EventMenuItemView: NSView {
    private let barColor: NSColor
    private let onClick: () -> Void
    private let cachedSize: NSSize
    private let textHeight: CGFloat
    private let textNormal: NSAttributedString
    private let textHighlighted: NSAttributedString
    private weak var observedItem: NSMenuItem?

    private static let returnKeyCode: UInt16 = 36
    private static let enterKeyCode: UInt16 = 76
    private static let spaceKeyCode: UInt16 = 49

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

    init(timeStr: String, titleStr: String, barColor: NSColor, onClick: @escaping () -> Void) {
        self.barColor = barColor
        self.onClick = onClick
        self.textNormal = Self.makeText(timeStr: timeStr, titleStr: titleStr, highlighted: false)
        self.textHighlighted = Self.makeText(timeStr: timeStr, titleStr: titleStr, highlighted: true)
        let textSize = textNormal.size()
        self.textHeight = textSize.height
        let width = Self.leadingInset + Self.barWidth + Self.barTitleGap + textSize.width + Self.trailingInset
        self.cachedSize = NSSize(width: ceil(width), height: Self.rowHeight)
        super.init(frame: NSRect(origin: .zero, size: cachedSize))
        autoresizingMask = .width
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { cachedSize }

    private static func makeText(timeStr: String, titleStr: String, highlighted: Bool) -> NSAttributedString {
        let primary = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        let secondary = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.secondaryLabelColor
        let timeAttrs: [NSAttributedString.Key: Any] = [.font: timeFont, .foregroundColor: secondary]
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: primary]
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: timeStr, attributes: timeAttrs))
        result.append(NSAttributedString(string: "  ·  ", attributes: titleAttrs))
        result.append(NSAttributedString(string: titleStr, attributes: titleAttrs))
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let highlighted = enclosingMenuItem?.isHighlighted ?? false

        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            let bg = bounds.insetBy(dx: Self.highlightInsetX, dy: 0)
            NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        }

        barColor.setFill()
        let bar = NSRect(
            x: Self.leadingInset,
            y: (bounds.height - Self.barHeight) / 2,
            width: Self.barWidth,
            height: Self.barHeight
        )
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()

        let attrText = highlighted ? textHighlighted : textNormal
        let textX = Self.leadingInset + Self.barWidth + Self.barTitleGap
        let textY = (bounds.height - textHeight) / 2
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
        guard observedItem == nil, let item = enclosingMenuItem else { return }
        item.addObserver(self, forKeyPath: #keyPath(NSMenuItem.isHighlighted), options: [.new], context: nil)
        observedItem = item
    }

    // Removes from the originally-observed item rather than `enclosingMenuItem` (which may be nil
    // during teardown), preventing a KVO-leaks-into-deallocated-observee crash.
    private func detachHighlightObserver() {
        guard let item = observedItem else { return }
        item.removeObserver(self, forKeyPath: #keyPath(NSMenuItem.isHighlighted))
        observedItem = nil
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
        // Defer so the menu has unwound before the click handler runs.
        DispatchQueue.main.async { [onClick] in onClick() }
    }

    // MARK: Keyboard activation

    // Required so AppKit's menu tracking forwards keyDown to this view when its enclosing item
    // is highlighted. NSMenu's tracking loop bypasses NSEvent local monitors, so the view is
    // the only place plain Return/Enter can be intercepted for view-based items.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case Self.returnKeyCode, Self.enterKeyCode, Self.spaceKeyCode:
            invokeMenuAction()
        default:
            super.keyDown(with: event)
        }
    }

    private func invokeMenuAction() {
        guard let item = enclosingMenuItem,
              let menu = item.menu,
              let idx = menu.items.firstIndex(of: item) else { return }
        menu.performActionForItem(at: idx)
    }
}
