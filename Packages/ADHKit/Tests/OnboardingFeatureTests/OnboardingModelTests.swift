import ADHTestSupport
import DeviceDomain
import Foundation
import SDKDomain
import Testing

@testable import OnboardingFeature

@MainActor
struct OnboardingModelTests {
    let repository = FakeDeviceRepository()
    let installs = FakeInstallCoordinator()
    let context = SDKContext()

    static func report(emulatorInstalled: Bool = true, platformTools: Bool = true) -> SetupReport {
        let location = SampleData.location()
        func check(_ id: SetupCheck.ID, _ level: SetupCheck.Level, _ ok: Bool) -> SetupCheck {
            SetupCheck(
                id: id, title: id.rawValue, level: level,
                status: ok ? .satisfied(detail: "ok") : .missing(detail: "missing"),
                installablePackagePath: id == .emulator ? "emulator" : id == .platformTools ? "platform-tools" : nil)
        }
        return SetupReport(
            resolution: .found(location),
            checks: [
                check(.sdkFolder, .required, true),
                check(.emulator, .required, emulatorInstalled),
                check(.platformTools, .optional, platformTools),
            ])
    }

    func makeModel(
        report: SetupReport,
        completions: @escaping (OnboardingDependencies.Completion) -> Void = { _ in }
    ) -> OnboardingModel {
        OnboardingModel(
            dependencies: OnboardingDependencies(
                context: context,
                runChecks: { report },
                setSDKRoot: { _ in },
                createFolder: { _ in },
                remotePackages: { _ in [] },
                packageForSysdir: { sysdir in
                    SampleData.remotePackage(for: SampleData.image(api: sysdir.contains("35") ? 35 : 36))
                },
                installs: installs,
                repository: repository,
                complete: completions
            ))
    }

    @Test func blocksWhileRequiredChecksFail() async {
        let model = makeModel(report: Self.report(emulatorInstalled: false))
        await model.start()
        #expect(!model.canContinue)
        await model.goForward()
        #expect(model.step == .sdk)
    }

    @Test func skipsPlatformToolsStepWhenInstalled() async {
        let model = makeModel(report: Self.report())
        await model.start()
        #expect(model.canContinue)
        await model.goForward()
        #expect(model.step == .ready)
        model.goBack()
        #expect(model.step == .sdk)
    }

    @Test func recordsSkippedPlatformTools() async {
        var completion: OnboardingDependencies.Completion?
        let model = makeModel(report: Self.report(platformTools: false)) { completion = $0 }
        await model.start()
        await model.goForward()
        #expect(model.step == .platformTools)

        await model.skipPlatformTools()
        #expect(model.step == .ready)
        model.finish(openNewEmulator: true)

        #expect(completion?.skippedPlatformTools == true)
        #expect(completion?.openNewEmulator == true)
    }

    @Test func groupsDevicesMissingImages() async {
        repository.devices = [
            .emulator(
                id: "a", name: "A", state: .needsAttention(.missingSystemImage(sysdir: "system-images/android-36/x/y/"))
            ),
            .emulator(
                id: "b", name: "B", state: .needsAttention(.missingSystemImage(sysdir: "system-images/android-36/x/y/"))
            ),
            .emulator(
                id: "c", name: "C", state: .needsAttention(.missingSystemImage(sysdir: "system-images/android-35/x/y/"))
            ),
            .emulator(id: "d", name: "D"),
        ]
        let model = makeModel(report: Self.report())
        await model.start()
        await model.goForward()

        #expect(model.deviceCount == 4)
        #expect(model.missingImages.map(\.deviceNames) == [["C"], ["A", "B"]])
        #expect(model.missingImages.first?.package?.systemImage?.apiLevel.major == 35)
    }

    @Test func publishesTheReport() async {
        let model = makeModel(report: Self.report())
        await model.start()
        #expect(context.report?.isReady == true)
    }
}
