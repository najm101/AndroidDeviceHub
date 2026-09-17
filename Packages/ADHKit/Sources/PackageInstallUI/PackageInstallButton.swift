import DesignSystem
import Foundations
public import SDKDomain
public import SwiftUI

/// Install control for one SDK package: shows the license when needed, then progress, cancel and errors.
public struct PackageInstallButton: View {
    private let package: RemotePackage
    private let title: String
    private let coordinator: any InstallCoordinating

    @State private var pendingLicense: License?
    @State private var isCheckingLicense = false
    @State private var licenseError: String?

    public init(_ title: String = "Install", package: RemotePackage, coordinator: any InstallCoordinating) {
        self.title = title
        self.package = package
        self.coordinator = coordinator
    }

    public var body: some View {
        Group {
            if let progress = coordinator.activeInstalls[package.path] {
                InstallProgressView(progress: progress) {
                    coordinator.cancelInstall(of: package.path)
                }
            } else {
                HStack(spacing: Spacing.small) {
                    if let failure = coordinator.failures[package.path] ?? licenseError {
                        Image(systemName: Symbol.warning)
                            .foregroundStyle(.yellow)
                            .help(failure)
                            .accessibilityLabel("Install failed: \(failure)")
                    }
                    Button {
                        Task { await begin() }
                    } label: {
                        Label(buttonTitle, systemImage: Symbol.download)
                    }
                    .disabled(isCheckingLicense)
                    .help("\(package.displayName) · \(package.archive.size.formattedFileSize)")
                }
            }
        }
        .sheet(item: $pendingLicense) { license in
            LicenseAgreementSheet(
                title: package.displayName,
                text: license.text,
                onAccept: { Task { await accept(license) } },
                onDecline: { pendingLicense = nil }
            )
        }
    }

    private var buttonTitle: String {
        coordinator.failures[package.path] == nil ? title : "Retry"
    }

    private func begin() async {
        isCheckingLicense = true
        defer { isCheckingLicense = false }
        licenseError = nil
        if let license = await coordinator.pendingLicense(for: package) {
            pendingLicense = license
        } else {
            coordinator.install(package)
        }
    }

    private func accept(_ license: License) async {
        pendingLicense = nil
        do {
            try await coordinator.acceptLicense(license)
            coordinator.install(package)
        } catch {
            licenseError = error.localizedDescription
        }
    }
}
