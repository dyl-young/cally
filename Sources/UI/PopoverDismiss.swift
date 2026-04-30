import SwiftUI

private struct PopoverDismissKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    var popoverDismiss: @MainActor () -> Void {
        get { self[PopoverDismissKey.self] }
        set { self[PopoverDismissKey.self] = newValue }
    }
}
