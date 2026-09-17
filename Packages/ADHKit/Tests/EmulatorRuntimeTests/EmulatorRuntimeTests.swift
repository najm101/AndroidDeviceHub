import ADHTestSupport
import Foundation
import Foundations
import SDKDomain
import Testing

@testable import EmulatorRuntime

struct EmulatorDiscoveryTests {
    @Test func parsesDiscoveryFile() throws {
        let text = try String(contentsOf: Fixtures.url("emulator/pid_37993.ini"), encoding: .utf8)
        let emulator = try #require(EmulatorDiscovery.parse(text, fileName: "pid_37993.ini"))
        #expect(emulator.pid == 37993)
        #expect(emulator.avdID == "SmokeTest_API36")
        #expect(emulator.grpcPort == 8554)
        #expect(emulator.hasGRPCToken)
        #expect(emulator.adbSerial == "emulator-5554")
    }

    @Test func ignoresDeadProcessesAndOtherFiles() throws {
        let temp = try TemporaryDirectory()
        try temp.write(
            try String(contentsOf: Fixtures.url("emulator/pid_37993.ini"), encoding: .utf8), to: "pid_37993.ini")
        try temp.write("avd.id=Alive\n", to: "pid_42.ini")
        try temp.write("avd.id=Ignored\n", to: "notes.txt")

        let discovery = EmulatorDiscovery(directory: temp.url, isAlive: { $0 == 42 })
        #expect(discovery.runningEmulators().map(\.avdID) == ["Alive"])
    }

    @Test func missingDirectoryMeansNothingRuns() {
        let discovery = EmulatorDiscovery(directory: URL(filePath: "/does/not/exist"))
        #expect(discovery.runningEmulators().isEmpty)
    }
}

struct EmulatorLauncherTests {
    @Test func buildsArguments() throws {
        let arguments = try EmulatorLauncher.arguments(
            avdID: "Pixel", options: LaunchOptions(coldBoot: true, hideWindow: true))
        #expect(arguments.starts(with: ["-avd", "Pixel", "-grpc"]))
        #expect(arguments.contains("-grpc-use-token"))
        #expect(arguments.contains("-no-snapshot-load"))
        #expect(arguments.contains("-qt-hide-window"))
        #expect(!arguments.contains("-wipe-data"))
    }

    @Test func passesResolvedFoldersToTheEmulator() {
        let env = EmulatorLauncher.environment(
            base: ProcessEnvironment(
                values: ["PATH": "/bin", "ANDROID_AVD_HOME": "/old"], homeDirectory: URL(filePath: "/h")),
            location: SampleData.location(root: URL(filePath: "/Volumes/x/sdk", directoryHint: .isDirectory))
        )
        #expect(env["PATH"] == "/bin")
        #expect(env["ANDROID_HOME"] == "/Volumes/x/sdk/")
        #expect(env["ANDROID_SDK_ROOT"] == "/Volumes/x/sdk/")
        #expect(env["ANDROID_AVD_HOME"] == "/Volumes/x/sdk/avd")
    }

    @Test func reportsMissingEmulator() async throws {
        let temp = try TemporaryDirectory()
        let launcher = EmulatorLauncher(logDirectory: temp.url)
        await #expect(throws: EmulatorLaunchError.emulatorNotInstalled) {
            try await launcher.launch(avdID: "x", options: .init(), location: SampleData.location(root: temp.url))
        }
    }

    @Test func reportsImmediateExit() async throws {
        let temp = try TemporaryDirectory()
        try temp.write("#!/bin/sh\necho broken\nexit 3\n", to: "emulator/emulator")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: temp.appending("emulator/emulator").path)
        let launcher = EmulatorLauncher(logDirectory: temp.appending("logs", isDirectory: true))

        do {
            try await launcher.launch(avdID: "x", options: .init(), location: SampleData.location(root: temp.url))
            Issue.record("Expected a launch failure")
        } catch let EmulatorLaunchError.exited(code, log) {
            #expect(code == 3)
            #expect(try String(contentsOf: log, encoding: .utf8).contains("broken"))
        }
    }
}
