import DesignSystem
import DeviceDomain
import PackageInstallUI
import SDKDomain
import SwiftUI

/// What the screen area shows when the live screen isn't available.
struct CanvasOverlay: View {
    let model: DeviceWorkspaceModel
    let device: Device

    var body: some View {
        VStack(spacing: Spacing.medium) {
            switch device.state {
            case .stopped:
                stoppedControls
            case .starting:
                ProgressView()
                Text("Starting…")
                    .foregroundStyle(.secondary)
            case .running(inAppControl: true):
                ProgressView()
                Text("Connecting…")
                    .foregroundStyle(.secondary)
            case .running(inAppControl: false):
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Running in Another App")
                    .font(.headline)
                Text("Shut it down there and start it here to see its screen in this window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case let .needsAttention(problem):
                attention(problem)
            }
        }
        .padding(Spacing.large)
    }

    private var stoppedControls: some View {
        VStack(spacing: Spacing.medium) {
            Button {
                model.start(.normal)
            } label: {
                Label("Start", systemImage: Symbol.start)
                    .frame(minWidth: 110)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .disabled(!model.availability(.start).isAvailable)

            Button("Cold Boot") { model.start(.coldBoot) }
                .buttonStyle(.borderless)
                .disabled(!model.availability(.coldBoot).isAvailable)
                .help("Start without restoring the last saved state")
        }
    }

    @ViewBuilder
    private func attention(_ problem: DeviceProblem) -> some View {
        Image(systemName: Symbol.warning)
            .font(.system(size: 30))
            .foregroundStyle(.yellow)
        Text(problem.message)
            .font(.headline)
            .multilineTextAlignment(.center)
        if case let .missingSystemImage(sysdir) = problem {
            Text(sysdir)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            if let package = model.missingImagePackage {
                PackageInstallButton(
                    "Install \(package.archive.size.formatted(.byteCount(style: .file)))",
                    package: package,
                    coordinator: model.installs
                )
            } else if model.isLookingUpImage {
                ProgressView().controlSize(.small)
            } else {
                Text("This image isn't available for download anymore.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
