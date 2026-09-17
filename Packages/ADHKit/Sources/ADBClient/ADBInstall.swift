public import Foundation

/// Installing APKs by streaming them to the package manager (no temporary copy on the device).
extension ADBDevice {
    /// Installs one app from one or more APK files (a base APK plus its splits).
    public func install(_ apks: [URL], user: Int? = nil, progress: ADBProgress? = nil) async throws {
        guard !apks.isEmpty else { return }
        let abb = (try? await features())?.contains("abb_exec") ?? false
        let sizes = try apks.map { Int64(try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        let total = sizes.reduce(0, +)
        let userArguments = user.map { ["--user", String($0)] } ?? []

        if apks.count == 1 {
            let output = try await execute(
                Self.command(["package", "install", "-S", String(total)] + userArguments, abb: abb),
                abb: abb, input: apks[0], size: total, progress: progress
            )
            try PackageManagerOutput.check(output)
            return
        }

        let created = try await execute(
            Self.command(["package", "install-create", "-S", String(total)] + userArguments, abb: abb), abb: abb)
        try PackageManagerOutput.check(created)
        guard let session = PackageManagerOutput.sessionID(created) else {
            throw ADBError.protocolViolation("install session")
        }
        do {
            var offset: Int64 = 0
            for (index, apk) in apks.enumerated() {
                let base = offset
                var splitProgress: ADBProgress?
                if let progress {
                    splitProgress = { sent, _ in progress(base + sent, total) }
                }
                let arguments = [
                    "package", "install-write", "-S", String(sizes[index]), String(session),
                    "\(index)_\(apk.lastPathComponent)", "-",
                ]
                let output = try await execute(
                    Self.command(arguments, abb: abb), abb: abb, input: apk, size: sizes[index],
                    progress: splitProgress
                )
                try PackageManagerOutput.check(output)
                offset += sizes[index]
            }
            try PackageManagerOutput.check(
                try await execute(Self.command(["package", "install-commit", String(session)], abb: abb), abb: abb))
        } catch {
            _ = try? await execute(Self.command(["package", "install-abandon", String(session)], abb: abb), abb: abb)
            throw error
        }
    }

    /// `abb_exec` separates arguments with NUL bytes; `exec` runs `cmd` through the shell.
    static func command(_ arguments: [String], abb: Bool) -> String {
        abb ? arguments.joined(separator: "\u{0}") : "cmd " + arguments.map(shellQuoted).joined(separator: " ")
    }
}

/// The package manager's one-line results (`Success`, `Failure [REASON: detail]`).
public enum PackageManagerOutput {
    public static func check(_ output: String) throws {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.contains(where: { $0.hasPrefix("Success") }) { return }
        let failure = lines.first { $0.hasPrefix("Failure") || $0.hasPrefix("Error") || $0.hasPrefix("Exception") }
        throw ADBError.failed(readableFailure(failure ?? lines.last ?? "The package manager didn't report success."))
    }

    /// `Success: created install session [1234]` → 1234
    static func sessionID(_ output: String) -> Int? {
        guard let open = output.firstIndex(of: "["), let close = output[open...].firstIndex(of: "]") else {
            return nil
        }
        return Int(output[output.index(after: open)..<close])
    }

    /// `Failure [INSTALL_FAILED_OLDER_SDK: …]` → a sentence people can act on.
    static func readableFailure(_ line: String) -> String {
        let known: [String: String] = [
            "INSTALL_FAILED_OLDER_SDK": "The app needs a newer Android version.",
            "INSTALL_FAILED_NO_MATCHING_ABIS": "The app doesn't include code for this device's CPU.",
            "INSTALL_FAILED_UPDATE_INCOMPATIBLE":
                "An app with the same name but a different signature is installed. Uninstall it first.",
            "INSTALL_FAILED_VERSION_DOWNGRADE": "A newer version of the app is already installed.",
            "INSTALL_FAILED_INSUFFICIENT_STORAGE": "The device doesn't have enough free space.",
            "INSTALL_PARSE_FAILED_NOT_APK": "The file isn't a valid APK.",
            "INSTALL_PARSE_FAILED_NO_CERTIFICATES": "The APK isn't signed.",
            "INSTALL_FAILED_TEST_ONLY": "The APK is marked test-only.",
            "INSTALL_FAILED_MISSING_SPLIT": "Some split APKs are missing.",
        ]
        if let match = known.first(where: { line.contains($0.key) }) {
            return match.value
        }
        return line
    }
}
