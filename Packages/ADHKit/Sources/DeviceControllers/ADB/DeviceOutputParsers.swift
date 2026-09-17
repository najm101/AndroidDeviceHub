import DeviceDomain
import Foundation

/// Parsers for the few device commands whose output has a fixed, machine-readable format.
enum DeviceOutputParsers {
    /// `[ro.product.model]: [Pixel 9]` lines.
    static func properties(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("["), let keyEnd = line.range(of: "]: [") else { continue }
            let key = line[line.index(after: line.startIndex)..<keyEnd.lowerBound]
            var value = line[keyEnd.upperBound...]
            if value.hasSuffix("]") { value = value.dropLast() }
            result[String(key)] = String(value)
        }
        return result
    }

    /// `package:/data/app/~~x==/com.foo-y==/base.apk=com.foo versionCode:12 uid:10123`
    static func packages(_ text: String, thirdParty: Set<String>) -> [InstalledApp] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasPrefix("package:") else { return nil }
            let fields = line.dropFirst("package:".count).split(separator: " ")
            guard let first = fields.first else { return nil }
            let path: String?
            let name: String
            if let equals = first.lastIndex(of: "=") {
                path = String(first[..<equals])
                name = String(first[first.index(after: equals)...])
            } else {
                path = nil
                name = String(first)
            }
            var attributes: [String: String] = [:]
            for field in fields.dropFirst() {
                let pair = field.split(separator: ":", maxSplits: 1)
                if pair.count == 2 { attributes[String(pair[0])] = String(pair[1]) }
            }
            return InstalledApp(
                packageName: name,
                uid: attributes["uid"].flatMap { Int($0.split(separator: ",").first ?? "") },
                versionCode: attributes["versionCode"].flatMap { Int($0) },
                apkPath: path,
                isSystem: !thirdParty.contains(name)
            )
        }
    }

    /// Package names from `pm list packages` without extra columns.
    static func packageNames(_ text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: \.isNewline).compactMap { line in
                line.hasPrefix("package:") ? String(line.dropFirst("package:".count)) : nil
            })
    }

    /// `\tUserInfo{10:Work profile:1030} running`
    static func users(_ text: String) -> [DeviceUser] {
        let managedProfile = 0x20
        let profile = 0x1000
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let open = line.range(of: "UserInfo{"), let close = line.lastIndex(of: "}") else { return nil }
            let body = line[open.upperBound..<close]
            guard let firstColon = body.firstIndex(of: ":"), let lastColon = body.lastIndex(of: ":"),
                firstColon < lastColon, let id = Int(body[..<firstColon])
            else { return nil }
            let name = String(body[body.index(after: firstColon)..<lastColon])
            let flags = Int(body[body.index(after: lastColon)...], radix: 16) ?? 0
            return DeviceUser(
                id: id,
                name: name,
                isRunning: line[close...].contains("running"),
                isProfile: flags & managedProfile != 0 || flags & profile != 0
            )
        }
    }

    /// The last integer in the text (`Maximum supported users: 4` → 4).
    static func lastInteger(_ text: String) -> Int? {
        text.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
    }

    /// Splits combined output at `@@` marker lines.
    static func sections(_ text: String, marker: String = "@@") -> [String] {
        var result: [String] = [""]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == marker {
                result.append("")
            } else {
                result[result.count - 1] += line + "\n"
            }
        }
        return result
    }

    // MARK: - Dropbox

    static let crashTags: [String: CrashReport.Kind] = [
        "data_app_crash": .appCrash,
        "system_app_crash": .appCrash,
        "system_server_crash": .systemCrash,
        "data_app_anr": .appNotResponding,
        "system_app_anr": .appNotResponding,
        "system_server_anr": .appNotResponding,
        "data_app_native_crash": .nativeCrash,
        "system_app_native_crash": .nativeCrash,
        "SYSTEM_TOMBSTONE": .nativeCrash,
    ]

    private static let separator = "========================================"

    /// Entries from `dumpsys dropbox --print <tag>` (possibly several calls concatenated).
    static func crashReports(_ text: String, timeZone: TimeZone = .current) -> [CrashReport] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var reports: [CrashReport] = []
        var header: Substring?
        var body: [Substring] = []

        func flush() {
            defer {
                header = nil
                body = []
            }
            // `2026-09-17 10:31:55 data_app_crash (text, 1234 bytes)`
            guard let header else { return }
            let fields = header.split(separator: " ", maxSplits: 3)
            guard fields.count >= 3, let date = formatter.date(from: "\(fields[0]) \(fields[1])"),
                let kind = crashTags[String(fields[2])]
            else { return }
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // Entries the device couldn't read come back as a single `*** java.io…Exception` line.
            guard !text.isEmpty, !(text.hasPrefix("***") && !text.contains("\n")) else { return }
            reports.append(
                CrashReport(
                    id: "\(fields[2])@\(fields[0])T\(fields[1])#\(reports.count)",
                    kind: kind,
                    tag: String(fields[2]),
                    date: date,
                    process: process(in: text),
                    text: text
                ))
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == separator {
                flush()
                header = nil
                body = []
                // The next line is the header.
                header = ""
            } else if header == "" {
                header = line
            } else if header != nil {
                // Another `dumpsys` call starts with its summary.
                if line.hasPrefix("Drop box contents:") {
                    flush()
                } else {
                    body.append(line)
                }
            }
        }
        flush()
        return removingDuplicateTombstones(reports).sorted { $0.date > $1.date }
    }

    /// A native app crash is stored twice: as `*_native_crash` and as `SYSTEM_TOMBSTONE`. Keep the first.
    static func removingDuplicateTombstones(_ reports: [CrashReport]) -> [CrashReport] {
        let native = Set(
            reports.filter { $0.tag != "SYSTEM_TOMBSTONE" && $0.kind == .nativeCrash }
                .map { "\($0.date.timeIntervalSince1970)|\($0.process ?? "")" })
        return reports.filter { report in
            report.tag != "SYSTEM_TOMBSTONE"
                || !native.contains("\(report.date.timeIntervalSince1970)|\(report.process ?? "")")
        }
    }

    /// `Process: com.foo`, `Cmdline: com.foo`, or `>>> com.foo <<<` in tombstones.
    static func process(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline).prefix(40) {
            for prefix in ["Process: ", "Cmdline: ", "Package: "] where line.hasPrefix(prefix) {
                let value = line.dropFirst(prefix.count).split(separator: " ").first.map(String.init)
                if let value, !value.isEmpty { return value }
            }
            if let start = line.range(of: ">>> "), let end = line.range(of: " <<<") {
                return String(line[start.upperBound..<end.lowerBound])
            }
        }
        return nil
    }

    // MARK: - Bug reports

    enum BugReportLine: Equatable {
        case progress(Double)
        case finished(path: String)
        case failed(String)
    }

    /// `bugreportz -p` prints `PROGRESS:5/100`, then `OK:<path>` or `FAIL:<reason>`.
    static func bugReportLine(_ line: some StringProtocol) -> BugReportLine? {
        if line.hasPrefix("PROGRESS:") {
            let parts = line.dropFirst("PROGRESS:".count).split(separator: "/").compactMap { Double($0) }
            guard parts.count == 2, parts[1] > 0 else { return nil }
            return .progress(min(1, parts[0] / parts[1]))
        }
        if line.hasPrefix("OK:") { return .finished(path: String(line.dropFirst(3))) }
        if line.hasPrefix("FAIL:") { return .failed(String(line.dropFirst(5))) }
        return nil
    }

    // MARK: - Resources

    /// `/proc/meminfo` value in bytes (`MemTotal:  2021944 kB`).
    static func memInfo(_ text: String, key: String) -> Int64? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix(key + ":") {
            return lastInteger(String(line)).map { Int64($0) * 1024 }
        }
        return nil
    }

    /// `df -k <path>` → (total, used) in bytes, from the last line.
    static func diskUsage(_ text: String) -> (total: Int64, used: Int64)? {
        guard let line = text.split(whereSeparator: \.isNewline).last else { return nil }
        let numbers = line.split(separator: " ").compactMap { Int64($0) }
        guard numbers.count >= 2 else { return nil }
        return (numbers[0] * 1024, numbers[1] * 1024)
    }

    /// `Physical size: 1080x2400` (a later `Override size:` line wins).
    static func screenSize(_ text: String) -> String? {
        text.split(whereSeparator: \.isNewline).last { $0.contains("size:") }
            .flatMap { $0.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) }
    }
}
