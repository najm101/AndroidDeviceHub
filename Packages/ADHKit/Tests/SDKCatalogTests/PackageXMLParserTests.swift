import ADHTestSupport
import Foundation
import SDKDomain
import Testing

@testable import SDKCatalog

struct PackageXMLParserTests {
    let armHost = PackageXMLParser.Host(os: "macosx", arch: "aarch64", abis: ["arm64-v8a"])
    let intelHost = PackageXMLParser.Host(os: "macosx", arch: "x64", abis: ["x86_64", "x86"])
    let repositoryURL = URL(string: "https://dl.google.com/android/repository/repository2-3.xml")!
    let imagesURL = URL(
        string: "https://dl.google.com/android/repository/sys-img/google_apis_playstore/sys-img2-4.xml")!

    @Test func parsesEmulatorForAppleSilicon() throws {
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/repository2-3.xml"), baseURL: repositoryURL, host: armHost
        )
        let emulator = try #require(packages.latest(path: "emulator"))
        #expect(emulator.kind == .emulator)
        #expect(emulator.channel == .stable)
        #expect(
            emulator.archive.url.absoluteString.hasPrefix(
                "https://dl.google.com/android/repository/emulator-darwin_aarch64"))
        #expect(emulator.license?.id == "android-sdk-license")
        #expect(emulator.license?.text.hasPrefix("Terms and Conditions") == true)
    }

    @Test func picksIntelArchiveOnIntel() throws {
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/repository2-3.xml"), baseURL: repositoryURL, host: intelHost
        )
        let emulator = try #require(packages.latest(path: "emulator"))
        #expect(emulator.archive.url.lastPathComponent.contains("darwin_x64"))
    }

    @Test func parsesPlatformToolsWithoutArchitecture() throws {
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/repository2-3.xml"), baseURL: repositoryURL, host: armHost
        )
        let tools = try #require(packages.latest(path: "platform-tools"))
        #expect(tools.kind == .platformTools)
        #expect(tools.archive.url.lastPathComponent.hasSuffix("-darwin.zip"))
        #expect(tools.archive.size > 1_000_000)
    }

    @Test func parsesSystemImagesForHostABIOnly() throws {
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/sys-img2-4-google_apis_playstore.xml"), baseURL: imagesURL, host: armHost
        )
        #expect(!packages.isEmpty)
        #expect(packages.allSatisfy { $0.systemImage?.abi == .arm64 })

        let android16 = try #require(
            packages.first { $0.path == "system-images;android-36;google_apis_playstore;arm64-v8a" })
        let details = try #require(android16.systemImage)
        #expect(details.apiLevel == APILevel(major: 36))
        #expect(details.extensionLevel == 17)
        #expect(details.hasPlayStore)
        #expect(!details.usesSixteenKBPages)
        #expect(details.stage == .stable)
        #expect(details.sysdir == "system-images/android-36/google_apis_playstore/arm64-v8a/")
        #expect(android16.license?.id == "android-sdk-arm-dbt-license")
        #expect(
            android16.archive.url.absoluteString
                == "https://dl.google.com/android/repository/sys-img/google_apis_playstore/arm64-v8a-36_r07.zip")
        #expect(android16.dependencies.first?.path == "emulator")
    }

    @Test func recognizesExtensionPreviewAndPageSizeVariants() throws {
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/sys-img2-4-google_apis_playstore.xml"), baseURL: imagesURL, host: armHost
        )
        let extensionImage = try #require(packages.first { $0.path.contains("android-36-ext19") }?.systemImage)
        #expect(extensionImage.apiLevel == APILevel(major: 36))
        #expect(!extensionImage.isBaseExtension)

        let pageSize = try #require(
            packages.first { $0.path == "system-images;android-36;google_apis_playstore_ps16k;arm64-v8a" }?.systemImage)
        #expect(pageSize.usesSixteenKBPages)

        let beta = try #require(packages.first { $0.path.contains("beta") }?.systemImage)
        #expect(beta.stage.isPrerelease)
    }

    @Test func keepsTypeDetailsForPackageXML() throws {
        let packages = try PackageXMLParser.remotePackages(
            fromXML: Fixtures.data("catalog/sys-img2-4-google_apis_playstore.xml"), baseURL: imagesURL, host: armHost
        )
        let image = try #require(
            packages.first { $0.path == "system-images;android-36;google_apis_playstore;arm64-v8a" })
        #expect(image.localPackageXML.contains("<extension-level>17</extension-level>"))
        #expect(image.localPackageXML.contains("<uses-license ref=\"android-sdk-arm-dbt-license\""))
        #expect(!image.localPackageXML.contains("<archives>"))
        #expect(image.namespaceDeclarations["sys-img"] == "http://schemas.android.com/sdk/android/repo/sys-img2/04")
    }

    @Test func parsesInstalledPackageXML() throws {
        let directory = URL(filePath: "/sdk/emulator")
        let package = try #require(
            PackageXMLParser.localPackage(
                fromXML: Fixtures.data("sdk/emulator.package.xml"), directory: directory
            ))
        #expect(package.kind == .emulator)
        #expect(package.revision == PackageRevision(major: 36, minor: 5, micro: 11))
    }

    @Test func listsSystemImageSites() throws {
        let sites = try SiteList.systemImageSites(
            fromXML: Fixtures.data("catalog/addons_list-6.xml"),
            baseURL: RemoteSDKCatalog.defaultBaseURL
        )
        #expect(
            sites.contains(
                URL(string: "https://dl.google.com/android/repository/sys-img/google_apis_playstore/sys-img2-4.xml")!))
        #expect(!sites.contains { $0.absoluteString.contains("_atd") })
        #expect(!sites.contains { $0.absoluteString.contains("addon2") })
    }
}

struct SourcePropertiesTests {
    @Test func parsesLegacySystemImage() throws {
        let text = """
            Pkg.Desc=Google Play ARM 64 v8a System Image
            Pkg.Revision=9
            AndroidVersion.ApiLevel=30
            SystemImage.Abi=arm64-v8a
            SystemImage.TagId=google_apis_playstore
            SystemImage.TagDisplay=Google Play
            """
        let directory = URL(filePath: "/sdk/system-images/android-30/google_apis_playstore/arm64-v8a")
        let package = try #require(SourceProperties.package(from: text, directory: directory))
        #expect(package.path == "system-images;android-30;google_apis_playstore;arm64-v8a")
        #expect(package.systemImage?.apiLevel == APILevel(major: 30))
        #expect(package.systemImage?.hasPlayStore == true)
    }
}
