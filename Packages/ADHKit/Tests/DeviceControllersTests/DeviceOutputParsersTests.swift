import ADHTestSupport
import DeviceDomain
import Foundation
import Testing

@testable import DeviceControllers

struct DeviceOutputParsersTests {
    @Test func properties() {
        let values = DeviceOutputParsers.properties(
            """
            [ro.product.model]: [sdk_gphone64_arm64]
            [ro.build.version.sdk]: [36]
            [empty]: []
            not a property
            """)
        #expect(values["ro.product.model"] == "sdk_gphone64_arm64")
        #expect(values["ro.build.version.sdk"] == "36")
        #expect(values["empty"] == "")
        #expect(values.count == 3)
    }

    @Test func packagesKeepPathsWithEqualsSigns() {
        let apps = DeviceOutputParsers.packages(
            """
            package:/data/app/~~a1==/com.example.app-b2==/base.apk=com.example.app versionCode:12 uid:10190
            package:/system/app/Settings/Settings.apk=com.android.settings versionCode:36 uid:1000
            """,
            thirdParty: ["com.example.app"]
        )
        #expect(apps.count == 2)
        #expect(apps[0].packageName == "com.example.app")
        #expect(apps[0].apkPath == "/data/app/~~a1==/com.example.app-b2==/base.apk")
        #expect(apps[0].versionCode == 12)
        #expect(apps[0].uid == 10190)
        #expect(!apps[0].isSystem)
        #expect(apps[1].isSystem)
    }

