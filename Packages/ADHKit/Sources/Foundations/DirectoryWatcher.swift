public import Foundation

/// Emits a value whenever the contents of a directory change (files added, removed or renamed).
///
/// Creation is lazy: if the directory does not exist yet, the stream simply finishes and the
/// caller can retry after creating it.
public enum DirectoryWatcher {
    public static func changes(of directory: URL) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let descriptor = open(directory.path(percentEncoded: false), O_EVTONLY)
            guard descriptor >= 0 else {
                continuation.finish()
                return
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .link],
                queue: DispatchQueue(label: "io.github.najm101.AndroidDeviceHub.directory-watcher")
            )
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler { close(descriptor) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }
}
