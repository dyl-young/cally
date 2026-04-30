import AppKit

@MainActor
struct MenuBuilder {
    let appState: AppState
    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onJoinMeet: (CalendarEvent) -> Void
    let onOpenCalendarWeb: () -> Void
    let onOpenSettings: () -> Void

    func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch appState.authStatus {
        case .signedOut, .signingIn:
            menu.addItem(actionItem(title: "Sign in with Google", action: onSignIn))
        case .needsReconnect:
            menu.addItem(actionItem(title: "Reconnect to Google", action: onSignIn))
        case .signedIn:
            appendEvents(to: menu)
        }

        menu.addItem(.separator())

        if case .signedIn = appState.authStatus {
            let item = actionItem(
                title: "Open Google Calendar",
                action: onOpenCalendarWeb,
                keyEquivalent: "1",
                modifiers: .command
            )
            if let icon = NSImage(named: "GoogleCalendar") {
                icon.isTemplate = false
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            menu.addItem(item)
        }

        menu.addItem(actionItem(
            title: "Settings…",
            action: onOpenSettings,
            keyEquivalent: ",",
            modifiers: .command
        ))

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Cally",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    private func appendEvents(to menu: NSMenu) {
        if appState.isOffline {
            menu.addItem(disabledHeader("Offline — showing cached events", italic: true))
            menu.addItem(.separator())
        }

        let sections = EventGrouping.group(events: appState.events, now: Date())
        if sections.isEmpty {
            menu.addItem(disabledHeader("No upcoming events"))
            return
        }

        for section in sections {
            menu.addItem(disabledHeader(section.title))
            let showMeet = (section.id == "now" || section.id == "upcoming")
            for ev in section.events {
                menu.addItem(eventItem(ev))
                if showMeet, ev.meetLink != nil {
                    menu.addItem(meetItem(ev))
                }
            }
        }
    }

    private func disabledHeader(_ title: String, italic: Bool = false) -> NSMenuItem {
        let item = NSMenuItem()
        var attrs: [NSAttributedString.Key: Any] = [
            .font: italic
                ? NSFont.menuFont(ofSize: 11)
                : NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        if italic, let italicFont = NSFontManager.shared.font(
            withFamily: NSFont.menuFont(ofSize: 11).familyName ?? "",
            traits: .italicFontMask,
            weight: 5,
            size: 11
        ) {
            attrs[.font] = italicFont
        }
        item.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        item.isEnabled = false
        return item
    }

    private func eventItem(_ event: CalendarEvent) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = eventAttributedTitle(event)
        item.image = colourBarImage(color: event.calendarColor)
        item.target = MenuActionForwarder.shared
        item.action = #selector(MenuActionForwarder.invoke(_:))
        item.representedObject = MenuAction(block: { [onOpenEvent] in onOpenEvent(event) })
        return item
    }

    private func meetItem(_ event: CalendarEvent) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = "Join Google Meet meeting"
        if let icon = NSImage(named: "GoogleMeet") {
            icon.isTemplate = false
            icon.size = NSSize(width: 18, height: 18)
            item.image = icon
        }
        item.indentationLevel = 1
        item.target = MenuActionForwarder.shared
        item.action = #selector(MenuActionForwarder.invoke(_:))
        item.representedObject = MenuAction(block: { [onJoinMeet] in onJoinMeet(event) })
        return item
    }

    private func eventAttributedTitle(_ event: CalendarEvent) -> NSAttributedString {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeStr = formatter.string(from: event.start)

        let timeFont = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        let titleFont = NSFont.menuFont(ofSize: NSFont.systemFontSize)

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: timeStr, attributes: [.font: timeFont]))
        result.append(NSAttributedString(string: "  ·  ", attributes: [.font: titleFont]))
        result.append(NSAttributedString(string: event.title, attributes: [.font: titleFont]))
        return result
    }

    /// 16×16 image with the calendar colour rendered as a 4×16 rounded bar flush-left.
    /// Using the standard menu icon size keeps native padding/alignment intact.
    private func colourBarImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        let bar = NSRect(x: 0, y: 0, width: 4, height: 16)
        NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func actionItem(
        title: String,
        action: @escaping () -> Void,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.title = title
        item.target = MenuActionForwarder.shared
        item.action = #selector(MenuActionForwarder.invoke(_:))
        item.representedObject = MenuAction(block: action)
        item.keyEquivalent = keyEquivalent
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}

/// A small box around a closure so it can travel through `NSMenuItem.representedObject`.
final class MenuAction: NSObject {
    let block: () -> Void
    init(block: @escaping () -> Void) { self.block = block }
}

/// Singleton target that invokes the closure stored on the triggering menu item.
final class MenuActionForwarder: NSObject, @unchecked Sendable {
    static let shared = MenuActionForwarder()

    @objc func invoke(_ sender: NSMenuItem) {
        if let action = sender.representedObject as? MenuAction {
            action.block()
        }
    }
}
