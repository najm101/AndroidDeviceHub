import ADHTestSupport
import Foundation
import Foundations
import SDKDomain
import Testing

@testable import SDKLocator

struct SDKLocatorTests {
    func locator(
        _ temp: TemporaryDirectory,
        variables: [String: String] = [:],
        preferences: InMemoryKeyValueStore = InMemoryKeyValueStore()
    ) -> SDKLocator {
        let home = temp.url
        return SDKLocator(
            environment: { ProcessEnvironment(values: variables, homeDirectory: home) },
            preferences: preferences
        )
    }

    @Test func prefersUserSelection() async throws {
        let temp = try TemporaryDirectory()
        let chosen = temp.appending("chosen", isDirectory: true)
        let fromEnv = temp.appending("env", isDirectory: true)
        try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fromEnv, withIntermediateDirectories: true)
        let sut = locator(temp, variables: ["ANDROID_HOME": fromEnv.path])

        await sut.setUserSDKRoot(chosen)
        let resolution = await sut.resolve()

        #expect(resolution == .found(resolution.location))
        #expect(resolution.location.sdkRoot.standardizedFileURL == chosen.standardizedFileURL)
        #expect(resolution.location.sdkSource == .userSelection)
    }

    @Test func usesEnvironmentThenAndroidStudio() async throws {
        let temp = try TemporaryDirectory()
        let studioSDK = temp.appending("studio-sdk", isDirectory: true)
        try FileManager.default.createDirectory(at: studioSDK, withIntermediateDirectories: true)
        try temp.write(
            """
            <application>
              <component name="AndroidSdkPathStore">
                <option name="androidSdkAbsolutePath" value="\(studioSDK.path(percentEncoded: false))" />
              </component>
            </application>
            """, to: "Library/Application Support/Google/AndroidStudio2024.3/options/android.sdk.path.xml")

        // The environment points at a folder that doesn't exist, so Studio's path wins.
        let resolution = await locator(temp, variables: ["ANDROID_HOME": "/does/not/exist"]).resolve()

        #expect(resolution.location.sdkSource == .androidStudio)
        #expect(
            resolution.location.sdkRoot.path(percentEncoded: false).hasPrefix(studioSDK.path(percentEncoded: false)))
    }

    @Test func suggestsDefaultWhenNothingExists() async throws {
        let temp = try TemporaryDirectory()
        let resolution = await locator(temp).resolve()

        guard case let .notFound(suggested) = resolution else {
            Issue.record("Expected notFound")
            return
        }
        #expect(suggested.sdkRoot.path(percentEncoded: false).hasSuffix("Library/Android/sdk/"))
        #expect(suggested.avdHome.path(percentEncoded: false).hasSuffix(".android/avd/"))
    }

    @Test func resolvesAVDHomeFromEnvironment() async throws {
        let temp = try TemporaryDirectory()
        let avd = await locator(temp, variables: ["ANDROID_AVD_HOME": "/Volumes/x/avd"]).resolve().location
        #expect(avd.avdHome.path(percentEncoded: false).hasPrefix("/Volumes/x/avd"))
        #expect(avd.avdSource == .environment(variable: "ANDROID_AVD_HOME"))

        let userHome = await locator(temp, variables: ["ANDROID_USER_HOME": "/Volumes/y"]).resolve().location
        #expect(userHome.avdHome.path(percentEncoded: false).hasPrefix("/Volumes/y/avd"))
    }

    @Test func parsesStudioSettings() {
        let xml =
            #"<application><component><option name="androidSdkAbsolutePath" value="/a/b" /></component></application>"#
        #expect(AndroidStudioSettings.sdkPath(inSettingsXML: xml) == "/a/b")
        #expect(AndroidStudioSettings.sdkPath(inSettingsXML: "<application/>") == nil)
    }
}
