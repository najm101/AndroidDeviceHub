import Foundation

public extension Array where Element == RemotePackage {
    /// The newest package at `path` in `channel` or a more stable one.
    func latest(path: String, upTo channel: ReleaseChannel = .stable) -> RemotePackage? {
        filter { $0.path == path && $0.channel <= channel }
            .max { $0.revision < $1.revision }
    }
}

public extension Array where Element == LocalPackage {
    func package(at path: String) -> LocalPackage? {
        first { $0.path == path }
    }
}
