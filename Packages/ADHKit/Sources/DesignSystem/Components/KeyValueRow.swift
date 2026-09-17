public import SwiftUI

/// A label/value pair for inspectors and summaries.
public struct KeyValueRow: View {
    private let key: String
    private let value: String

    public init(_ key: String, value: String) {
        self.key = key
        self.value = value
    }

    public var body: some View {
        LabeledContent(key) {
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
