import DesignSystem
public import SwiftUI

/// The Connect Real Device dialog. Not implemented yet.
public struct ConnectDeviceView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView(
            "Connect Real Device", systemImage: "cable.connector",
            description: Text("USB and Wi-Fi pairing for physical devices."))
    }
}
