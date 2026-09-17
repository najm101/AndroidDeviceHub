public import Foundation
public import Foundations
public import SDKDomain

/// Finds the Android SDK and AVD folders the same way the Android tools do.
///
/// SDK: user selection → `$ANDROID_HOME` → `$ANDROID_SDK_ROOT` → Android Studio settings → `~/Library/Android/sdk`.
/// AVDs: `$ANDROID_AVD_HOME` → `$ANDROID_USER_HOME/avd` → `~/.android/avd`.
///
/// Apps started from Finder only see variables set with `launchctl setenv`, so the Android Studio
/// settings file is an important fallback.
public struct SDKLocator: SDKLocating {
    private let environment: @Sendable () -> ProcessEnvironment
    private let fileSystem: any FileSystem
    private let preferences: any KeyValueStore

    public init(
        environment: @escaping @Sendable () -> ProcessEnvironment = { .current },
        fileSystem: any FileSystem = LiveFileSystem(),
        preferences: any KeyValueStore
    ) {
        self.environment = environment
        self.fileSystem = fileSystem
        self.preferences = preferences
    }

    public func resolve() async -> SDKLocationResolution {
        let env = environment()
        let avd = resolveAVDHome(env)
        let candidates = sdkCandidates(env)
        if let existing = candidates.first(where: { fileSystem.directoryExists(at: $0.url) }) {
            return .found(
                SDKLocation(sdkRoot: existing.url, sdkSource: existing.source, avdHome: avd.url, avdSource: avd.source))
        }
        let suggestion = candidates.first ?? defaultSDK(env)
        return .notFound(
            suggested: SDKLocation(
                sdkRoot: suggestion.url, sdkSource: suggestion.source, avdHome: avd.url, avdSource: avd.source
            ))
    }

    public func setUserSDKRoot(_ url: URL?) async {
        preferences.set(url?.path(percentEncoded: false), forKey: PreferenceKey.sdkRootOverride)
    }

    // MARK: - SDK

    private struct Candidate {
        var url: URL
        var source: LocationSource
    }

    private func sdkCandidates(_ env: ProcessEnvironment) -> [Candidate] {
        var candidates: [Candidate] = []
        if let path = preferences.string(forKey: PreferenceKey.sdkRootOverride), !path.isEmpty {
            candidates.append(Candidate(url: env.url(forPath: path), source: .userSelection))
        }
        for variable in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = env[variable] {
                candidates.append(Candidate(url: env.url(forPath: path), source: .environment(variable: variable)))
            }
        }
        if let path = AndroidStudioSettings.sdkPath(home: env.homeDirectory, fileSystem: fileSystem) {
            candidates.append(Candidate(url: env.url(forPath: path), source: .androidStudio))
        }
        candidates.append(defaultSDK(env))
        return candidates
    }

    private func defaultSDK(_ env: ProcessEnvironment) -> Candidate {
        Candidate(
            url: env.homeDirectory.appending(path: "Library/Android/sdk", directoryHint: .isDirectory),
            source: .defaultLocation
        )
    }

    // MARK: - AVD home

    private func resolveAVDHome(_ env: ProcessEnvironment) -> Candidate {
        if let path = env["ANDROID_AVD_HOME"] {
            return Candidate(url: env.url(forPath: path), source: .environment(variable: "ANDROID_AVD_HOME"))
        }
        if let path = env["ANDROID_USER_HOME"] {
            return Candidate(
                url: env.url(forPath: path).appending(path: "avd", directoryHint: .isDirectory),
                source: .environment(variable: "ANDROID_USER_HOME")
            )
        }
        return Candidate(
            url: env.homeDirectory.appending(path: ".android/avd", directoryHint: .isDirectory),
            source: .defaultLocation
        )
    }
}

/// Reads the SDK path Android Studio stores in `options/android.sdk.path.xml`.
enum AndroidStudioSettings {
    static func sdkPath(home: URL, fileSystem: any FileSystem) -> String? {
        let googleSupport = home.appending(path: "Library/Application Support/Google", directoryHint: .isDirectory)
        guard let folders = try? fileSystem.contentsOfDirectory(at: googleSupport) else { return nil }
        let studioFolders =
            folders
            .filter { $0.lastPathComponent.hasPrefix("AndroidStudio") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        for folder in studioFolders {
            let file = folder.appending(path: "options/android.sdk.path.xml", directoryHint: .notDirectory)
            if let text = try? fileSystem.string(contentsOf: file), let path = sdkPath(inSettingsXML: text) {
                return path
            }
        }
        return nil
    }

    /// Extracts `<option name="androidSdkAbsolutePath" value="…"/>`.
    static func sdkPath(inSettingsXML text: String) -> String? {
        guard let document = try? XMLDocument(xmlString: text),
            let nodes = try? document.nodes(forXPath: "//option[@name='androidSdkAbsolutePath']/@value"),
            let value = nodes.first?.stringValue, !value.isEmpty
        else { return nil }
        return value
    }
}
