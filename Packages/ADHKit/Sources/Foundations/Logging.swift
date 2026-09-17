public import os

public enum ADHLog {
    public static let subsystem = "io.github.najm101.AndroidDeviceHub"

    /// A logger for one module. Never log tokens or file contents.
    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
