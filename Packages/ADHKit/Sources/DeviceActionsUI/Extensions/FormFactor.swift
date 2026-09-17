public import DesignSystem
public import SDKDomain

extension FormFactor {
    /// The drawn frame that fits this kind of device.
    public func frameStyle(isRound: Bool) -> DeviceFrameStyle {
        switch self {
        case .phone: .phone
        case .foldable: .foldable
        case .tablet, .xr: .tablet
        case .wear: isRound ? .roundWatch : .squareWatch
        case .tv: .tv
        case .automotive: .automotive
        case .desktop: .desktop
        }
    }
}
