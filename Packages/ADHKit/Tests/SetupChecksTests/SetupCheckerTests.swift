import ADHTestSupport
import Foundation
import Foundations
import SDKDomain
import SetupChecks
import Testing

struct SetupCheckerTests {
    struct StubLocator: SDKLocating {
        var resolution: SDKLocationResolution
        func resolve() async -> SDKLocationResolution { resolution }
        func setUserSDKRoot(_ url: URL?) async {}
    }

    struct StubInventory: SDKInventoryProviding {
        var packages: [LocalPackage]
        func installedPackages(in location: SDKLocation) async -> [LocalPackage] { packages }
    }

    func package(_ path: String, _ revision: PackageRevision, _ kind: PackageKind) -> LocalPackage {
        LocalPackage(path: path, displayName: path, revision: revision, kind: kind, directory: URL(filePath: "/x"))
    }

    func location(_ temp: TemporaryDirectory) -> SDKLocation {
        SDKLocation(
            sdkRoot: temp.appending("sdk", isDirectory: true), sdkSource: .defaultLocation,
            avdHome: temp.appending("avd", isDirectory: true), avdSource: .defaultLocation
        )
    }

    @Test func readyWhenEverythingIsInstalled() async throws {
        let temp = try TemporaryDirectory()
        try temp.write("", to: "sdk/platform-tools/adb")
        let checker = SetupChecker(
            locator: StubLocator(resolution: .found(location(temp))),
            inventory: StubInventory(packages: [
                package("emulator", .init(major: 36, minor: 5, micro: 11), .emulator),
                package("platform-tools", .init(major: 37), .platformTools),
            ]),
            hypervisorAvailable: { true }
        )

        let report = await checker.run()

        #expect(report.isReady)
        #expect(report.hasPlatformTools)
        #expect(report.check(.emulator)?.installedRevision == PackageRevision(major: 36, minor: 5, micro: 11))
        #expect(FileManager.default.fileExists(atPath: location(temp).avdHome.path(percentEncoded: false)))
    }

    @Test func missingPlatformToolsDoesNotBlock() async throws {
        let temp = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: location(temp).sdkRoot, withIntermediateDirectories: true)
        let checker = SetupChecker(
            locator: StubLocator(resolution: .found(location(temp))),
            inventory: StubInventory(packages: [package("emulator", .init(major: 36), .emulator)]),
            hypervisorAvailable: { true }
        )
        let report = await checker.run()
        #expect(report.isReady)
        #expect(!report.hasPlatformTools)
        #expect(report.check(.platformTools)?.level == .optional)
    }

    @Test func oldOrMissingEmulatorBlocks() async throws {
        let temp = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: location(temp).sdkRoot, withIntermediateDirectories: true)
        let old = SetupChecker(
            locator: StubLocator(resolution: .found(location(temp))),
            inventory: StubInventory(packages: [package("emulator", .init(major: 30), .emulator)]),
            hypervisorAvailable: { true }
        )
        let oldReport = await old.run()
        #expect(!oldReport.isReady)
        guard case .needsUpdate = oldReport.check(.emulator)?.status else {
            Issue.record("Expected needsUpdate")
            return
        }

        let none = SetupChecker(
            locator: StubLocator(resolution: .found(location(temp))),
            inventory: StubInventory(packages: []),
            hypervisorAvailable: { true }
        )
        #expect(await !none.run().isReady)
    }

    @Test func missingSDKAndHypervisorFail() async throws {
        let temp = try TemporaryDirectory()
        let checker = SetupChecker(
            locator: StubLocator(resolution: .notFound(suggested: location(temp))),
            inventory: StubInventory(packages: []),
            hypervisorAvailable: { false }
        )
        let report = await checker.run()
        #expect(!report.isReady)
        #expect(report.check(.sdkFolder)?.status.isSatisfied == false)
        #expect(report.check(.hypervisor)?.status.isSatisfied == false)
    }
}
