public import SwiftUI

extension Binding where Value == Bool {
    /// True while `item` holds a value; setting false clears it. For dialogs that present an item.
    public static func isPresenting<Item: Sendable>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding {
            item.wrappedValue != nil
        } set: {
            if !$0 { item.wrappedValue = nil }
        }
    }
}
