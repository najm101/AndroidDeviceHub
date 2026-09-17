public import SwiftUI

/// Spacing scale used throughout the app.
public enum Spacing {
    public static let xxSmall: CGFloat = 2
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xLarge: CGFloat = 24
    public static let xxLarge: CGFloat = 32
}

public enum CornerRadius {
    public static let small: CGFloat = 6
    public static let medium: CGFloat = 10
    public static let large: CGFloat = 16
}

public enum Layout {
    public static let sidebarMinWidth: CGFloat = 220
    public static let sidebarIdealWidth: CGFloat = 250
    public static let inspectorWidth: CGFloat = 300
    public static let inspectorMinWidth: CGFloat = 260
    /// Sidebar, inspector and the workspace footer must fit side by side. Narrower windows make
    /// AppKit's constraint passes loop until it throws (seen at 840 pt with a running device).
    public static let mainWindowMinWidth: CGFloat = 900
    public static let mainWindowMinHeight: CGFloat = 560
    public static let sheetWidth: CGFloat = 760
    public static let onboardingWidth: CGFloat = 640
}
