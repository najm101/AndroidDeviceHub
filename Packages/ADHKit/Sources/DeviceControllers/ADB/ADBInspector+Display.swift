public import DeviceDomain

// Screen size and density overrides with `wm`, for emulators and phones alike.
extension ADBInspector: DisplayOverriding {
    public func displayMetrics() async throws -> DisplayMetrics {
        async let size = device.run("wm size")
        async let density = device.run("wm density")
        guard let metrics = DeviceOutputParsers.displayMetrics(size: try await size, density: try await density) else {
            throw DeviceSettingsError.rejected("The device didn't report its screen size.")
        }
        return metrics
    }

    public func setDisplayOverride(_ configuration: DisplayConfiguration?) async throws {
        guard let configuration else {
            try await device.run("wm size reset")
            try await device.run("wm density reset")
            return
        }
        if let problem = configuration.validationError {
            throw DeviceSettingsError.invalidValue(problem)
        }
        try await device.run("wm size \(configuration.size.width)x\(configuration.size.height)")
        try await device.run("wm density \(configuration.density)")
    }
}
