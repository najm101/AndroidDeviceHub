public import Foundation

/// Finds an app's display name from its compiled manifest and resource table.
public enum APKLabelReader {
    /// The label from the manifest alone, when it's written inline. Returns the resource id otherwise.
    public static func manifestLabel(_ manifest: Data) throws -> ManifestLabel? {
        switch try BinaryManifest.applicationLabel(in: manifest) {
        case let .string(text): .text(text)
        case let .reference(id): .resource(id)
        case .other, nil: nil
        }
    }

    /// Resolves a string resource id in `resources.arsc`.
    public static func string(for id: UInt32, in resources: Data) throws -> String? {
        try ResourceTable(resources).string(for: id)
    }

    public enum ManifestLabel: Equatable, Sendable {
        case text(String)
        case resource(UInt32)
    }
}
