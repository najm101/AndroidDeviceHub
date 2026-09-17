import ADBClient
import DeviceDomain
import Foundation
import Testing

@testable import DeviceControllers

/// Opt-in: needs a booted emulator in ADB.
/// `ADH_LIVE=1 [ADH_LIVE_APK=/path/app.apk] swift test --filter LiveInspectorTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ADH_LIVE"] == "1"), .serialized)
@MainActor
struct LiveInspectorTests {
    func inspector() async throws -> ADBInspector {
        let server = ADBServer()
        let entry = try #require(try await server.devices().first { $0.isReady && $0.serial.hasPrefix("emulator-") })
        return ADBInspector(device: server.device(serial: entry.serial), homeDirectory: "/")
    }

    @Test func info() async throws {
        let groups = try await inspector().properties()
        let values = Dictionary(
            groups.flatMap(\.properties).map { ($0.title, $0.value) }, uniquingKeysWith: { first, _ in first })
        #expect(values["API level"].flatMap(Int.init) != nil)
        #expect(values["RAM"] != nil)
        #expect(values["Resolution"]?.contains("x") == true)
        #expect(values["Storage"]?.contains("used") == true)
        print(groups)
    }

    @Test func appsAndUsers() async throws {
        let inspector = try await inspector()
        let apps = try await inspector.apps(user: 0)
        #expect(apps.count > 50)
        #expect(apps.contains { $0.packageName == "com.android.settings" && $0.isSystem && $0.uid != nil })
        try await inspector.launch("com.android.settings", user: 0)
        try await inspector.forceStop("com.android.settings", user: 0)

        let users = try await inspector.users()
        #expect(users.users.contains { $0.id == 0 })
        #expect(users.currentUserID == 0)
        #expect(users.maximumUsers >= 1)
    }

    @Test func installAndUninstall() async throws {
        guard let path = ProcessInfo.processInfo.environment["ADH_LIVE_APK"] else { return }
        let inspector = try await inspector()
        let before = Set(try await inspector.apps(user: 0).filter { !$0.isSystem }.map(\.packageName))
        let progress = ProgressBox()
        try await inspector.install(URL(filePath: path), user: 0) { progress.last = $0 }
        #expect(progress.last?.fraction == 1)
        let added = Set(try await inspector.apps(user: 0).filter { !$0.isSystem }.map(\.packageName)).subtracting(
            before)
        let package = try #require(added.first)
        try await inspector.clearData(package, user: 0)
        try await inspector.uninstall(package, user: 0)
        #expect(!(try await inspector.apps(user: 0).contains { $0.packageName == package }))
    }

    @Test func files() async throws {
        let inspector = try await inspector()
        let root = try await inspector.files(in: "/")
        #expect(root.contains { $0.name == "sdcard" })
        await #expect(throws: InspectorError.permissionDenied) { try await inspector.files(in: "/data") }

        let folder = "/sdcard/Download/adh-inspector"
        try await inspector.delete(folder)
        try await inspector.makeDirectory(at: folder)
        let local = FileManager.default.temporaryDirectory.appending(path: "adh-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: local.appending(path: "nested"), withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: local.appending(path: "nested/a.txt"))
        defer { try? FileManager.default.removeItem(at: local) }

        try await inspector.upload(local, into: folder) { _ in }
        let uploaded = RemotePath.join(folder, local.lastPathComponent)
        try await inspector.move(uploaded, to: RemotePath.join(folder, "renamed"))
        let listing = try await inspector.files(in: folder)
        #expect(listing.map(\.name) == ["renamed"])

        let downloads = FileManager.default.temporaryDirectory.appending(path: "adh-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: downloads) }
        let result = try await inspector.download(listing[0], into: downloads) { _ in }
        #expect(try String(contentsOf: result.appending(path: "nested/a.txt"), encoding: .utf8) == "hello")
        try await inspector.delete(folder)
    }

    @Test func reports() async throws {
        let inspector = try await inspector()
        _ = try await inspector.crashReports()
        var count = 0
        for try await batch in inspector.logEntries(recent: 20) {
            count += batch.count
            #expect(batch.allSatisfy { !$0.tag.isEmpty && $0.pid > 0 })
            if count >= 20 { break }
        }
        #expect(count >= 20)
    }
}

final class ProgressBox: @unchecked Sendable {
    var last: TransferProgress?
}

/// Slow (a minute or two): `ADH_LIVE=1 ADH_LIVE_SLOW=1 swift test --filter LiveSlowInspectorTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ADH_LIVE_SLOW"] == "1"), .serialized)
@MainActor
struct LiveSlowInspectorTests {
    @Test func bugReport() async throws {
        let inspector = try await LiveInspectorTests().inspector()
        let folder = FileManager.default.temporaryDirectory.appending(path: "adh-bugreport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await inspector.bugReport(into: folder) { _ in }
        #expect(url.pathExtension == "zip")
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 100_000)
    }

    @Test func createAndRemoveUser() async throws {
        let inspector = try await LiveInspectorTests().inspector()
        try await inspector.createUser(named: "ADH Test")
        let created = try #require(try await inspector.users().users.first { $0.name == "ADH Test" })
        try await inspector.removeUser(created.id)
        #expect(!(try await inspector.users().users.contains { $0.id == created.id }))
    }
}
