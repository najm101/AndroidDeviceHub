@preconcurrency import AVFoundation
import CoreVideo
public import DeviceDomain
public import Foundation
import IOSurface
public import Observation

/// Records a device's screen to an H.264 `.mp4` from its frame stream.
@MainActor
@Observable
public final class ScreenRecorder {
    public enum Failure: LocalizedError {
        case noFrames
        case writerFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noFrames: "No frames were recorded."
            case let .writerFailed(reason): "The recording couldn't be saved: \(reason)"
            }
        }
    }

    public private(set) var startDate: Date?
    @ObservationIgnored private var task: Task<URL, any Error>?

    public init() {}

    public var isRecording: Bool { startDate != nil }

    /// Starts recording `session` into `url` with the quality's size, frame rate and bit rate.
    public func start(session: any DeviceSession, to url: URL, quality: RecordingQuality = .standard) {
        guard task == nil else { return }
        let display = session.displaySize
        let longest = max(display.width, display.height)
        let side = min(longest, quality.maximumSide)
        let frames = session.frames(maxPixels: PixelSize(width: side, height: side))
        startDate = .now
        task = Task.detached {
            try await Self.write(frames: frames, to: url, quality: quality)
        }
    }

    /// Stops recording and returns the saved file.
    public func stop() async throws -> URL {
        guard let task else { throw Failure.noFrames }
        self.task = nil
        startDate = nil
        task.cancel()
        return try await task.value
    }

    private nonisolated static func write(
        frames: AsyncStream<ScreenFrame>, to url: URL, quality: RecordingQuality
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: url)
        var writer: AVAssetWriter?
        var receiver: AVAssetWriterInput.PixelBufferReceiver?
        var firstTime: CMTime?
        var lastAppended: CMTime?
        let minimumInterval = CMTime(value: 1, timescale: quality.framesPerSecond)
        var size = CVImageSize.zero

        for await frame in frames {
            if Task.isCancelled { break }
            // Encoders need even sizes.
            let frameSize = CVImageSize(width: frame.width & ~1, height: frame.height & ~1)
            if writer == nil {
                let newWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
                let input = AVAssetWriterInput(
                    mediaType: .video,
                    outputSettings: [
                        AVVideoCodecKey: AVVideoCodecType.h264,
                        AVVideoWidthKey: frameSize.width,
                        AVVideoHeightKey: frameSize.height,
                        AVVideoCompressionPropertiesKey: [
                            AVVideoAverageBitRateKey: quality.bitsPerSecond,
                            AVVideoExpectedSourceFrameRateKey: quality.framesPerSecond,
                        ],
                    ])
                let attributes = CVPixelBufferCreationAttributes(
                    pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
                    size: frameSize
                )
                receiver = newWriter.inputPixelBufferReceiver(for: input, pixelBufferAttributes: attributes)
                try newWriter.start()
                newWriter.startSession(atSourceTime: .zero)
                writer = newWriter
                size = frameSize
            }
            // A rotation changes the frame size; keep the first orientation and skip the others.
            guard frameSize == size, let receiver, let pool = receiver.pixelBufferPool else { continue }

            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let start = firstTime ?? now
            firstTime = start
            let time = CMTimeSubtract(now, start)
            if let lastAppended, CMTimeSubtract(time, lastAppended) < minimumInterval {
                continue
            }
            var buffer = try pool.makeMutablePixelBuffer()
            copy(frame, into: &buffer)
            // `appendImmediately` returns false when the encoder is busy; that frame is dropped.
            if try receiver.appendImmediately(CVReadOnlyPixelBuffer(buffer), with: time) {
                lastAppended = time
            }
        }

        guard let writer, let receiver else { throw Failure.noFrames }
        receiver.finish()
        await writer.finishWriting()
        if writer.status != .completed {
            throw Failure.writerFailed(writer.error?.localizedDescription ?? "unknown error")
        }
        return url
    }

    /// Copies the frame so later frames reusing the same surface don't change what was recorded.
    private nonisolated static func copy(_ frame: ScreenFrame, into buffer: inout CVMutablePixelBuffer) {
        IOSurfaceLock(frame.surface, .readOnly, nil)
        defer { IOSurfaceUnlock(frame.surface, .readOnly, nil) }
        let source = IOSurfaceGetBaseAddress(frame.surface)
        let sourceStride = IOSurfaceGetBytesPerRow(frame.surface)
        buffer.accessUnsafeMutableRawPlaneBytes { planes in
            guard let plane = planes.first, let destination = plane.bytes.baseAddress else { return }
            let rows = min(plane.properties.size.height, frame.height)
            let length = min(plane.properties.bytesPerRow, sourceStride, plane.properties.size.width * 4)
            for row in 0..<rows {
                memcpy(destination + row * plane.properties.bytesPerRow, source + row * sourceStride, length)
            }
        }
    }
}
