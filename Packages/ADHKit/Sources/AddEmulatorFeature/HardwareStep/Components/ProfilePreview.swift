import DesignSystem
import DeviceActionsUI
import SDKDomain
import SwiftUI

struct ProfilePreview: View {
    let profile: HardwareProfile?

    var body: some View {
        VStack(spacing: Spacing.medium) {
            if let profile {
                DeviceSilhouette(
                    aspectRatio: CGFloat(profile.widthPixels) / CGFloat(profile.heightPixels),
                    style: profile.formFactor.frameStyle(isRound: profile.isRound)
                ) {
                    Image(systemName: profile.formFactor.symbolName)
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
                .frame(height: 200)
                VStack(spacing: Spacing.xSmall) {
                    Text(profile.name)
                        .font(.headline)
                    Text("\(profile.sizeText) · \(profile.resolutionText) · \(profile.density) dpi")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(profile.playStore ? "Google Play supported" : "No Google Play")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            } else {
                ContentUnavailableView("No Device Selected", systemImage: "iphone")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, Spacing.small)
    }
}