    @Test func users() {
        let users = DeviceOutputParsers.users(
            """
            Users:
            \tUserInfo{0:Owner:4c13} running
            \tUserInfo{10:Work: profile:1030}
            """)
        #expect(
            users == [
                DeviceUser(id: 0, name: "Owner", isRunning: true, isProfile: false),
                DeviceUser(id: 10, name: "Work: profile", isRunning: false, isProfile: true),
            ])
        #expect(DeviceOutputParsers.lastInteger("Maximum supported users: 4\n") == 4)
    }

    @Test func sections() {
        #expect(DeviceOutputParsers.sections("a\n@@\nb\nc\n@@\n") == ["a\n", "b\nc\n", "\n"])
    }

    @Test func crashReportsFromDropbox() throws {
        let text = String(decoding: try Fixtures.data("adb/dropbox-print.txt"), as: UTF8.self)
        let reports = DeviceOutputParsers.crashReports(text, timeZone: TimeZone(identifier: "UTC")!)
        let report = try #require(reports.first)
        #expect(reports.count == 1)
        #expect(report.kind == .appCrash)
        #expect(report.tag == "system_app_crash")
        #expect(report.process == "com.android.settings")
        #expect(report.summary.hasPrefix("android.app.RemoteServiceException$CrashedByAdbException"))
        #expect(report.text.hasSuffix("ZygoteInit.java:932)"))
        #expect(!report.text.contains("Drop box contents"))
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: report.date)
        #expect(components.hour == 11 && components.minute == 18)
    }

    @Test func nativeCrashes() {
        let entry = """
            SystemUptimeMs: 1
            Process: com.google.android.bluetooth

            *** *** *** *** ***
            Cmdline: com.google.android.bluetooth
            signal 6 (SIGABRT), code -1 (SI_QUEUE), fault addr --------
            Abort message: 'hci_layer.cc:527 on_hardware_error'
            """
        let text = """
            ========================================
            2026-09-17 02:33:30 system_app_native_crash (text, 5438 bytes)
            \(entry)
            ========================================
            2026-09-17 02:33:30 SYSTEM_TOMBSTONE (compressed text, 10892 bytes)
            \(entry)
            ========================================
            2026-09-17 02:40:00 SYSTEM_TOMBSTONE (compressed text, 10 bytes)
            *** java.io.EOFException
            """
        let reports = DeviceOutputParsers.crashReports(text)
        #expect(reports.count == 1)
        #expect(reports.first?.tag == "system_app_native_crash")
        #expect(reports.first?.summary == "hci_layer.cc:527 on_hardware_error")
    }

    @Test func tombstoneProcess() {
        #expect(DeviceOutputParsers.process(in: "pid: 1, tid: 2, name: main  >>> com.foo <<<") == "com.foo")
    }

    @Test func bugReportLines() {
        #expect(DeviceOutputParsers.bugReportLine("PROGRESS:25/100") == .progress(0.25))
        #expect(DeviceOutputParsers.bugReportLine("OK:/bugreports/a.zip") == .finished(path: "/bugreports/a.zip"))
        #expect(DeviceOutputParsers.bugReportLine("FAIL:no space") == .failed("no space"))
        #expect(DeviceOutputParsers.bugReportLine("BEGIN:/bugreports/a.zip") == nil)
    }

    @Test func resources() {
        let memory = DeviceOutputParsers.memInfo("MemTotal:        2021944 kB\nMemFree: 1 kB", key: "MemTotal")
        #expect(memory == Int64(2_021_944) * 1024)
        let disk = DeviceOutputParsers.diskUsage(
            "Filesystem 1K-blocks Used Available Use% Mounted on\n/dev/block/dm-53   6082144 1643616   4296316  28% /data"
        )
        #expect(disk?.total == Int64(6_082_144) * 1024)
        #expect(disk?.used == Int64(1_643_616) * 1024)
        #expect(DeviceOutputParsers.screenSize("Physical size: 1080x2400\nOverride size: 720x1600") == "720x1600")
    }

    @Test func logcatBinary() throws {
        var decoder = LogcatDecoder()
        let data = try Fixtures.data("adb/logcat-25.bin")
        // Split into uneven chunks to exercise buffering.
        var entries: [LogEntry] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + 37, data.count)
            decoder.append(data[offset..<end])
            entries += decoder.entries()
            offset = end
        }
        #expect(entries.count >= 25)
        #expect(entries.allSatisfy { !$0.tag.isEmpty && $0.pid > 0 && $0.uid != nil })
        #expect(entries.map(\.id) == Array(1...entries.count))
        #expect(entries.last!.date.timeIntervalSinceNow > -86_400 * 30)
    }

    @Test func remotePaths() {
        #expect(RemotePath.join("/", "sdcard") == "/sdcard")
        #expect(RemotePath.join("/sdcard", "a") == "/sdcard/a")
        #expect(RemotePath.parent(of: "/sdcard/a") == "/sdcard")
        #expect(RemotePath.parent(of: "/sdcard") == "/")
        #expect(RemotePath.ancestors(of: "/sdcard/Download") == ["/", "/sdcard", "/sdcard/Download"])
        #expect(RemotePath.validationError(forName: "a/b") != nil)
    }

    @Test func apksFromArchive() throws {
        let temp = try TemporaryDirectory()
        let apk = temp.appending("app.apk")
        try Data("x".utf8).write(to: apk)
        #expect(try ADBInspector.apkFiles(for: apk, workspace: temp.appending("w", isDirectory: true)) == [apk])

        try temp.write("s", to: "splits/split_config.en.apk")
        try temp.write("b", to: "splits/base-master.apk")
        let apks = try ADBInspector.apkFiles(for: temp.appending("splits", isDirectory: true), workspace: temp.url)
        #expect(apks.map(\.lastPathComponent) == ["base-master.apk", "split_config.en.apk"])
        #expect(throws: InspectorError.unsupportedFile("notes.txt")) {
            try ADBInspector.apkFiles(for: temp.appending("notes.txt"), workspace: temp.url)
        }
    }

    @Test func adbTabsFollowADBStatus() {
        let ready = EmulatorCapabilities.capabilities(
            for: .running(inAppControl: false), formFactor: .phone, adb: .ready)
        #expect(ready[.files] == .available)
        #expect(ready[.settings] == nil)
        let missing = EmulatorCapabilities.capabilities(for: .running(inAppControl: true), formFactor: .phone)
        #expect(missing[.apps] == .disabled(reason: InspectorHint.installPlatformTools))
        let stopped = EmulatorCapabilities.capabilities(for: .stopped, formFactor: .phone, adb: .ready)
        #expect(stopped[.info] == nil)
    }
}
