import ADHTestSupport
import Foundation
import Foundations
import SDKDomain
import Testing

@testable import SDKCatalog
@testable import SDKInstaller

struct PackageXMLWriterTests {
    func playStoreImage() throws -> RemotePackage {
        let url = URL(string: "https://dl.google.com/android/repository/sys-img/google_apis_playstore/sys-img2-4.xml")!
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/sys-img2-4-google_apis_playstore.xml"),
            baseURL: url,
            host: .init(os: "macosx", arch: "aarch64", abis: ["arm64-v8a"])
        )
        return try #require(packages.first { $0.path == "system-images;android-36;google_apis_playstore;arm64-v8a" })
    }

    @Test func writtenDocumentParsesBackAsInstalledPackage() throws {
        let package = try playStoreImage()
        let xml = PackageXMLWriter.document(for: package)

        let local = try #require(
            PackageXMLParser.localPackage(fromXML: Data(xml.utf8), directory: URL(filePath: "/sdk/x")))
        #expect(local.path == package.path)
        #expect(local.revision == package.revision)
        #expect(local.systemImage?.extensionLevel == 17)
        #expect(local.systemImage?.hasPlayStore == true)
    }

    @Test func documentKeepsLicenseTextAndDeclaresPrefixes() throws {
        let package = try playStoreImage()
        let xml = PackageXMLWriter.document(for: package)
        let document = try XMLDocument(xmlString: xml)
        let root = try #require(document.rootElement())

        #expect(root.localName == "repository")
        #expect(root.uri == PackageXMLWriter.commonNamespace)
        let license = try #require(root.elements(forName: "license").first)
        #expect(license.stringValue == package.license?.text)
        #expect(xml.contains("xmlns:sys-img=\"http://schemas.android.com/sdk/android/repo/sys-img2/04\""))
        #expect(xml.contains("<dependencies>"))
    }

    @Test func escapesSpecialCharacters() {
        #expect(PackageXMLWriter.escape(#"a<b>&"c""#) == "a&lt;b&gt;&amp;&quot;c&quot;")
    }
}

struct LicenseStoreTests {
    let license = License(id: "android-sdk-license", text: "Terms")
    let store = LicenseStore(fileSystem: LiveFileSystem())

    func location(_ temp: TemporaryDirectory) -> SDKLocation {
        SDKLocation(
            sdkRoot: temp.url, sdkSource: .defaultLocation,
            avdHome: temp.appending("avd", isDirectory: true), avdSource: .defaultLocation
        )
    }

    @Test func hashMatchesSDKManagerAlgorithm() {
        // SHA-1 of the UTF-8 text, as `License.getLicenseHash()` in the Android tools.
        #expect(LicenseStore.hash(of: License(id: "x", text: "abc")) == "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    @Test func acceptingAppendsToExistingHashes() throws {
        let temp = try TemporaryDirectory()
        try temp.write("\n24333f8a63b6825ea9c5514f83c2829b004d1fee", to: "licenses/android-sdk-license")
        let location = location(temp)

        #expect(!store.isAccepted(license, in: location))
        try store.accept(license, in: location)
        #expect(store.isAccepted(license, in: location))

        let text = try String(contentsOf: temp.appending("licenses/android-sdk-license"), encoding: .utf8)
        #expect(text.hasPrefix("\n24333f8a63b6825ea9c5514f83c2829b004d1fee\n"))
        #expect(text.hasSuffix(LicenseStore.hash(of: license)))

        // Accepting twice doesn't duplicate the hash.
        try store.accept(license, in: location)
        let again = try String(contentsOf: temp.appending("licenses/android-sdk-license"), encoding: .utf8)
        #expect(again == text)
    }

    @Test func acceptingCreatesTheFile() throws {
        let temp = try TemporaryDirectory()
        try store.accept(license, in: location(temp))
        #expect(store.isAccepted(license, in: location(temp)))
    }
}

/// Opt-in: `ADH_INTEGRATION=1 swift test --filter GoogleToolsCompatibility`.
/// Checks that Google's `sdkmanager` accepts a `package.xml` written by the app (needs cmdline-tools + Java).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ADH_INTEGRATION"] == "1"))
struct GoogleToolsCompatibilityTests {
    @Test func sdkmanagerListsWrittenPackage() async throws {
        let sdk = try #require(ProcessInfo.processInfo.environment["ANDROID_HOME"])
        let sdkmanager = URL(filePath: sdk).appending(path: "cmdline-tools/latest/bin/sdkmanager")
        let temp = try TemporaryDirectory()
        let package = try PackageXMLWriterTests().playStoreImage()
        let folder = temp.appending("system-images/android-36/google_apis_playstore/arm64-v8a", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PackageXMLWriter.document(for: package).write(
            to: folder.appending(path: "package.xml"), atomically: true, encoding: .utf8)

        let output = temp.appending("out.txt")
        try await ProcessRunner.run(
            sdkmanager,
            arguments: ["--list_installed", "--sdk_root=\(temp.url.path(percentEncoded: false))"],
            logFile: output
        )
        let text = try String(contentsOf: output, encoding: .utf8)
        #expect(text.contains("system-images;android-36;google_apis_playstore;arm64-v8a"))
    }
}
