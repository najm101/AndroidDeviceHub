import Foundation

/// An editable `key=value` file that keeps unknown keys, comments and order intact.
///
/// AVD folders use two styles: `<id>.ini` writes `key=value`, `config.ini` writes `key = value`.
/// The style of an existing file is kept; new files use the given style.
struct IniDocument: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        case compact
        case spaced

        var separator: String { self == .compact ? "=" : " = " }
    }

    private enum Line: Equatable, Sendable {
        case entry(key: String, value: String)
        case other(String)
    }

    private var lines: [Line]
    private(set) var style: Style

    init(style: Style) {
        lines = []
        self.style = style
    }

    init(text: String, defaultStyle: Style = .spaced) {
        var detected: Style?
        lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map { raw in
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";"), let equals = line.firstIndex(of: "=") else {
                return .other(line)
            }
            if detected == nil {
                detected = line[..<equals].hasSuffix(" ") ? .spaced : .compact
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? .other(line) : .entry(key: key, value: value)
        }
        // A trailing newline produces one empty line; don't keep it twice.
        if case .other("") = lines.last { lines.removeLast() }
        style = detected ?? defaultStyle
    }

    subscript(key: String) -> String? {
        get {
            for case let .entry(entryKey, value) in lines where entryKey == key {
                return value
            }
            return nil
        }
        set {
            let index = lines.firstIndex {
                if case let .entry(entryKey, _) = $0 { return entryKey == key }
                return false
            }
            switch (index, newValue) {
            case let (index?, value?): lines[index] = .entry(key: key, value: value)
            case let (index?, nil): lines.remove(at: index)
            case let (nil, value?): lines.append(.entry(key: key, value: value))
            case (nil, nil): break
            }
        }
    }

    var keys: [String] {
        lines.compactMap {
            if case let .entry(key, _) = $0 { return key }
            return nil
        }
    }

    func int(_ key: String) -> Int? {
        self[key].flatMap { Int($0) }
    }

    func bool(_ key: String) -> Bool? {
        switch self[key]?.lowercased() {
        case "yes", "true": true
        case "no", "false": false
        default: nil
        }
    }

    var text: String {
        lines.map { line in
            switch line {
            case let .entry(key, value): "\(key)\(style.separator)\(value)"
            case let .other(text): text
            }
        }
        .joined(separator: "\n") + "\n"
    }
}

/// Parses emulator size values such as `512M`, `6G`, `6442450944` or `512MB`.
enum SizeValue {
    static func bytes(_ text: String) -> Int64? {
        let value = text.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = value.prefix { $0.isNumber }
        guard let number = Int64(digits) else { return nil }
        let unit = value.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        switch unit {
        case "": return number
        case "K", "KB": return number * 1024
        case "M", "MB": return number * 1024 * 1024
        case "G", "GB": return number * 1024 * 1024 * 1024
        default: return nil
        }
    }
}
