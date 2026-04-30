import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's RegisterEventHotKey to register a system-wide keyboard shortcut.
/// The handler is dispatched on the main queue.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID: UInt32
    private let action: () -> Void

    nonisolated(unsafe) private static var instances: [UInt32: GlobalHotKey] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    private static let signature: OSType = 0x43_61_6c_6c // 'Call'
    nonisolated(unsafe) private static var sharedHandlerInstalled = false

    /// `keyCode` and `modifiers` use Carbon constants (e.g. `kVK_ANSI_K`, `cmdKey`, `controlKey`).
    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.nextID += 1
        self.hotKeyID = Self.nextID
        self.action = action

        Self.installSharedHandlerIfNeeded()
        Self.instances[hotKeyID] = self

        let id = EventHotKeyID(signature: Self.signature, id: hotKeyID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("RegisterEventHotKey failed: \(status)")
            Self.instances.removeValue(forKey: hotKeyID)
        }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        Self.instances.removeValue(forKey: hotKeyID)
    }

    private static func installSharedHandlerIfNeeded() {
        guard !sharedHandlerInstalled else { return }
        sharedHandlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var id = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard result == noErr,
                      id.signature == GlobalHotKey.signature,
                      let instance = GlobalHotKey.instances[id.id] else {
                    return noErr
                }
                let action = instance.action
                DispatchQueue.main.async { action() }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
