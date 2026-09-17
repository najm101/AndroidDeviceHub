public import DeviceDomain

/// A device action that needs a dialog before it runs.
public enum DeviceActionRequest: Identifiable, Hashable {
    case rename(Device)
    case duplicate(Device)
    case wipeData(Device)
    case remove(Device)

    public var id: String {
        switch self {
        case let .rename(device): "rename-\(device.id)"
        case let .duplicate(device): "duplicate-\(device.id)"
        case let .wipeData(device): "wipe-\(device.id)"
        case let .remove(device): "remove-\(device.id)"
        }
    }

    var device: Device {
        switch self {
        case let .rename(device), let .duplicate(device), let .wipeData(device), let .remove(device): device
        }
    }
}
