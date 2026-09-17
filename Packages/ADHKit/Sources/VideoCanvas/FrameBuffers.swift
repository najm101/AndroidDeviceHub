import Accelerate
import CoreVideo
public import Foundation
public import IOSurface

/// A file mapped into memory that the emulator writes frames into (`ImageTransport.MMAP`).
public final class SharedFrameFile: @unchecked Sendable {
    public let url: URL
    public let capacity: Int
    private let descriptor: Int32
    private let pointer: UnsafeMutableRawPointer

    public enum Failure: Error {
        case cannotCreate(errno: Int32)
    }

    /// Creates (or truncates) the file and maps `capacity` bytes.
    public init(url: URL, capacity: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path(percentEncoded: false), O_RDWR | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else { throw Failure.cannotCreate(errno: errno) }
        guard ftruncate(descriptor, off_t(capacity)) == 0,
            let mapped = mmap(nil, capacity, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0),
            mapped != MAP_FAILED
        else {
            let error = errno
            close(descriptor)
            throw Failure.cannotCreate(errno: error)
        }
        self.url = url
        self.capacity = capacity
        self.descriptor = descriptor
        pointer = mapped
    }

    /// The `file:///` handle the emulator expects.
    public var handle: String { url.absoluteString }

    public var bytes: UnsafeRawPointer { UnsafeRawPointer(pointer) }

    deinit {
        munmap(pointer, capacity)
        close(descriptor)
        try? FileManager.default.removeItem(at: url)
    }
}

/// Reuses a few BGRA IOSurfaces so frames don't allocate.
public final class SurfacePool: @unchecked Sendable {
    private var surfaces: [IOSurfaceRef] = []
    private var width = 0
    private var height = 0
    private var next = 0
    private let lock = NSLock()
    private let count: Int

    public init(count: Int = 3) {
        self.count = count
    }

    public func surface(width: Int, height: Int) -> IOSurfaceRef? {
        lock.withLock {
            if width != self.width || height != self.height || surfaces.isEmpty {
                surfaces = (0..<count).compactMap { _ in Self.makeSurface(width: width, height: height) }
                self.width = width
                self.height = height
                next = 0
            }
            guard !surfaces.isEmpty else { return nil }
            defer { next = (next + 1) % surfaces.count }
            return surfaces[next]
        }
    }

    static func makeSurface(width: Int, height: Int) -> IOSurfaceRef? {
        let properties: [CFString: Any] = [
            kIOSurfaceWidth: width,
            kIOSurfaceHeight: height,
            kIOSurfaceBytesPerElement: 4,
            kIOSurfacePixelFormat: kCVPixelFormatType_32BGRA,
        ]
        return IOSurfaceCreate(properties as CFDictionary)
    }
}

public enum PixelConversion {
    /// Copies an RGBA buffer into a BGRA surface, optionally flipping it vertically.
    public static func copyRGBA(
        from source: UnsafeRawPointer,
        width: Int,
        height: Int,
        bottomUp: Bool,
        into surface: IOSurfaceRef
    ) {
        IOSurfaceLock(surface, [], nil)
        defer { IOSurfaceUnlock(surface, [], nil) }

        let stride = IOSurfaceGetBytesPerRow(surface)
        var sourceBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: source),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
        )
        var destination = vImage_Buffer(
            data: IOSurfaceGetBaseAddress(surface),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: stride
        )
        let map: [UInt8] = [2, 1, 0, 3]
        vImagePermuteChannels_ARGB8888(&sourceBuffer, &destination, map, vImage_Flags(kvImageNoFlags))
        if bottomUp {
            vImageVerticalReflect_ARGB8888(&destination, &destination, vImage_Flags(kvImageNoFlags))
        }
    }
}
