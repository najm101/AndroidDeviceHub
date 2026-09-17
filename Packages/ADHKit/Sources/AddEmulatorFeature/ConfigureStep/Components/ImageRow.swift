import DesignSystem
import Foundations
import PackageInstallUI
import SDKDomain
import SwiftUI

struct ImageRow: View {
    let entry: SystemImageEntry
    let isSelected: Bool
    let installs: any InstallCoordinating
    let select: () -> Void

    var body: some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(entry.displayName)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isInstalled {
                Label("Installed", systemImage: Symbol.success)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .font(.callout)
            } else if let remote = entry.remote {
                PackageInstallButton(remote.archive.size.formattedFileSize, package: remote, coordinator: installs)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Select", select)
    }

    private var detail: String {
        var parts = [entry.details.abi.rawValue]
        if let level = entry.details.extensionLevel {
            parts.append("Extension \(level)")
        }
        if let stage = entry.details.stage.label {
            parts.append(stage)
        }
        if let revision = entry.installed?.revision ?? entry.remote?.revision {
            parts.append("Revision \(revision.major)")
        }
        return parts.joined(separator: " · ")
    }
}
