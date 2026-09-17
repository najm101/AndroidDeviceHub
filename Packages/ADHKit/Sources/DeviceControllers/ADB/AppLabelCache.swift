import ADBClient
import APKMetadata
public import Foundation
import Foundations

/// App display names read from APKs, cached on disk by APK path and version.
///
/// Reads run one at a time, so scrolling a long list doesn't flood the device.
public actor AppLabelCache {
    private let file: URL?
    private var labels: [String: String] = [:]
    /// Keys whose APK has no label, so they aren't read again this session.
    private var missing: Set<String> = []
    private var isLoaded = false
    private var saveTask: Task<Void, Never>?

    public init(file: URL?) {
        self.file = file
    }

    func label(packageName: String, apkPath: String, versionCode: Int?, device: ADBDevice) async -> String? {
        loadIfNeeded()
        let key = "\(device.serial)|\(apkPath)|\(versionCode ?? 0)"
        if let label = labels[key] { return label }
        if missing.contains(key) { return nil }

        let label = await Self.read(apkPath: apkPath, device: device)
        if let label {
            labels[key] = label
            scheduleSave()
        } else {
            missing.insert(key)
        }
        return label
    }

    private static func read(apkPath: String, device: ADBDevice) async -> String? {
        let apk = shellQuoted(apkPath)
        guard let manifest = try? await device.shell("unzip -p \(apk) AndroidManifest.xml").standardOutput,
            let label = try? APKLabelReader.manifestLabel(manifest)
        else { return nil }
        switch label {
        case let .text(text):
            return text
        case let .resource(id):
            guard let table = try? await device.shell("unzip -p \(apk) resources.arsc").standardOutput else {
                return nil
            }
            return (try? APKLabelReader.string(for: id, in: table)) ?? nil
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let file, let data = try? Data(contentsOf: file) else { return }
        labels = (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func scheduleSave() {
        guard let file, saveTask == nil else { return }
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            save(to: file)
        }
    }

    private func save(to file: URL) {
        saveTask = nil
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(labels).write(to: file, options: .atomic)
    }
}
