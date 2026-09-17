// swift-tools-version: 6.2
import PackageDescription

// MARK: - Module graph
//
// Layer 0  Foundations, DesignSystem
// Layer 1  SDKDomain, DeviceDomain                      (definitions only)
// Layer 2  SDK*, AVDStore, HardwareProfiles, ...        (implement the domain protocols)
// Layer 3  *Feature                                     (UI + @Observable models, domain protocols only)
//
// Features never depend on other features or on Layer 2 modules.
// Scripts/check-deps.sh enforces the same rules for imports.

let package = Package(
    name: "ADHKit",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ADHKit", targets: [
            // Infrastructure the app composes
            "Foundations", "DesignSystem", "PackageInstallUI", "DeviceActionsUI", "SDKDomain", "DeviceDomain",
            "SDKLocator", "SDKCatalog", "SDKInstaller", "AVDStore", "HardwareProfiles", "SetupChecks",
            "EmulatorRuntime", "ADBClient", "ADBRuntime", "DeviceControllers",
            // Features
            "OnboardingFeature", "DeviceListFeature", "AddEmulatorFeature", "ConnectDeviceFeature",
            "DeviceWorkspaceFeature", "DeviceSettingsFeature", "ReportsFeature", "DeviceInfoFeature",
            "FilesFeature", "ComponentsFeature", "PreferencesFeature",
        ]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.4.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.9.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.4.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.38.0"),
    ],
    targets: []
)

// MARK: - Layer 0

package.targets += [
    .target(name: "Foundations"),
    .target(name: "DesignSystem", dependencies: ["Foundations"]),
]

// MARK: - Shared UI (reusable views used by several features; no feature logic)

package.targets += [
    .target(name: "PackageInstallUI", dependencies: ["Foundations", "DesignSystem", "SDKDomain"]),
    .target(name: "DeviceActionsUI", dependencies: ["Foundations", "DesignSystem", "SDKDomain", "DeviceDomain"]),
]

// MARK: - Layer 1 (domain)

package.targets += [
    .target(name: "SDKDomain", dependencies: ["Foundations"]),
    .target(name: "DeviceDomain", dependencies: ["Foundations", "SDKDomain"]),
]

// MARK: - Layer 2 (data & infrastructure)

package.targets += [
    .target(name: "SDKLocator", dependencies: ["Foundations", "SDKDomain"]),
    .target(name: "SDKCatalog", dependencies: ["Foundations", "SDKDomain"]),
    .target(name: "SDKInstaller", dependencies: [
        "Foundations", "SDKDomain",
        .product(name: "ZIPFoundation", package: "ZIPFoundation"),
    ]),
    .target(name: "AVDStore", dependencies: ["Foundations", "SDKDomain"]),
    .target(name: "HardwareProfiles", dependencies: ["SDKDomain"], resources: [.process("Resources")]),
    .target(name: "SetupChecks", dependencies: ["Foundations", "SDKDomain"]),
    .target(name: "EmulatorRuntime", dependencies: ["Foundations", "SDKDomain"]),
    .target(name: "DeviceControllers", dependencies: [
        "Foundations", "SDKDomain", "DeviceDomain", "AVDStore", "EmulatorRuntime", "EmulatorGRPC", "VideoCanvas",
        "ADBClient", "ADBRuntime", "APKMetadata",
        .product(name: "ZIPFoundation", package: "ZIPFoundation"),
    ]),
    .target(name: "EmulatorGRPC", dependencies: [
        "Foundations",
        .product(name: "GRPCCore", package: "grpc-swift-2"),
        .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
        .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
    ]),
    .target(name: "ADBClient", dependencies: ["Foundations"]),
    .target(name: "APKMetadata"),
    .target(name: "ADBRuntime", dependencies: ["Foundations", "ADBClient"]),
    .target(name: "ScrcpyClient", dependencies: ["Foundations", "ADBClient"]),
    .target(name: "VideoCanvas", dependencies: ["Foundations", "DesignSystem", "DeviceDomain"]),
]

// MARK: - Layer 3 (features)

let featureBase: [Target.Dependency] = [
    "Foundations", "DesignSystem", "PackageInstallUI", "DeviceActionsUI", "SDKDomain", "DeviceDomain",
]

