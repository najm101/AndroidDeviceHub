import Foundation
import Foundations

enum CaptureFolder {
    static func url(preferences: any KeyValueStore) -> URL {
        if let path = preferences.string(forKey: PreferenceKey.captureFolder), !path.isEmpty {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        return URL.desktopDirectory
    }
}
