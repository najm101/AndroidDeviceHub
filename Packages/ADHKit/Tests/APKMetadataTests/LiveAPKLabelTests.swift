import ADBClient
import APKMetadata
import Foundation
import Testing

/// Opt-in: reads labels of every package on a booted emulator.
/// `ADH_LIVE=1 swift test --filter LiveAPKLabelTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ADH_LIVE"] == "1"))
struct LiveAPKLabelTests {
    @Test func labelsForInstalledPackages() async throws {
        let server = ADBServer()
        let entry = try #require(try await server.devices().first { $0.isReady })
        let device = server.device(serial: entry.serial)
        let paths = try await device.run("pm list packages -f").split(whereSeparator: \.isNewline).compactMap {
            line -> (String, String)? in
            let body = line.dropFirst("package:".count)
            guard let equals = body.lastIndex(of: "=") else { return nil }
            return (String(body[..<equals]), String(body[body.index(after: equals)...]))
        }
        var resolved = 0
        var failures: [String] = []
        for (path, name) in paths.prefix(400) {
            let manifest = try await device.shell("unzip -p \(shellQuoted(path)) AndroidManifest.xml").standardOutput
            do {
                switch try APKLabelReader.manifestLabel(manifest) {
                case let .text(text)?:
                    resolved += 1
                    if resolved < 5 { print("\(name) → \(text) (inline)") }
                case let .resource(id)?:
                    let arsc = try await device.shell("unzip -p \(shellQuoted(path)) resources.arsc").standardOutput
                    if let label = try APKLabelReader.string(for: id, in: arsc) {
                        resolved += 1
                        if ["com.android.settings", "com.android.chrome", "com.google.android.apps.maps"].contains(name)
                        {
                            print("\(name) → \(label)")
                        }
                    } else {
                        failures.append("\(name): unresolved \(String(id, radix: 16))")
                    }
                case nil:
                    failures.append("\(name): no label")
                }
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        print("resolved \(resolved) of \(paths.count)")
        print(failures.prefix(30).joined(separator: "\n"))
        #expect(resolved > paths.count / 2)
    }
}
