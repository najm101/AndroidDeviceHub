public import DeviceDomain
public import Foundation

// Screen size and density overrides with `wm`, for emulators and phones alike.
extension ADBInspector: DisplayOverriding {
    public func displayMetrics() async throws -> DisplayMetrics {
        async let size = device.run("wm size")
        async let density = device.run("wm density")
        guard let metrics = DeviceOutputParsers.displayMetrics(size: try await size, density: try await density) else {
            throw DeviceSettingsError.rejected("The device didn't report its screen size.")
        }
        knownDisplayMetrics = metrics
        return metrics
    }

    public func setDisplayOverride(_ configuration: DisplayConfiguration?) async throws {
        if let configuration {
            if let problem = configuration.validationError {
                throw DeviceSettingsError.invalidValue(problem)
            }
            try await device.run("wm size \(configuration.size.width)x\(configuration.size.height)")
            try await device.run("wm density \(configuration.density)")
        } else {
            try await device.run("wm size reset")
            try await device.run("wm density reset")
        }
        // Read back what the device actually uses; it may round or refuse parts of the request.
        _ = try await displayMetrics()
    }
}
