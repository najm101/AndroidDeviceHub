import AppKit
import DesignSystem
import SDKDomain
import SwiftUI

extension ImageServices {
    /// A short name for badges and menus.
    var shortTitle: String {
        switch self {
        case .googlePlay: "Google Play"
        case .googleAPIs: "Google APIs"
        case .plainAndroid: "Open Source"
        }
    }

    var tint: Color {
        switch self {
        case .googlePlay: .green
        case .googleAPIs: .blue
        case .plainAndroid: .teal
        }
    }
}

/// The icon for a system image flavor: the Android robot for open source images, braces for Google
/// APIs and a play triangle for Google Play.
struct ImageServicesGlyph: View {
    let services: ImageServices

    var body: some View {
        switch services {
        case .plainAndroid:
            AndroidRobotHead()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: 13, height: 13)
        case .googleAPIs:
            Image(systemName: "curlybraces")
        case .googlePlay:
            Image(systemName: "play.fill")
        }
    }
}

/// A small capsule naming one image flavor and whether it is installed. Clicking it chooses that flavor.
struct ImageServicesBadge: View {
    let services: ImageServices
    let isInstalled: Bool
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.xSmall) {
                ImageServicesGlyph(services: services)
                    .foregroundStyle(services.tint)
                Text(services.shortTitle)
                Image(systemName: isInstalled ? Symbol.success : Symbol.download)
                    .foregroundStyle(isInstalled ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            }
            .font(.callout)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.xxSmall + 1)
            .background {
                Capsule().fill(isSelected ? AnyShapeStyle(services.tint.opacity(0.18)) : AnyShapeStyle(.quaternary))
            }
            .overlay {
                if isSelected {
                    Capsule().strokeBorder(services.tint.opacity(0.6))
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(services.title): \(isInstalled ? "installed" : "not installed")")
        .accessibilityLabel(services.title)
        .accessibilityValue(isInstalled ? "Installed" : "Not installed")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One glyph per image flavor, drawn into a single image for menu items: colored when installed, gray
/// when it needs a download, and left blank when the flavor doesn't exist for that level.
@MainActor
struct APIAvailabilityIcon {
    let services: [ImageServices]
    let offered: Set<ImageServices>
    let installed: Set<ImageServices>

    var image: Image {
        let renderer = ImageRenderer(content: glyphs)
        renderer.scale = 2
        guard let image = renderer.nsImage else { return Image(systemName: Symbol.download) }
        image.accessibilityDescription = accessibilityDescription
        return Image(nsImage: image)
    }

    private var glyphs: some View {
        HStack(spacing: Spacing.xSmall) {
            ForEach(services) { services in
                ImageServicesGlyph(services: services)
                    .frame(width: 13, height: 13)
                    .foregroundStyle(color(for: services))
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.vertical, 1)
    }

    private func color(for services: ImageServices) -> Color {
        if installed.contains(services) { return services.tint }
        return offered.contains(services) ? Color.gray.opacity(0.7) : .clear
    }

    private var accessibilityDescription: String {
        services.filter(offered.contains).map { services in
            "\(services.title) \(installed.contains(services) ? "installed" : "not installed")"
        }
        .joined(separator: ", ")
    }
}
