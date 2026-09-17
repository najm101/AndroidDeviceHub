import CryptoKit
import Foundation
import Foundations
import SDKDomain

/// Reads and writes `sdk/licenses/<id>`, the same files `sdkmanager --licenses` uses.
///
/// Each file holds one SHA-1 per line: the hash of a license text the user accepted.
struct LicenseStore {
    let fileSystem: any FileSystem

    static func hash(of license: License) -> String {
        Insecure.SHA1.hash(data: Data(license.text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func isAccepted(_ license: License, in location: SDKLocation) -> Bool {
        acceptedHashes(for: license.id, in: location).contains(Self.hash(of: license))
    }

    func accept(_ license: License, in location: SDKLocation) throws {
        guard !isAccepted(license, in: location) else { return }
        let file = fileURL(for: license.id, in: location)
        var text = (try? fileSystem.string(contentsOf: file)) ?? ""
        if !text.hasSuffix("\n") { text += "\n" }
        text += Self.hash(of: license)
        try fileSystem.write(text, to: file)
    }

    private func acceptedHashes(for id: String, in location: SDKLocation) -> Set<String> {
        guard let text = try? fileSystem.string(contentsOf: fileURL(for: id, in: location)) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private func fileURL(for id: String, in location: SDKLocation) -> URL {
        location.licensesDirectory.appending(path: id, directoryHint: .notDirectory)
    }
}
