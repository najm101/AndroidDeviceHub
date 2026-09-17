import Foundation
import Testing

@testable import ADBClient

/// Opt-in: needs a running ADB server with a booted emulator.
/// `ADH_LIVE=1 swift test --filter LiveADBTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ADH_LIVE"] == "1"), .serialized)
struct LiveADBTests {
    let server = ADBServer()

    func device() async throws -> ADBDevice {
        let entry = try #require(try await server.devices().first { $0.isReady && $0.serial.hasPrefix("emulator-") })
        return server.device(serial: entry.serial)
    }

    @Test func versionAndFeatures() async throws {
        #expect(try await server.version() > 30)
        let features = try await device().features()
        #expect(features.contains("shell_v2"))
    }

    @Test func shellKeepsStreamsAndExitCode() async throws {
        let device = try await device()
        let result = try await device.shell("echo out; echo err >&2; exit 3")
        #expect(result.output == "out\n")
        #expect(result.errorOutput == "err\n")
        #expect(result.exitCode == 3)
        let props = try await device.run("getprop ro.build.version.sdk")
        #expect(Int(props.trimmingCharacters(in: .whitespacesAndNewlines)) != nil)
    }

    @Test func pushListStatPull() async throws {
        let device = try await device()
        let local = FileManager.default.temporaryDirectory.appending(path: "adh-live-\(UUID().uuidString).bin")
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        try payload.write(to: local)
        defer { try? FileManager.default.removeItem(at: local) }

        let folder = "/sdcard/Download/adh-live"
        let sync = try await device.sync()
        defer { sync.close() }
        try await sync.push(local, to: "\(folder)/sample.bin")
        let entries = try await sync.list(folder)
        #expect(entries.map(\.name) == ["sample.bin"])
        let stat = try await sync.stat("\(folder)/sample.bin")
        #expect(stat.size == 200_000)
        #expect(stat.isRegularFile)
        #expect(try await sync.stat("\(folder)/missing").exists == false)

        let copy = local.appendingPathExtension("copy")
        defer { try? FileManager.default.removeItem(at: copy) }
        try await sync.pull("\(folder)/sample.bin", to: copy, size: stat.size)
        #expect(try Data(contentsOf: copy) == payload)
        try await device.run("rm -rf \(shellQuoted(folder))")
    }

    @Test func tracksDevices() async throws {
        for try await devices in server.trackDevices() {
            #expect(devices.contains { $0.serial.hasPrefix("emulator-") })
            break
        }
    }
}