package.targets += [
    .target(name: "OnboardingFeature", dependencies: featureBase),
    .target(name: "DeviceListFeature", dependencies: featureBase),
    .target(name: "AddEmulatorFeature", dependencies: featureBase),
    .target(name: "ConnectDeviceFeature", dependencies: featureBase),
    .target(name: "DeviceWorkspaceFeature", dependencies: featureBase + ["VideoCanvas"]),
    .target(name: "DeviceSettingsFeature", dependencies: featureBase),
    .target(name: "ReportsFeature", dependencies: featureBase),
    .target(name: "DeviceInfoFeature", dependencies: featureBase),
    .target(name: "FilesFeature", dependencies: featureBase),
    .target(name: "ComponentsFeature", dependencies: featureBase),
    .target(name: "PreferencesFeature", dependencies: featureBase),
]

// MARK: - Tests

package.targets += [
    // Fakes and fixture helpers shared by the test targets.
    .target(
        name: "ADHTestSupport",
        dependencies: ["Foundations", "SDKDomain", "DeviceDomain"],
        path: "Tests/ADHTestSupport"
    ),

    .testTarget(name: "FoundationsTests", dependencies: ["ADHTestSupport", "Foundations"]),
    .testTarget(name: "SDKDomainTests", dependencies: ["ADHTestSupport", "SDKDomain"]),
    .testTarget(name: "SDKLocatorTests", dependencies: ["ADHTestSupport", "SDKLocator", "SDKDomain"]),
    .testTarget(name: "SDKCatalogTests", dependencies: ["ADHTestSupport", "SDKCatalog", "SDKDomain"]),
    .testTarget(name: "SDKInstallerTests", dependencies: ["ADHTestSupport", "SDKInstaller", "SDKCatalog", "SDKDomain", "Foundations"]),
    .testTarget(name: "AVDStoreTests", dependencies: ["ADHTestSupport", "AVDStore", "SDKDomain", "Foundations"]),
    .testTarget(name: "HardwareProfilesTests", dependencies: ["ADHTestSupport", "HardwareProfiles", "SDKDomain"]),
    .testTarget(name: "SetupChecksTests", dependencies: ["ADHTestSupport", "SetupChecks", "SDKDomain", "Foundations"]),
    .testTarget(name: "ADBClientTests", dependencies: ["ADBClient"]),
    .testTarget(name: "APKMetadataTests", dependencies: ["ADHTestSupport", "APKMetadata", "ADBClient"]),
    .testTarget(name: "EmulatorRuntimeTests", dependencies: ["ADHTestSupport", "EmulatorRuntime", "Foundations", "SDKDomain"]),
    .testTarget(name: "DeviceControllersTests", dependencies: [
        "ADHTestSupport", "DeviceControllers", "DeviceDomain", "SDKDomain", "AVDStore", "EmulatorRuntime", "HardwareProfiles",
        "EmulatorGRPC",
    ]),
    .testTarget(name: "DeviceListFeatureTests", dependencies: ["ADHTestSupport", "DeviceListFeature", "DeviceDomain", "SDKDomain"]),
    .testTarget(name: "DeviceSettingsFeatureTests", dependencies: ["ADHTestSupport", "DeviceSettingsFeature", "DeviceDomain", "Foundations"]),
    .testTarget(name: "InspectorFeaturesTests", dependencies: [
        "ADHTestSupport", "DeviceInfoFeature", "FilesFeature", "ReportsFeature", "DeviceDomain",
    ]),
    .testTarget(name: "DeviceWorkspaceFeatureTests", dependencies: ["DeviceWorkspaceFeature"]),
    .testTarget(name: "AddEmulatorFeatureTests", dependencies: ["ADHTestSupport", "AddEmulatorFeature", "DeviceDomain", "SDKDomain"]),
    .testTarget(name: "OnboardingFeatureTests", dependencies: ["ADHTestSupport", "OnboardingFeature", "SDKDomain", "DeviceDomain"]),
]

// MARK: - Shared settings

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(.defaultIsolation(nil))
    settings.append(.enableUpcomingFeature("ExistentialAny"))
    settings.append(.enableUpcomingFeature("InternalImportsByDefault"))
    target.swiftSettings = settings
}
