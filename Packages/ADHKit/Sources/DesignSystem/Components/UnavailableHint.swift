public import SwiftUI

/// An inspector page that can't be used right now, with the reason (for example "Install Platform Tools…").
public struct UnavailableHint: View {
    private let title: String
    private let systemImage: String
    private let reason: String

    public init(_ title: String, systemImage: String, reason: String) {
        self.title = title
        self.systemImage = systemImage
        self.reason = reason
    }

    public var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(reason))
    }
}
